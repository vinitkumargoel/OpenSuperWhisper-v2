import Combine
import FluidAudio
import Foundation

/// Downloads, tracks and activates speech models for every screen that offers
/// them (onboarding, Settings › Model, the Home set-up list), so a download
/// started in one place shows its progress everywhere.
@MainActor
final class ModelDownloadCenter: ObservableObject {
    static let shared = ModelDownloadCenter()

    struct DownloadError: Identifiable {
        let id = UUID()
        let modelName: String
        let message: String
        let progressAtFailure: Double
        let model: SpeechModel
    }

    @Published private(set) var downloadingID: String?
    @Published private(set) var progress: Double = 0
    /// Bumped when anything on disk or in preferences changes, so views re-read
    /// `isInstalled` / `isActive`.
    @Published private(set) var revision = 0
    @Published var lastError: DownloadError?

    private var downloadTask: Task<Void, Never>?
    private var startedAt: Date?

    private init() {}

    var isDownloading: Bool { downloadingID != nil }

    var downloadingModel: SpeechModel? {
        downloadingID.flatMap(ModelCatalog.model(id:))
    }

    // MARK: - State

    func isInstalled(_ model: SpeechModel) -> Bool {
        _ = revision
        switch model.source {
        case .whisper(let url):
            return WhisperModelManager.shared.isModelDownloaded(name: url.lastPathComponent)
        case .parakeet(let version):
            let asrVersion = AsrModelVersion(appVersion: version)
            return AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: asrVersion), version: asrVersion)
        }
    }

    func isActive(_ model: SpeechModel) -> Bool {
        _ = revision
        return ModelCatalog.activeModel?.id == model.id && isInstalled(model)
    }

    var hasUsableModel: Bool {
        _ = revision
        if let active = ModelCatalog.activeModel { return isInstalled(active) }
        // The bundled tiny Whisper model counts when Whisper is selected.
        return SpeechEngine.current == .whisper && !WhisperModelManager.shared.getAvailableModels().isEmpty
    }

    func installedBytes(_ model: SpeechModel) -> Int64? {
        guard isInstalled(model) else { return nil }
        switch model.source {
        case .whisper(let url):
            let path = WhisperModelManager.shared.modelsDirectory.appendingPathComponent(url.lastPathComponent).path
            return (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? nil
        case .parakeet(let version):
            return Self.directorySize(AsrModels.defaultCacheDirectory(for: AsrModelVersion(appVersion: version)))
        }
    }

    /// "504 MB of 1.2 GB · about 40 s left", when the size is known.
    func progressDetail(for model: SpeechModel) -> String {
        var parts: [String] = []
        if let size = model.sizeMB {
            parts.append("\(ModelCatalog.formatMB(Double(size) * progress)) of \(ModelCatalog.formatMB(Double(size)))")
        } else {
            parts.append("\(Int((progress * 100).rounded()))% downloaded")
        }
        if let startedAt, progress > 0.03 {
            let elapsed = Date().timeIntervalSince(startedAt)
            let remaining = elapsed / progress * (1 - progress)
            parts.append(Self.remainingText(remaining))
        } else {
            parts.append("starting…")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

    /// Downloads `model` and makes it the active model when it finishes.
    func download(_ model: SpeechModel) {
        guard downloadingID == nil else { return }
        downloadingID = model.id
        progress = 0
        startedAt = Date()

        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                switch model.source {
                case .whisper(let url):
                    try await WhisperModelManager.shared.downloadModel(url: url, name: url.lastPathComponent) { value in
                        Task { @MainActor [weak self] in
                            guard let self, self.downloadingID == model.id else { return }
                            self.progress = value
                        }
                    }
                case .parakeet(let version):
                    let asrVersion = AsrModelVersion(appVersion: version)
                    let models = try await AsrModels.downloadAndLoad(version: asrVersion) { update in
                        Task { @MainActor [weak self] in
                            guard let self, self.downloadingID == model.id else { return }
                            self.progress = max(self.progress, update.fractionCompleted)
                        }
                    }
                    try Task.checkCancellation()
                    // Loading once proves the download is usable before we switch to it.
                    let manager = AsrManager(config: .default)
                    try await manager.loadModels(models)
                }
                try Task.checkCancellation()
                self.finish()
                self.activate(model)
            } catch is CancellationError {
                self.finish()
            } catch {
                if Task.isCancelled {
                    self.finish()
                } else {
                    let failedAt = self.progress
                    self.finish()
                    self.lastError = DownloadError(
                        modelName: model.name,
                        message: error.localizedDescription,
                        progressAtFailure: failedAt,
                        model: model
                    )
                }
            }
        }
    }

    func cancel() {
        guard let model = downloadingModel else { return }
        downloadTask?.cancel()
        if let file = model.whisperFileName {
            WhisperModelManager.shared.cancelDownload(name: file)
        }
        finish()
    }

    /// Switches transcription to `model`. The engine is released and reloads
    /// on the next recording.
    func activate(_ model: SpeechModel) {
        let prefs = AppPreferences.shared
        switch model.source {
        case .whisper(let url):
            prefs.selectedEngine = SpeechEngine.whisper.rawValue
            let path = WhisperModelManager.shared.modelsDirectory.appendingPathComponent(url.lastPathComponent).path
            TranscriptionService.shared.reloadModel(with: path)
        case .parakeet(let version):
            prefs.selectedEngine = SpeechEngine.parakeet.rawValue
            prefs.fluidAudioModelVersion = version
            TranscriptionService.shared.reloadEngine()
        }
        refresh()
    }

    /// Changes the engine; the engine's previously chosen model stays selected.
    func selectEngine(_ engine: SpeechEngine) {
        guard SpeechEngine.current != engine else { return }
        AppPreferences.shared.selectedEngine = engine.rawValue
        if engine == .whisper, AppPreferences.shared.selectedWhisperModelPath == nil {
            AppPreferences.shared.selectedWhisperModelPath = WhisperModelManager.shared.getAvailableModels().first?.path
        }
        TranscriptionService.shared.reloadEngine()
        refresh()
    }

    func refresh() { revision += 1 }

    var totalInstalledBytes: Int64 {
        ModelCatalog.all.compactMap { installedBytes($0) }.reduce(0, +)
    }

    // MARK: - Helpers

    private func finish() {
        downloadingID = nil
        progress = 0
        startedAt = nil
        downloadTask = nil
        refresh()
    }

    private static func remainingText(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "about \(max(1, Int(seconds.rounded()))) s left" }
        return "about \(Int((seconds / 60).rounded())) min left"
    }

    private static func directorySize(_ url: URL) -> Int64? {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return nil }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
