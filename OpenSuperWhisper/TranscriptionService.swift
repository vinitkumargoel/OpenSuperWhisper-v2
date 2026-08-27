import AVFoundation
import Foundation

@MainActor
class TranscriptionService: ObservableObject {
    static let shared = TranscriptionService()
    
    @Published private(set) var isTranscribing = false
    @Published private(set) var transcribedText = ""
    @Published private(set) var currentSegment = ""
    @Published private(set) var isLoading = false
    @Published private(set) var progress: Float = 0.0
    @Published private(set) var isConverting = false
    @Published private(set) var conversionProgress: Float = 0.0
    
    private var currentEngine: TranscriptionEngine?
    private var engineLoadTask: Task<TranscriptionEngine, Error>?
    /// Bumped by `releaseEngine`. A load that was in flight across a release
    /// compares generations when it lands and discards its result instead of
    /// quietly reinstating a model the user asked us to give back.
    private var engineGeneration = 0
    private var totalDuration: Float = 0.0
    private var transcriptionTask: Task<String, Error>? = nil
    private var isCancelled = false

    var isEngineLoaded: Bool { currentEngine != nil }

    /// Nothing is loaded at init. The model comes in when recording starts —
    /// see `ModelResidency` — so an idle app holds no ASR weights.
    init() {}

    /// Starts loading in the background and ignores failure; a real error
    /// surfaces at `transcribeAudio`, where there is a user waiting to be told.
    func prewarm() {
        guard currentEngine == nil, engineLoadTask == nil else { return }
        Task { _ = try? await ensureEngineLoaded() }
    }

    /// Frees the model. Safe at any time — the next transcription reloads it.
    func releaseEngine() {
        guard currentEngine != nil || engineLoadTask != nil else { return }
        engineGeneration += 1
        engineLoadTask?.cancel()
        engineLoadTask = nil
        currentEngine?.unload()
        currentEngine = nil
        print("Engine released")
    }

    /// Loads the engine if needed. Concurrent callers await one load rather
    /// than each starting their own.
    @discardableResult
    func ensureEngineLoaded() async throws -> TranscriptionEngine {
        if let currentEngine { return currentEngine }

        let generation = engineGeneration
        if let engineLoadTask {
            let engine = try await engineLoadTask.value
            return try claimLoadedEngine(engine, generation: generation)
        }

        let selectedEngine = AppPreferences.shared.selectedEngine
        print("Loading engine: \(selectedEngine)")
        isLoading = true

        let task = Task<TranscriptionEngine, Error> {
            let engine: TranscriptionEngine = selectedEngine == "fluidaudio"
                ? await FluidAudioEngine()
                : await WhisperEngine()
            try await engine.initialize()
            return engine
        }
        engineLoadTask = task

        do {
            let engine = try await task.value
            isLoading = false
            let claimed = try claimLoadedEngine(engine, generation: generation)
            engineLoadTask = nil
            currentEngine = claimed
            print("Engine loaded: \(selectedEngine)")
            return claimed
        } catch {
            if engineGeneration == generation {
                engineLoadTask = nil
            }
            isLoading = false
            print("Failed to load engine: \(error)")
            throw error
        }
    }

    /// A load that finished after a `releaseEngine` must not resurrect the
    /// model: unload what just landed and let the caller retry from scratch.
    private func claimLoadedEngine(
        _ engine: TranscriptionEngine, generation: Int
    ) throws -> TranscriptionEngine {
        guard engineGeneration == generation else {
            engine.unload()
            throw CancellationError()
        }
        return engine
    }
    
    func cancelTranscription() {
        isCancelled = true
        currentEngine?.cancelTranscription()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        
        isTranscribing = false
        currentSegment = ""
        progress = 0.0
        isCancelled = false
    }
    
    /// Drops the current engine so the next use picks up the new selection.
    /// Deliberately does not reload: nothing is resident while idle, and the
    /// next recording prewarms the new choice anyway.
    func reloadEngine() {
        releaseEngine()
    }
    
    func reloadModel(with path: String) {
        if AppPreferences.shared.selectedEngine == "whisper" {
            AppPreferences.shared.selectedWhisperModelPath = path
            reloadEngine()
        }
    }
    
    func transcribeAudio(url: URL, settings: Settings) async throws -> String {
        await MainActor.run {
            self.progress = 0.0
            self.conversionProgress = 0.0
            self.isConverting = true
            self.isTranscribing = true
            self.transcribedText = ""
            self.currentSegment = ""
            self.isCancelled = false
        }
        
        defer {
            Task { @MainActor in
                self.isTranscribing = false
                self.isConverting = false
                self.currentSegment = ""
                if !self.isCancelled {
                    self.progress = 1.0
                }
                self.transcriptionTask = nil
            }
        }
        
        let durationInSeconds: Float = await (try? Task.detached(priority: .userInitiated) {
            let asset = AVAsset(url: url)
            let duration = try await asset.load(.duration)
            return Float(CMTimeGetSeconds(duration))
        }.value) ?? 0.0
        
        await MainActor.run {
            self.totalDuration = durationInSeconds
        }
        
        // Normally already loaded by the prewarm at recording start; this
        // covers a cold path such as dropping a file onto the app.
        //
        // One retry: a release landing mid-load (memory pressure, or the model
        // being changed in Settings) cancels the load, and the second attempt
        // starts a fresh one rather than failing a transcription for it.
        let engine: TranscriptionEngine
        do {
            engine = try await ensureEngineLoaded()
        } catch is CancellationError {
            guard !isCancelled else { throw CancellationError() }
            engine = try await ensureEngineLoaded()
        }
        
        // Setup progress callback for engines
        if let whisperEngine = engine as? WhisperEngine {
            whisperEngine.onProgressUpdate = { [weak self] newProgress in
                Task { @MainActor in
                    guard let self = self, !self.isCancelled else { return }
                    self.progress = newProgress
                }
            }
            whisperEngine.onSegmentUpdate = { [weak self] partialText in
                Task { @MainActor in
                    guard let self = self, !self.isCancelled else { return }
                    self.currentSegment = partialText
                }
            }
        } else if let fluidEngine = engine as? FluidAudioEngine {
            fluidEngine.onProgressUpdate = { [weak self] newProgress in
                Task { @MainActor in
                    guard let self = self, !self.isCancelled else { return }
                    self.progress = newProgress
                }
            }
        }
        
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            try Task.checkCancellation()
            
            let cancelled = await MainActor.run {
                guard let self = self else { return true }
                return self.isCancelled
            }
            
            guard !cancelled else {
                throw CancellationError()
            }
            
            let result = try await engine.transcribeAudio(url: url, settings: settings)
            
            try Task.checkCancellation()
            
            let finalCancelled = await MainActor.run {
                guard let self = self else { return true }
                return self.isCancelled
            }
            
            await MainActor.run {
                guard let self = self, !self.isCancelled else { return }
                self.transcribedText = result
                self.progress = 1.0
            }
            
            guard !finalCancelled else {
                throw CancellationError()
            }
            
            return result
        }
        
        await MainActor.run {
            self.transcriptionTask = task
        }
        
        do {
            return try await task.value
        } catch is CancellationError {
            await MainActor.run {
                self.isCancelled = true
            }
            throw TranscriptionError.processingFailed
        }
    }
}

enum TranscriptionError: Error {
    case contextInitializationFailed
    case audioConversionFailed
    case processingFailed
}
