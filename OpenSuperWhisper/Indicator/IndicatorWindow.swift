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
    /// A transient message shown just before the pill hides (failure, warning).
    case notice
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
    /// Text shown in the `.notice` state.
    @Published var noticeMessage: String = ""
    /// Drives the notice tint: red for failures, orange for warnings.
    @Published var noticeIsError: Bool = false

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

    /// Holds the pill open for a moment with a short message, then hides it.
    /// Used instead of vanishing silently when something went wrong.
    func showNotice(_ message: String, isError: Bool) {
        noticeMessage = message
        noticeIsError = isError
        state = .notice

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
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
        // Start loading the models now: the user is about to speak for several
        // seconds, which is exactly the window the load needs.
        ModelResidency.shared.recordingDidStart()

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
            ModelResidency.shared.recordingDidCancel()
            showBusyMessage()
            return
        }

        partialText = ""
        state = .decoding
        
        if let tempURL = recorder.stopRecording() {
            Task { [weak self] in
                guard let self = self else { return }
                ModelResidency.shared.pipelineDidBegin()
                defer { ModelResidency.shared.pipelineDidFinish() }

                // When set, the pill shows this briefly and hides itself on a
                // timer, so we must not also hide it immediately below.
                var notice: (message: String, isError: Bool)?

                do {
                    print("start decoding...")
                    let rawText = try await transcriptionService.transcribeAudio(url: tempURL, settings: Settings())
                    ModelResidency.shared.transcriptionDidFinish()
                    var formattingError: Error?
                    let text = await FinalTextProcessor.formatIfNeeded(rawText) {
                        await MainActor.run {
                            self.state = .formatting
                        }
                    } onFormattingFailed: { error in
                        formattingError = error
                    }
                    let duration = await Self.audioDuration(of: tempURL)
                    
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
                            targetAppBundleID: FocusUtils.lastFrontmostBundleID,
                            errorMessage: formattingError?.localizedDescription
                        ))
                    }
                    
                    insertText(text)
                    print("Transcription result: \(text)")

                    // The transcript was delivered, but AI cleanup silently fell
                    // back to raw text — say so instead of leaving the user to
                    // wonder why the formatting looks wrong.
                    if formattingError != nil {
                        notice = ("AI formatting unavailable - pasted raw text", false)
                    }
                } catch {
                    print("Error transcribing audio: \(error)")
                    let duration = await Self.audioDuration(of: tempURL)
                    let saved = await self.recordingStore.saveFailedRecording(
                        tempURL: tempURL,
                        duration: duration,
                        targetAppName: FocusUtils.lastFrontmostAppName,
                        targetAppBundleID: FocusUtils.lastFrontmostBundleID,
                        error: error
                    )
                    notice = saved != nil
                        ? ("Transcription failed - saved to History", true)
                        : ("Transcription failed - audio could not be saved", true)
                }

                await MainActor.run {
                    if let notice {
                        self.showNotice(notice.message, isError: notice.isError)
                    } else {
                        self.delegate?.didFinishDecoding()
                    }
                }
            }
        } else {
            // stopRecording() returns nil for clips under a second - a normal
            // "too short to transcribe" case, not a failure.
            print("Recording too short to transcribe - discarded")
            ModelResidency.shared.recordingDidCancel()

            Task {
                await MainActor.run {
                    self.delegate?.didFinishDecoding()
                }
            }
        }
    }

    /// Best-effort duration of a recorded file; 0 when it cannot be read.
    private static func audioDuration(of url: URL) async -> TimeInterval {
        await (try? Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            return CMTimeGetSeconds(duration)
        }.value) ?? 0.0
    }
    
    func insertText(_ text: String) {
        let finalText = FinalTextProcessor.applyPastePostProcessing(text)
        // Auto-paste only when the user enabled it AND Accessibility is granted
        // (the synthesized ⌘V needs it). Otherwise fall back to clipboard-only so
        // the text is never lost — the user can paste manually.
        if AppPreferences.shared.autoPasteEnabled && AXIsProcessTrusted() {
            // Pasting works by putting the text on the clipboard and sending ⌘V.
            // Whether the previous clipboard comes back afterwards is the user's
            // call: keeping the transcript lets them paste it again elsewhere.
            ClipboardUtil.insertText(
                finalText,
                restoreClipboard: !AppPreferences.shared.keepTranscriptOnClipboard
            )
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
        ModelResidency.shared.recordingDidCancel()
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
    var tint: Color
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 7, height: 7)
            .overlay(
                Circle()
                    .stroke(tint.opacity(0.25), lineWidth: 4)
            )
            .opacity(pulsing ? 0.25 : 1.0)
            .animation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}

/// A small animated bar meter reflecting live microphone input level.
struct LevelMeter: View {
    @ObservedObject var recorder: AudioRecorder
    var tint: Color

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
    @Environment(\.palette) private var palette

    /// Measured height of the live transcript block, used to grow the pill.
    @State private var liveTextHeight: CGFloat = 0

    /// Roughly six lines at 12pt; past this the block scrolls instead of growing.
    private let liveTextMaxHeight: CGFloat = 108

    private var hasPartialText: Bool {
        viewModel.state == .decoding && !viewModel.partialText.isEmpty
    }

    /// States that need the wide, vertically-padded pill because their content
    /// wraps onto more than one line.
    private var isWideContent: Bool {
        hasPartialText || viewModel.state == .notice
    }

    var body: some View {

        // One-line states are a capsule, as in the design; once the live
        // transcript wraps, a capsule would bow out absurdly, so the tall pill
        // falls back to a generous rounded rect.
        let rect = RoundedRectangle(cornerRadius: isWideContent ? 18 : 999)

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
                    RecordingIndicator(tint: palette.live)

                    Text(viewModel.elapsedString)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .fixedSize()

                    Spacer(minLength: 6)

                    LevelMeter(recorder: viewModel.recorder, tint: palette.pillBar)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
            case .decoding:
                // Fixed width, growing height: the live transcript wraps and the
                // pill grows line by line up to `liveTextMaxHeight`, after which
                // it scrolls and stays pinned to the newest words.
                HStack(alignment: .top, spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 20)

                    if hasPartialText {
                        ScrollView(.vertical) {
                            Text(viewModel.partialText)
                                .font(.system(size: 12))
                                .foregroundColor(palette.pillText.opacity(0.7))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .onGeometryChange(for: CGFloat.self) { proxy in
                                    proxy.size.height
                                } action: { height in
                                    liveTextHeight = height
                                }
                        }
                        .frame(height: min(max(liveTextHeight, 16), liveTextMaxHeight))
                        // partialText is a full growing snapshot rebuilt on every
                        // whisper segment, so anchor to the bottom to follow it.
                        .defaultScrollAnchor(.bottom)
                        .scrollIndicators(.never)
                        .scrollDisabled(liveTextHeight <= liveTextMaxHeight)
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
                        .frame(width: 24)

                    Text("Processing...")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            case .notice:
                // Errors are the one case that earns colour; plain notices stay
                // in the pill's own text colour.
                let noticeColor = viewModel.noticeIsError ? palette.danger : palette.pillText
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: viewModel.noticeIsError
                          ? "exclamationmark.triangle.fill"
                          : "info.circle.fill")
                        .foregroundColor(noticeColor)
                        .frame(width: 24)

                    Text(viewModel.noticeMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(noticeColor)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
            case .idle:
                EmptyView()
            }
        }
        .foregroundColor(palette.pillText)
        .tint(palette.pillText)
        .padding(.horizontal, 24)
        .padding(.vertical, isWideContent ? 10 : 0)
        .frame(minHeight: 40)
        .background {
            rect
                .fill(palette.pillFill)
                .overlay { rect.stroke(palette.pillBorder, lineWidth: 1) }
                .shadow(color: .black.opacity(palette.pillShadowOpacity), radius: 12, x: 0, y: 5)
        }
        .clipShape(rect)
        .frame(width: isWideContent ? 340 : 200)
        .scaleEffect(viewModel.isVisible ? 1 : 0.5)
        .offset(y: viewModel.isVisible ? 0 : 20)
        .opacity(viewModel.isVisible ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isVisible)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isWideContent)
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
