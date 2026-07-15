import Cocoa
import Combine
import SwiftUI
import AVFoundation
import ApplicationServices

enum RecordingState {
    case idle
    case connecting
    case recording
    case decoding
    case formatting
    case busy
}

@MainActor
protocol IndicatorViewDelegate: AnyObject {
    
    func didFinishDecoding()
}

@MainActor
class IndicatorViewModel: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var recorder: AudioRecorder = .shared
    @Published var isVisible = false
    @Published var partialText: String = ""

    /// Where the pill anchors inside the transparent panel (set by IndicatorWindowManager).
    var contentAlignment: Alignment = .bottom

    var delegate: IndicatorViewDelegate?
    private var recordingTimer: Timer?
    private var recordingStart: Date?
    private var hideTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    private let recordingStore: RecordingStore
    private let transcriptionService: TranscriptionService
    private let transcriptionQueue: TranscriptionQueue
    
    init() {
        self.recordingStore = RecordingStore.shared
        self.transcriptionService = TranscriptionService.shared
        self.transcriptionQueue = TranscriptionQueue.shared
        
        recorder.$isConnecting
            .receive(on: RunLoop.main)
            .sink { [weak self] isConnecting in
                guard let self = self else { return }
                if isConnecting {
                    self.state = .connecting
                    self.stopRecordingTimer()
                }
            }
            .store(in: &cancellables)
        
        recorder.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] isRecording in
                guard let self = self else { return }
                if isRecording {
                    self.state = .recording
                    self.startRecordingTimer()
                }
            }
            .store(in: &cancellables)

        // Live partial transcript: whisper streams decoded segments while transcribing
        transcriptionService.$currentSegment
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                guard let self = self, self.state == .decoding else { return }
                self.partialText = text
            }
            .store(in: &cancellables)
    }
    
    var isTranscriptionBusy: Bool {
        transcriptionService.isTranscribing || transcriptionQueue.isProcessing
    }

    var elapsedString: String {
        let total = Int(elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
    
    func showBusyMessage() {
        state = .busy
        
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.delegate?.didFinishDecoding()
            }
        }
    }
    
    func startRecording() {
        if isTranscriptionBusy {
            showBusyMessage()
            return
        }

        // Remember which app the user is dictating into, for per-app modes.
        FocusUtils.captureFrontmostApp()

        if MicrophoneService.shared.isActiveMicrophoneRequiresConnection() {
            state = .connecting
            stopRecordingTimer()
        } else {
            state = .recording
            startRecordingTimer()
        }
        
        Task.detached { [recorder] in
            recorder.startRecording()
        }
    }
    
    func startDecoding() {
        stopRecordingTimer()
        
        if isTranscriptionBusy {
            recorder.cancelRecording()
            showBusyMessage()
            return
        }

        partialText = ""
        state = .decoding
        
        if let tempURL = recorder.stopRecording() {
            Task { [weak self] in
                guard let self = self else { return }
                
                do {
                    print("start decoding...")
                    let rawText = try await transcriptionService.transcribeAudio(url: tempURL, settings: Settings())
                    let text = await FinalTextProcessor.formatIfNeeded(rawText) {
                        await MainActor.run {
                            self.state = .formatting
                        }
                    }
                    let duration = await (try? Task.detached(priority: .userInitiated) {
                        let asset = AVURLAsset(url: tempURL)
                        let duration = try await asset.load(.duration)
                        return CMTimeGetSeconds(duration)
                    }.value) ?? 0.0
                    
                    // Create a new Recording instance
                    let timestamp = Date()
                    let fileName = "\(Int(timestamp.timeIntervalSince1970)).wav"
                    let recordingId = UUID()
                    let finalURL = Recording(
                        id: recordingId,
                        timestamp: timestamp,
                        fileName: fileName,
                        transcription: text,
                        rawTranscription: rawText,
                        duration: duration,
                        status: .completed,
                        progress: 1.0,
                        sourceFileURL: nil
                    ).url
                    
                    // Move the temporary recording to final location
                    try recorder.moveTemporaryRecording(from: tempURL, to: finalURL)
                    
                    // Save the recording to store
                    await MainActor.run {
                        self.recordingStore.addRecording(Recording(
                            id: recordingId,
                            timestamp: timestamp,
                            fileName: fileName,
                            transcription: text,
                            rawTranscription: rawText,
                            duration: duration,
                            status: .completed,
                            progress: 1.0,
                            sourceFileURL: nil,
                            targetAppName: FocusUtils.lastFrontmostAppName,
                            targetAppBundleID: FocusUtils.lastFrontmostBundleID
                        ))
                    }
                    
                    insertText(text)
                    print("Transcription result: \(text)")
                } catch {
                    print("Error transcribing audio: \(error)")
                    try? FileManager.default.removeItem(at: tempURL)
                }
                
                await MainActor.run {
                    self.delegate?.didFinishDecoding()
                }
            }
        } else {
            
            print("!!! Not found record url !!!")
            
            Task {
                await MainActor.run {
                    self.delegate?.didFinishDecoding()
                }
            }
        }
    }
    
    func insertText(_ text: String) {
        let finalText = FinalTextProcessor.applyPastePostProcessing(text)
        // Auto-paste only when the user enabled it AND Accessibility is granted
        // (the synthesized ⌘V needs it). Otherwise fall back to clipboard-only so
        // the text is never lost — the user can paste manually.
        if AppPreferences.shared.autoPasteEnabled && AXIsProcessTrusted() {
            ClipboardUtil.insertText(finalText)
        } else {
            ClipboardUtil.copyToClipboard(finalText)
        }
    }
    
    private func startRecordingTimer() {
        recordingTimer?.invalidate()
        recordingStart = Date()
        elapsed = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let start = self.recordingStart else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStart = nil
        elapsed = 0
    }

    func cleanup() {
        stopRecordingTimer()
        hideTimer?.invalidate()
        hideTimer = nil
        cancellables.removeAll()
    }

    func cancelRecording() {
        hideTimer?.invalidate()
        hideTimer = nil
        recorder.cancelRecording()
    }

    @MainActor
    func hideWithAnimation() async {
        await withCheckedContinuation { continuation in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self.isVisible = false
            } completion: {
                continuation.resume()
            }
        }
    }
}

struct RecordingIndicator: View {
    var tint: Color = .red
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        tint.opacity(0.85),
                        tint
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 9, height: 9)
            .shadow(color: tint.opacity(0.7), radius: 5)
            .opacity(pulsing ? 0.25 : 1.0)
            .animation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}

/// A small animated bar meter reflecting live microphone input level.
struct LevelMeter: View {
    @ObservedObject var recorder: AudioRecorder
    var tint: Color = .red

    private let weights: [CGFloat] = [0.5, 0.78, 1.0, 0.78, 0.5]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(weights.indices, id: \.self) { i in
                Capsule()
                    .fill(tint.opacity(0.85))
                    .frame(width: 2.5, height: barHeight(weights[i]))
            }
        }
        .frame(height: 16)
        .animation(.easeOut(duration: 0.08), value: recorder.level)
    }

    private func barHeight(_ weight: CGFloat) -> CGFloat {
        let level = CGFloat(max(0, min(1, recorder.level)))
        let minH: CGFloat = 3
        let maxH: CGFloat = 16
        return minH + (maxH - minH) * level * weight
    }
}

struct IndicatorWindow: View {
    @ObservedObject var viewModel: IndicatorViewModel
    @Environment(\.colorScheme) private var colorScheme

    private var style: IndicatorStyle { IndicatorStyle.current }

    private var hasPartialText: Bool {
        viewModel.state == .decoding && !viewModel.partialText.isEmpty
    }

    var body: some View {

        let rect = RoundedRectangle(cornerRadius: style.cornerRadius)

        VStack(spacing: 12) {
            switch viewModel.state {
            case .connecting:
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 24)
                    
                    Text("Connecting...")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
            case .recording:
                // The pulsing red dot already signals "recording", so we drop the
                // word to keep the pill on one line: dot · timer · level meter.
                HStack(spacing: 8) {
                    RecordingIndicator(tint: style.accent)

                    Text(viewModel.elapsedString)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .fixedSize()

                    Spacer(minLength: 6)

                    LevelMeter(recorder: viewModel.recorder, tint: style.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
            case .decoding:
                // Keep it single-line and horizontal: show the tail of the live
                // transcript (head-truncated) so the pill never grows vertically.
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 20)

                    if hasPartialText {
                        Text(viewModel.partialText)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Transcribing...")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            case .formatting:
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 24)

                    Text("Formatting...")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
            case .busy:
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .foregroundColor(.orange)
                        .frame(width: 24)
                    
                    Text("Processing...")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.orange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
            case .idle:
                EmptyView()
            }
        }
        .foregroundColor(style.textColor)
        .padding(.horizontal, 24)
        .padding(.vertical, hasPartialText ? 10 : 0)
        .frame(minHeight: 36)
        .background {
            rect
                .fill(style.fillColor(colorScheme))
                .background {
                    if style.usesMaterial {
                        rect.fill(Material.thinMaterial)
                    }
                }
                .overlay {
                    if let stroke = style.strokeColor {
                        rect.stroke(stroke, lineWidth: 1.5)
                    }
                }
                .shadow(color: .black.opacity(style.shadowOpacity), radius: 10, x: 0, y: 4)
        }
        .clipShape(rect)
        .frame(width: hasPartialText ? 340 : 200)
        .scaleEffect(viewModel.isVisible ? 1 : 0.5)
        .offset(y: viewModel.isVisible ? 0 : 20)
        .opacity(viewModel.isVisible ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isVisible)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hasPartialText)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: viewModel.contentAlignment)
        .onAppear {
            viewModel.isVisible = true
        }
    }
}

struct IndicatorWindowPreview: View {
    @StateObject private var recordingVM = {
        let vm = IndicatorViewModel()
//        vm.startRecording()
        return vm
    }()
    
    @StateObject private var decodingVM = {
        let vm = IndicatorViewModel()
        vm.startDecoding()
        return vm
    }()
    
    var body: some View {
        VStack(spacing: 20) {
            IndicatorWindow(viewModel: recordingVM)
            IndicatorWindow(viewModel: decodingVM)
        }
        .padding()
        .frame(height: 200)
        .background(Color(.windowBackgroundColor))
    }
}

#Preview {
    IndicatorWindowPreview()
}
