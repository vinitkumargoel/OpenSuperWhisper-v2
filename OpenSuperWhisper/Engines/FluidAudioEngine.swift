import Foundation
import AVFoundation
import FluidAudio

class FluidAudioEngine: TranscriptionEngine {
    var engineName: String { "FluidAudio" }
    
    private var asrManager: AsrManager?
    private var asrModels: AsrModels?
    private var isCancelled = false
    private var transcriptionTask: Task<String, Error>?
    private var progressTask: Task<Void, Never>?
    
    var onProgressUpdate: ((Float) -> Void)?
    
    var isModelLoaded: Bool {
        asrManager != nil
    }
    
    func initialize() async throws {
        let version = AsrModelVersion(appVersion: AppPreferences.shared.fluidAudioModelVersion)

        let models = try await AsrModels.downloadAndLoad(version: version)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        
        asrManager = manager
        asrModels = models
    }
    
    func unload() {
        cancelTranscription()
        progressTask?.cancel()
        progressTask = nil
        asrManager = nil
        asrModels = nil
    }

    func transcribeAudio(url: URL, settings: Settings) async throws -> String {
        guard let asrManager = asrManager else {
            throw TranscriptionError.contextInitializationFailed
        }
        
        isCancelled = false
        
        // Notify start
        onProgressUpdate?(0.02)
        
        guard !isCancelled else {
            throw CancellationError()
        }
        
        // Start progress monitoring task using FluidAudio's transcriptionProgressStream
        let onProgress = onProgressUpdate
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                // Get the real progress stream from FluidAudio
                let progressStream = await asrManager.transcriptionProgressStream
                
                for try await progress in progressStream {
                    guard !Task.isCancelled, !self.isCancelled else { break }
                    
                    // FluidAudio reports 0.0-1.0, we map to 0.05-0.95
                    let scaledProgress = 0.05 + Float(progress) * 0.90
                    
                    await MainActor.run {
                        onProgress?(scaledProgress)
                    }
                }
            } catch {
                // Stream finished or error
            }
        }
        
        defer {
            progressTask?.cancel()
            progressTask = nil
        }
        
        // Perform actual transcription - FluidAudio will emit progress automatically.
        // FluidAudio 0.15.x requires an explicit per-transcription TDT decoder state.
        let decoderLayers = await asrManager.decoderLayerCount
        var decoderState = TdtDecoderState.make(decoderLayers: decoderLayers)
        let result = try await asrManager.transcribe(url, decoderState: &decoderState)
        
        guard !isCancelled else {
            throw CancellationError()
        }
        
        // Finalize
        onProgressUpdate?(0.95)
        
        var processedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if settings.shouldApplyAsianAutocorrect && !processedText.isEmpty {
            processedText = AutocorrectWrapper.format(processedText)
        }
        
        onProgressUpdate?(1.0)
        
        return processedText.isEmpty ? "No speech detected in the audio" : processedText
    }
    
    func cancelTranscription() {
        isCancelled = true
        progressTask?.cancel()
        progressTask = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil
    }
    
    func getSupportedLanguages() -> [String] {
        if AsrModelVersion(appVersion: AppPreferences.shared.fluidAudioModelVersion) == .v2 {
            return ["en"]
        }
        return ["en", "de", "es", "fr", "it", "pt", "ru", "pl", "nl", "tr", "cs", "ar", "zh", "ja", "hu", "fi", "hr", "sk", "sr", "sl", "uk", "ca", "da", "el", "bg"]
    }
}


extension AsrModelVersion {
    /// Maps the version string stored in preferences ("v2", "v3", "ultra")
    /// to FluidAudio's model version. Unknown values fall back to v3.
    init(appVersion: String) {
        switch appVersion {
        case "v2": self = .v2
        case "ultra": self = .ultra
        default: self = .v3
        }
    }
}
