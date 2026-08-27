import Foundation
import AVFoundation
import Combine

@MainActor
class TranscriptionQueue: ObservableObject {
    static let shared = TranscriptionQueue()

    @Published private(set) var isProcessing = false
    @Published private(set) var currentRecordingId: UUID?

    private let transcriptionService: TranscriptionService
    private let recordingStore: RecordingStore
    private var processingTask: Task<Void, Never>?
    private var currentTranscriptionTask: Task<Void, Never>?
    private var cancelledRecordingIds: Set<UUID> = []
    private var progressCancellable: AnyCancellable?

    private init() {
        self.transcriptionService = TranscriptionService.shared
        self.recordingStore = RecordingStore.shared
        setupProgressObserver()
    }
    
    private func setupProgressObserver() {
        progressCancellable = transcriptionService.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newProgress in
                guard let self = self,
                      let recordingId = self.currentRecordingId,
                      newProgress > 0,
                      newProgress < 1.0 else { return }
                
                Task {
                    await self.recordingStore.updateRecordingStatusOnly(
                        recordingId,
                        progress: newProgress,
                        status: .transcribing
                    )
                }
            }
    }

    func cancelRecording(_ recordingId: UUID) {
        cancelledRecordingIds.insert(recordingId)

        if currentRecordingId == recordingId {
            transcriptionService.cancelTranscription()
            currentTranscriptionTask?.cancel()
        }
    }

    private func isRecordingCancelled(_ recordingId: UUID) -> Bool {
        return cancelledRecordingIds.contains(recordingId)
    }

    private func clearCancellation(_ recordingId: UUID) {
        cancelledRecordingIds.remove(recordingId)
    }

    func startProcessingQueue() {
        guard !isProcessing else { return }

        isProcessing = true

        processingTask = Task {
            await cleanupMissingFiles()
            await processQueue()
            isProcessing = false
            processingTask = nil
        }
    }

    private func cleanupMissingFiles() async {
        let pendingRecordings = recordingStore.getPendingRecordings()

        let recordingsToDelete = await Task.detached(priority: .utility) {
            var toDelete: [Recording] = []
            for recording in pendingRecordings {
                guard let sourceURLString = recording.sourceFileURL,
                      !sourceURLString.isEmpty else {
                    toDelete.append(recording)
                    continue
                }

                let sourceURL = URL(fileURLWithPath: sourceURLString)
                if !FileManager.default.fileExists(atPath: sourceURL.path) {
                    toDelete.append(recording)
                }
            }
            return toDelete
        }.value
        
        for recording in recordingsToDelete {
            recordingStore.deleteRecording(recording)
        }
    }

    func addFileToQueue(url: URL) async {
        do {
            let durationInSeconds = await (try? Task.detached(priority: .userInitiated) {
                let asset = AVAsset(url: url)
                let duration = try await asset.load(.duration)
                return CMTimeGetSeconds(duration)
            }.value) ?? 0.0

            let timestamp = Date()
            let fileName = "\(Int(timestamp.timeIntervalSince1970)).wav"
            let id = UUID()

            let recording = Recording(
                id: id,
                timestamp: timestamp,
                fileName: fileName,
                transcription: "",
                rawTranscription: nil,
                duration: durationInSeconds,
                status: .pending,
                progress: 0.0,
                sourceFileURL: url.path
            )

            try await recordingStore.addRecordingSync(recording)

            startProcessingQueue()
        } catch {
            print("Failed to add file to queue: \(error)")
        }
    }

    func requeueRecording(_ recording: Recording) async {
        let sourceURL: URL? = await Task.detached(priority: .userInitiated) {
            if let existingSource = recording.sourceFileURL,
               !existingSource.isEmpty,
               FileManager.default.fileExists(atPath: existingSource) {
                return URL(fileURLWithPath: existingSource)
            } else if FileManager.default.fileExists(atPath: recording.url.path) {
                return recording.url
            }
            return nil
        }.value
        
        guard let sourceURL = sourceURL else {
            // Leave the existing transcript alone — a failed regenerate must
            // never destroy text that was already good.
            await recordingStore.updateRecordingProgressOnlySync(
                recording.id,
                progress: 0.0,
                status: .failed,
                errorMessage: "Cannot regenerate: audio file not found"
            )
            return
        }

        await recordingStore.updateRecordingStatusOnly(
            recording.id,
            progress: 0.0,
            status: .pending,
            isRegeneration: true
        )

        do {
            try await recordingStore.updateSourceFileURL(recording.id, sourceURL: sourceURL.path)
        } catch {
            print("Failed to update source URL: \(error)")
        }

        startProcessingQueue()
    }

    /// Re-runs only the formatting step on the stored raw transcript, using the
    /// backend and style in `options` — the audio is never re-transcribed.
    ///
    /// `rawTranscription` is preserved, so the original stays comparable in the
    /// history panel and the recording can be reformatted again with different
    /// settings. The transient "formatting" state is only broadcast to the UI,
    /// never persisted, so the ASR queue can't mistake the row for pending work.
    func reformatRecording(_ recording: Recording, options: ReformatOptions) async throws {
        let raw = recording.rawTranscription?.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = (raw?.isEmpty == false ? raw! : recording.transcription)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }

        postReformatProgress(recording.id, progress: 0.9, status: .formatting, isRegeneration: true)

        // A reformat is a pipeline like any other: it should load the model it
        // needs and release it again afterwards.
        ModelResidency.shared.pipelineDidBegin()
        defer { ModelResidency.shared.pipelineDidFinish() }

        do {
            let formattedRaw: String
            switch options.backend {
            case .api:
                formattedRaw = try await LLMTextFormatter().format(source, modelOverride: options.model)
            case .s1mini:
                let output = try await S1MiniFormatter.shared.format(
                    source,
                    styling: options.styling,
                    structure: options.structure,
                    context: options.context
                )
                formattedRaw = output.isEmpty ? source : output
            }
            let formatted = VocabularyProcessor.applyConfigured(formattedRaw)
            await recordingStore.updateRecordingProgressOnlySync(
                recording.id,
                transcription: formatted,
                progress: 1.0,
                status: .completed,
                rawTranscription: source,
                // A successful manual reformat clears any stale warning.
                errorMessage: "",
                isRegeneration: false
            )
        } catch {
            postReformatProgress(recording.id, progress: 1.0, status: .completed, isRegeneration: false)
            throw error
        }
    }

    private func postReformatProgress(_ id: UUID, progress: Float, status: RecordingStatus, isRegeneration: Bool) {
        NotificationCenter.default.post(
            name: RecordingStore.recordingProgressDidUpdateNotification,
            object: nil,
            userInfo: [
                "id": id,
                "progress": progress,
                "status": status,
                "isRegeneration": isRegeneration
            ]
        )
    }

    private func processQueue() async {
        while let recording = recordingStore.getNextPendingRecording() {
            currentRecordingId = recording.id
            await processRecording(recording)
            currentRecordingId = nil
        }
    }

    private func processRecording(_ recording: Recording) async {
        if isRecordingCancelled(recording.id) {
            clearCancellation(recording.id)
            return
        }

        guard let sourceURLString = recording.sourceFileURL,
              !sourceURLString.isEmpty else {
            await recordingStore.updateRecordingProgressOnlySync(
                recording.id,
                progress: 0.0,
                status: .failed,
                errorMessage: "Source file not found"
            )
            return
        }

        let sourceURL = URL(fileURLWithPath: sourceURLString)

        let sourceExists = await Task.detached(priority: .userInitiated) {
            FileManager.default.fileExists(atPath: sourceURL.path)
        }.value
        
        guard sourceExists else {
            await recordingStore.updateRecordingProgressOnlySync(
                recording.id,
                progress: 0.0,
                status: .failed,
                errorMessage: "Source file not found"
            )
            return
        }

        let isRegeneration = !recording.transcription.isEmpty && 
            recording.transcription != "In queue..." && 
            recording.transcription != "Starting transcription..."

        if isRegeneration {
            await recordingStore.updateRecordingStatusOnly(
                recording.id,
                progress: 0.0,
                status: .converting
            )
        } else {
            await recordingStore.updateRecordingProgressOnlySync(
                recording.id,
                transcription: "",
                progress: 0.0,
                status: .converting
            )
        }

        currentTranscriptionTask = Task {
            // Dropped files have no recording window to prewarm behind, so the
            // load happens inline — but the release policy still applies.
            ModelResidency.shared.pipelineDidBegin()
            defer { ModelResidency.shared.pipelineDidFinish() }
            do {
                if isRecordingCancelled(recording.id) {
                    return
                }

                if isRecordingCancelled(recording.id) || Task.isCancelled {
                    return
                }

                let settings = Settings()
                let rawText = try await transcriptionService.transcribeAudio(url: sourceURL, settings: settings)
                var formattingError: Error?
                let text = await FinalTextProcessor.formatIfNeeded(rawText) {
                    await self.recordingStore.updateRecordingStatusOnly(
                        recording.id,
                        progress: 0.95,
                        status: .formatting
                    )
                } onFormattingFailed: { error in
                    formattingError = error
                }

                if isRecordingCancelled(recording.id) || Task.isCancelled {
                    return
                }

                let finalURL = recording.url
                try await Task.detached(priority: .userInitiated) {
                    try? FileManager.default.createDirectory(
                        at: Recording.recordingsDirectory,
                        withIntermediateDirectories: true
                    )

                    if sourceURL.path != finalURL.path {
                        if FileManager.default.fileExists(atPath: finalURL.path) {
                            try? FileManager.default.removeItem(at: finalURL)
                        }
                        try FileManager.default.copyItem(at: sourceURL, to: finalURL)
                    }
                }.value

                await recordingStore.updateRecordingProgressOnlySync(
                    recording.id,
                    transcription: text,
                    progress: 1.0,
                    status: .completed,
                    rawTranscription: rawText,
                    // "" clears any stale error from a previous failed attempt.
                    errorMessage: formattingError?.localizedDescription ?? "",
                    isRegeneration: false
                )

            } catch {
                if !isRecordingCancelled(recording.id) && !Task.isCancelled {
                    await recordingStore.updateRecordingProgressOnlySync(
                        recording.id,
                        progress: 0.0,
                        status: .failed,
                        errorMessage: "Failed to transcribe: \(error.localizedDescription)",
                        isRegeneration: false
                    )
                }
            }
        }

        await currentTranscriptionTask?.value
        currentTranscriptionTask = nil
        clearCancellation(recording.id)
    }

}
