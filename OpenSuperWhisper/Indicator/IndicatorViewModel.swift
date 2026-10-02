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
