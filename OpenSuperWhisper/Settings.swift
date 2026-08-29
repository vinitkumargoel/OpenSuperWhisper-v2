import AppKit
import Carbon
import Charts
import Combine
import Foundation
import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import FluidAudio

class SettingsViewModel: ObservableObject {
    @Published var selectedEngine: String {
        didSet {
            AppPreferences.shared.selectedEngine = selectedEngine
            if selectedEngine == "whisper" {
                loadAvailableModels()
            } else {
                initializeFluidAudioModels()
            }
            Task { @MainActor in
                TranscriptionService.shared.reloadEngine()
            }
        }
    }
    
    @Published var fluidAudioModelVersion: String {
        didSet {
            AppPreferences.shared.fluidAudioModelVersion = fluidAudioModelVersion
            if selectedEngine == "fluidaudio" {
                Task { @MainActor in
                    TranscriptionService.shared.reloadEngine()
                }
            }
            initializeFluidAudioModels()
        }
    }
    
    @Published var selectedModelURL: URL? {
        didSet {
            if let url = selectedModelURL {
                AppPreferences.shared.selectedWhisperModelPath = url.path
            }
        }
    }

    @Published var availableModels: [URL] = []
    
    @Published var downloadableModels: [SettingsDownloadableModel] = []
    @Published var downloadableFluidAudioModels: [SettingsFluidAudioModel] = []
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadingModelName: String?
    private var downloadTask: Task<Void, Error>?
    
    @Published var selectedLanguage: String {
        didSet {
            AppPreferences.shared.whisperLanguage = selectedLanguage
            NotificationCenter.default.post(name: .appPreferencesLanguageChanged, object: nil)
        }
    }

    @Published var translateToEnglish: Bool {
        didSet {
            AppPreferences.shared.translateToEnglish = translateToEnglish
        }
    }

    @Published var suppressBlankAudio: Bool {
        didSet {
            AppPreferences.shared.suppressBlankAudio = suppressBlankAudio
        }
    }

    @Published var showTimestamps: Bool {
        didSet {
            AppPreferences.shared.showTimestamps = showTimestamps
        }
    }
    
    @Published var temperature: Double {
        didSet {
            AppPreferences.shared.temperature = temperature
        }
    }

    @Published var noSpeechThreshold: Double {
        didSet {
            AppPreferences.shared.noSpeechThreshold = noSpeechThreshold
        }
    }

    @Published var initialPrompt: String {
        didSet {
            AppPreferences.shared.initialPrompt = initialPrompt
        }
    }

    @Published var useBeamSearch: Bool {
        didSet {
            AppPreferences.shared.useBeamSearch = useBeamSearch
        }
    }

    @Published var beamSize: Int {
        didSet {
            AppPreferences.shared.beamSize = beamSize
        }
    }

    @Published var debugMode: Bool {
        didSet {
            AppPreferences.shared.debugMode = debugMode
        }
    }
    
    @Published var playSoundOnRecordStart: Bool {
        didSet {
            AppPreferences.shared.playSoundOnRecordStart = playSoundOnRecordStart
        }
    }

    @Published var pauseMediaDuringRecording: Bool {
        didSet {
            AppPreferences.shared.pauseMediaDuringRecording = pauseMediaDuringRecording
        }
    }
    
    @Published var useAsianAutocorrect: Bool {
        didSet {
            AppPreferences.shared.useAsianAutocorrect = useAsianAutocorrect
        }
    }
    
    @Published var modifierOnlyHotkey: ModifierKey {
        didSet {
            AppPreferences.shared.modifierOnlyHotkey = modifierOnlyHotkey.rawValue
            NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
        }
    }
    
    @Published var holdToRecord: Bool {
        didSet {
            AppPreferences.shared.holdToRecord = holdToRecord
        }
    }
    
    @Published var addSpaceAfterSentence: Bool {
        didSet {
            AppPreferences.shared.addSpaceAfterSentence = addSpaceAfterSentence
        }
    }

    @Published var autoPasteEnabled: Bool {
        didSet {
            AppPreferences.shared.autoPasteEnabled = autoPasteEnabled
        }
    }

    @Published var keepTranscriptOnClipboard: Bool {
        didSet {
            AppPreferences.shared.keepTranscriptOnClipboard = keepTranscriptOnClipboard
        }
    }

    @Published var dictationCommandsEnabled: Bool {
        didSet {
            AppPreferences.shared.dictationCommandsEnabled = dictationCommandsEnabled
        }
    }

    @Published var historyRetentionDays: Int {
        didSet {
            AppPreferences.shared.historyRetentionDays = historyRetentionDays
            // Apply the new policy immediately rather than only on next launch.
            let days = historyRetentionDays
            Task { @MainActor in
                await RecordingStore.shared.purgeRecordings(olderThanDays: days)
            }
        }
    }

    @Published var indicatorPosition: IndicatorPosition {
        didSet {
            AppPreferences.shared.indicatorPosition = indicatorPosition.rawValue
        }
    }

    private var isRevertingLaunchAtLogin = false

    @Published var launchAtLogin: Bool {
        didSet {
            guard !isRevertingLaunchAtLogin, oldValue != launchAtLogin else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update launch at login: \(error)")
                isRevertingLaunchAtLogin = true
                launchAtLogin = oldValue
                isRevertingLaunchAtLogin = false
            }
        }
    }

    @Published var formattingEnabled: Bool {
        didSet {
            AppPreferences.shared.formattingEnabled = formattingEnabled
        }
    }

    @Published var llmBaseURL: String {
        didSet {
            AppPreferences.shared.llmBaseURL = llmBaseURL
        }
    }

    @Published var llmApiKey: String {
        didSet {
            AppPreferences.shared.llmApiKey = llmApiKey
        }
    }

    @Published var llmModel: String {
        didSet {
            AppPreferences.shared.llmModel = llmModel
        }
    }

    @Published var formattingPrompt: String {
        didSet {
            AppPreferences.shared.formattingPrompt = formattingPrompt
        }
    }

    @Published var vocabularyRules: [VocabularyRule] {
        didSet {
            AppPreferences.shared.vocabularyRules = vocabularyRules
        }
    }

    @Published var formattingModes: [FormattingMode] {
        didSet {
            AppPreferences.shared.formattingModes = formattingModes
        }
    }

    @Published var activeFormattingModeID: String {
        didSet {
            AppPreferences.shared.activeFormattingModeID = activeFormattingModeID
        }
    }

    @Published var autoSwitchFormattingMode: Bool {
        didSet {
            AppPreferences.shared.autoSwitchFormattingMode = autoSwitchFormattingMode
        }
    }

    /// UI-only: which mode is currently open in the editor.
    @Published var editingModeID: String = ""

    @Published var availableLLMModels: [String] = []
    @Published var isFetchingLLMModels: Bool = false
    @Published var llmModelsFetchError: String?

    // MARK: - Formatting backend / on-device model

    @Published var formattingBackend: FormattingBackend {
        didSet {
            AppPreferences.shared.formattingBackendValue = formattingBackend
        }
    }

    @Published var s1MiniVariant: String {
        didSet {
            AppPreferences.shared.s1MiniVariant = s1MiniVariant
        }
    }

    @Published var s1DefaultStyling: S1Styling {
        didSet { AppPreferences.shared.s1DefaultStyling = s1DefaultStyling.rawValue }
    }

    @Published var s1DefaultStructure: S1Structure {
        didSet { AppPreferences.shared.s1DefaultStructure = s1DefaultStructure.rawValue }
    }

    @Published var s1DefaultContext: S1Context {
        didSet { AppPreferences.shared.s1DefaultContext = s1DefaultContext.rawValue }
    }

    @Published var prewarmModelsOnRecord: Bool {
        didSet { AppPreferences.shared.prewarmModelsOnRecord = prewarmModelsOnRecord }
    }

    @Published var modelIdleUnloadSeconds: Int {
        didSet { AppPreferences.shared.modelIdleUnloadSeconds = modelIdleUnloadSeconds }
    }

    // Test-format box, so the whole path can be checked without recording.
    @Published var testInput: String =
        "so um i need to like send the the report by uh friday no wait make that thursday"
    @Published var testOutput: String = ""
    @Published var testError: String?
    @Published var isTesting = false
    @Published var testDuration: String = ""
    @Published var residencySummary: String = ""

    func runFormatTest() {
        guard !isTesting else { return }
        isTesting = true
        testOutput = ""
        testError = nil
        testDuration = ""

        let input = testInput
        let axes = (styling: s1DefaultStyling, structure: s1DefaultStructure, context: s1DefaultContext)
        let backend = formattingBackend

        Task { @MainActor in
            defer { isTesting = false }
            let started = Date()
            do {
                let output: String
                switch backend {
                case .api:
                    output = try await LLMTextFormatter().format(input)
                case .s1mini:
                    output = try await S1MiniFormatter.shared.format(
                        input,
                        styling: axes.styling,
                        structure: axes.structure,
                        context: axes.context
                    )
                }
                let elapsed = Date().timeIntervalSince(started)
                testDuration = String(format: "%.2f s", elapsed)
                // An empty result is what the model returns for filler-only
                // input, so say that rather than showing a blank box.
                testOutput = output.isEmpty ? "(empty — the model read this as filler only)" : output
            } catch {
                testError = error.localizedDescription
            }
            await refreshResidency()
        }
    }

    func refreshResidency() async {
        residencySummary = await ModelResidency.shared.residencySummary()
    }

    func unloadModelsNow() {
        Task { @MainActor in
            TranscriptionService.shared.releaseEngine()
            await S1MiniFormatter.shared.unload()
            await refreshResidency()
        }
    }

    func fetchLLMModels() {
        isFetchingLLMModels = true
        llmModelsFetchError = nil
        let baseURL = llmBaseURL
        let apiKey = llmApiKey
        Task { @MainActor in
            defer { isFetchingLLMModels = false }
            do {
                availableLLMModels = try await LLMTextFormatter.fetchAvailableModels(
                    baseURL: baseURL, apiKey: apiKey)
            } catch {
                availableLLMModels = []
                llmModelsFetchError = error.localizedDescription
            }
        }
    }

    // MARK: - Vocabulary & Modes editing

    func addVocabularyRule() {
        vocabularyRules.append(VocabularyRule())
    }

    func deleteVocabularyRule(_ id: UUID) {
        vocabularyRules.removeAll { $0.id == id }
    }

    func addFormattingMode() {
        let mode = FormattingMode(name: "New Mode", prompt: AppPreferences.defaultFormattingPrompt)
        formattingModes.append(mode)
        editingModeID = mode.id.uuidString
        if activeFormattingModeID.isEmpty {
            activeFormattingModeID = mode.id.uuidString
        }
    }

    func deleteFormattingMode(_ id: String) {
        formattingModes.removeAll { $0.id.uuidString == id }
        if activeFormattingModeID == id {
            activeFormattingModeID = formattingModes.first?.id.uuidString ?? ""
        }
        if editingModeID == id {
            editingModeID = formattingModes.first?.id.uuidString ?? ""
        }
    }

    /// Two-way binding to a field of the mode currently open in the editor.
    func editingModeBinding() -> Binding<FormattingMode>? {
        guard let idx = formattingModes.firstIndex(where: { $0.id.uuidString == editingModeID }) else {
            return nil
        }
        return Binding(
            get: { [weak self] in
                guard let self, self.formattingModes.indices.contains(idx) else {
                    return FormattingMode(name: "", prompt: "")
                }
                return self.formattingModes[idx]
            },
            set: { [weak self] newValue in
                guard let self, self.formattingModes.indices.contains(idx) else { return }
                self.formattingModes[idx] = newValue
            }
        )
    }

    @Published var analyticsSnapshot: AnalyticsSnapshot = .empty
    @Published var isLoadingAnalytics: Bool = false
    @Published var analyticsRange: AnalyticsRange = .month

    init() {
        let prefs = AppPreferences.shared
        self.selectedEngine = prefs.selectedEngine
        self.fluidAudioModelVersion = prefs.fluidAudioModelVersion
        self.selectedLanguage = prefs.whisperLanguage
        self.translateToEnglish = prefs.translateToEnglish
        self.suppressBlankAudio = prefs.suppressBlankAudio
        self.showTimestamps = prefs.showTimestamps
        self.temperature = prefs.temperature
        self.noSpeechThreshold = prefs.noSpeechThreshold
        self.initialPrompt = prefs.initialPrompt
        self.useBeamSearch = prefs.useBeamSearch
        self.beamSize = prefs.beamSize
        self.debugMode = prefs.debugMode
        self.playSoundOnRecordStart = prefs.playSoundOnRecordStart
        self.pauseMediaDuringRecording = prefs.pauseMediaDuringRecording
        self.useAsianAutocorrect = prefs.useAsianAutocorrect
        self.modifierOnlyHotkey = ModifierKey(rawValue: prefs.modifierOnlyHotkey) ?? .none
        self.holdToRecord = prefs.holdToRecord
        self.addSpaceAfterSentence = prefs.addSpaceAfterSentence
        self.autoPasteEnabled = prefs.autoPasteEnabled
        self.keepTranscriptOnClipboard = prefs.keepTranscriptOnClipboard
        self.dictationCommandsEnabled = prefs.dictationCommandsEnabled
        self.historyRetentionDays = prefs.historyRetentionDays
        self.indicatorPosition = IndicatorPosition(rawValue: prefs.indicatorPosition) ?? .nearCursor
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        self.formattingEnabled = prefs.formattingEnabled
        self.llmBaseURL = prefs.llmBaseURL
        self.llmApiKey = prefs.llmApiKey
        self.llmModel = prefs.llmModel
        self.formattingPrompt = prefs.formattingPrompt
        prefs.ensureDefaultFormattingMode()
        self.vocabularyRules = prefs.vocabularyRules
        self.formattingModes = prefs.formattingModes
        self.activeFormattingModeID = prefs.activeFormattingModeID
        self.autoSwitchFormattingMode = prefs.autoSwitchFormattingMode
        self.formattingBackend = prefs.formattingBackendValue
        self.s1MiniVariant = prefs.s1MiniVariant
        self.s1DefaultStyling = S1Styling(rawValue: prefs.s1DefaultStyling) ?? .semiFormal
        self.s1DefaultStructure = S1Structure(rawValue: prefs.s1DefaultStructure) ?? .prose
        self.s1DefaultContext = S1Context(rawValue: prefs.s1DefaultContext) ?? .general
        self.prewarmModelsOnRecord = prefs.prewarmModelsOnRecord
        self.modelIdleUnloadSeconds = prefs.modelIdleUnloadSeconds
        self.editingModeID = prefs.activeFormattingModeID

        if let savedPath = prefs.selectedWhisperModelPath ?? prefs.selectedModelPath {
            self.selectedModelURL = URL(fileURLWithPath: savedPath)
        }
        loadAvailableModels()
        initializeDownloadableModels()
        initializeFluidAudioModels()
        refreshAnalytics()
    }

    /// Clears the stats ledger. Recordings are untouched — this is the opposite
    /// half of the split: deleting history keeps the statistics, and this
    /// clears the statistics while keeping the history.
    func resetStatistics() {
        Task {
            do {
                try await RecordingStore.shared.resetStatistics()
            } catch {
                print("Failed to reset statistics: \(error)")
            }
            await MainActor.run { self.refreshAnalytics() }
        }
    }

    func refreshAnalytics() {
        isLoadingAnalytics = true
        Task {
            do {
                let entries = try await RecordingStore.shared.fetchStatsEntries()
                let snapshot = AnalyticsSnapshot(entries: entries)
                await MainActor.run {
                    self.analyticsSnapshot = snapshot
                    self.isLoadingAnalytics = false
                }
            } catch {
                print("Failed to load analytics: \(error)")
                await MainActor.run {
                    self.analyticsSnapshot = .empty
                    self.isLoadingAnalytics = false
                }
            }
        }
    }
    
    func initializeFluidAudioModels() {
        downloadableFluidAudioModels = SettingsFluidAudioModels.availableModels.map { model in
            var updatedModel = model
            updatedModel.isDownloaded = isFluidAudioModelDownloaded(version: model.version)
            return updatedModel
        }
    }
    
    func isFluidAudioModelDownloaded(version: String) -> Bool {
        let asrVersion: AsrModelVersion = version == "v2" ? .v2 : .v3
        
        // Используем правильный путь к кэшу согласно документации:
        // ~/Library/Application Support/FluidAudio/Models/<version-folder>/
        let cacheDirectory = AsrModels.defaultCacheDirectory(for: asrVersion)
        
        // Проверяем наличие всех необходимых файлов модели
        return AsrModels.modelsExist(at: cacheDirectory, version: asrVersion)
    }
    
    func initializeDownloadableModels() {
        let modelManager = WhisperModelManager.shared
        downloadableModels = SettingsDownloadableModels.availableModels.map { model in
            var updatedModel = model
            let filename = model.url.lastPathComponent
            updatedModel.isDownloaded = modelManager.isModelDownloaded(name: filename)
            return updatedModel
        }
    }
    
    func loadAvailableModels() {
        availableModels = WhisperModelManager.shared.getAvailableModels()
        if selectedModelURL == nil {
            selectedModelURL = availableModels.first
        }
        initializeDownloadableModels()
    }
    
    @MainActor
    func downloadModel(_ model: SettingsDownloadableModel) async throws {
        guard !isDownloading else { return }
        
        isDownloading = true
        downloadingModelName = model.name
        downloadProgress = 0.0
        
        downloadTask = Task {
            do {
                let filename = model.url.lastPathComponent
                
                try await WhisperModelManager.shared.downloadModel(url: model.url, name: filename) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self = self, !Task.isCancelled else { return }
                        guard let task = self.downloadTask, !task.isCancelled else { return }
                        
                        self.downloadProgress = progress
                        if let index = self.downloadableModels.firstIndex(where: { $0.name == model.name }) {
                            self.downloadableModels[index].downloadProgress = progress
                            if progress >= 1.0 {
                                self.downloadableModels[index].isDownloaded = true
                            }
                        }
                    }
                }
                
                guard !Task.isCancelled else {
                    await MainActor.run {
                        self.isDownloading = false
                        self.downloadingModelName = nil
                        self.downloadProgress = 0.0
                        if let index = self.downloadableModels.firstIndex(where: { $0.name == model.name }) {
                            self.downloadableModels[index].downloadProgress = 0.0
                        }
                    }
                    return
                }
                
                await MainActor.run {
                    if let index = downloadableModels.firstIndex(where: { $0.name == model.name }) {
                        downloadableModels[index].isDownloaded = true
                        downloadableModels[index].downloadProgress = 0.0
                    }
                    loadAvailableModels()
                    let modelPath = WhisperModelManager.shared.modelsDirectory.appendingPathComponent(filename).path
                    selectedModelURL = URL(fileURLWithPath: modelPath)
                    isDownloading = false
                    downloadingModelName = nil
                    downloadProgress = 0.0
                    
                    Task { @MainActor in
                        TranscriptionService.shared.reloadModel(with: modelPath)
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    isDownloading = false
                    downloadingModelName = nil
                    downloadProgress = 0.0
                    if let index = downloadableModels.firstIndex(where: { $0.name == model.name }) {
                        downloadableModels[index].downloadProgress = 0.0
                    }
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    downloadingModelName = nil
                    downloadProgress = 0.0
                    if let index = downloadableModels.firstIndex(where: { $0.name == model.name }) {
                        downloadableModels[index].downloadProgress = 0.0
                    }
                }
                throw error
            }
        }
        
        try await downloadTask?.value
    }
    
    func cancelDownload() {
        downloadTask?.cancel()
        if let modelName = downloadingModelName {
            if selectedEngine == "whisper", let model = downloadableModels.first(where: { $0.name == modelName }) {
                let filename = model.url.lastPathComponent
                WhisperModelManager.shared.cancelDownload(name: filename)
            }
            // Reset progress for the downloading model
            if let index = downloadableModels.firstIndex(where: { $0.name == modelName }) {
                downloadableModels[index].downloadProgress = 0.0
            }
            if let index = downloadableFluidAudioModels.firstIndex(where: { $0.name == modelName }) {
                downloadableFluidAudioModels[index].downloadProgress = 0.0
            }
        }
        isDownloading = false
        downloadingModelName = nil
        downloadProgress = 0.0
    }
    
    @MainActor
    func downloadFluidAudioModel(_ model: SettingsFluidAudioModel) async throws {
        guard !isDownloading else { return }
        
        isDownloading = true
        downloadingModelName = model.name
        downloadProgress = 0.0
        
        if let index = downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
            downloadableFluidAudioModels[index].downloadProgress = 0.0
        }
        
        var wasCancelled = false
        
        downloadTask = Task {
            do {
                let version: AsrModelVersion = model.version == "v2" ? .v2 : .v3
                
                guard !Task.isCancelled else {
                    await MainActor.run {
                        self.isDownloading = false
                        self.downloadingModelName = nil
                        self.downloadProgress = 0.0
                        if let index = self.downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                            self.downloadableFluidAudioModels[index].downloadProgress = 0.0
                        }
                    }
                    throw CancellationError()
                }
                
                let models = try await AsrModels.downloadAndLoad(version: version)
                
                guard !Task.isCancelled else {
                    await MainActor.run {
                        self.isDownloading = false
                        self.downloadingModelName = nil
                        self.downloadProgress = 0.0
                        if let index = self.downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                            self.downloadableFluidAudioModels[index].downloadProgress = 0.0
                        }
                    }
                    throw CancellationError()
                }
                
                let manager = AsrManager(config: .default)
                try await manager.loadModels(models)
                
                await MainActor.run {
                    if let index = downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                        downloadableFluidAudioModels[index].isDownloaded = true
                        downloadableFluidAudioModels[index].downloadProgress = 1.0
                    }
                    fluidAudioModelVersion = model.version
                    isDownloading = false
                    downloadingModelName = nil
                    downloadProgress = 1.0
                    
                    Task { @MainActor in
                        TranscriptionService.shared.reloadEngine()
                    }
                }
            } catch is CancellationError {
                wasCancelled = true
                await MainActor.run {
                    isDownloading = false
                    downloadingModelName = nil
                    downloadProgress = 0.0
                    if let index = downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                        downloadableFluidAudioModels[index].downloadProgress = 0.0
                    }
                }
                // Don't re-throw CancellationError - it's a manual cancellation
            } catch {
                // Check if we were cancelled before the error occurred
                if Task.isCancelled {
                    wasCancelled = true
                    await MainActor.run {
                        isDownloading = false
                        downloadingModelName = nil
                        downloadProgress = 0.0
                        if let index = downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                            downloadableFluidAudioModels[index].downloadProgress = 0.0
                        }
                    }
                } else {
                    await MainActor.run {
                        isDownloading = false
                        downloadingModelName = nil
                        downloadProgress = 0.0
                        if let index = downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                            downloadableFluidAudioModels[index].downloadProgress = 0.0
                        }
                    }
                    throw error
                }
            }
        }
        
        // Handle cancellation gracefully - don't throw if cancelled
        do {
            try await downloadTask?.value
        } catch is CancellationError {
            // Already handled in catch block above, just consume the error
            wasCancelled = true
        } catch {
            // If we were cancelled, don't throw
            if !wasCancelled {
                throw error
            }
        }
    }
    
    @MainActor
    func downloadFluidAudioModel() async throws {
        let versionString = AppPreferences.shared.fluidAudioModelVersion
        if let model = downloadableFluidAudioModels.first(where: { $0.version == versionString }) {
            try await downloadFluidAudioModel(model)
        }
    }
}

struct SettingsDownloadableModel: Identifiable {
    let id = UUID()
    let name: String
    var isDownloaded: Bool
    let url: URL
    let size: Int
    let description: String
    var downloadProgress: Double = 0.0

    var sizeString: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(size) * 1000000)
    }

    init(name: String, isDownloaded: Bool, url: URL, size: Int, description: String) {
        self.name = name
        self.isDownloaded = isDownloaded
        self.url = url
        self.size = size
        self.description = description
    }
}

struct SettingsDownloadableModels {
    static let availableModels = [
        SettingsDownloadableModel(
            name: "Turbo V3 large",
            isDownloaded: false,
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin?download=true")!,
            size: 1624,
            description: "High accuracy, best quality"
        ),
        SettingsDownloadableModel(
            name: "Turbo V3 medium",
            isDownloaded: false,
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin?download=true")!,
            size: 874,
            description: "Balanced speed and accuracy"
        ),
        SettingsDownloadableModel(
            name: "Turbo V3 small",
            isDownloaded: false,
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin?download=true")!,
            size: 574,
            description: "Fastest processing"
        )
    ]
}

struct Settings {
    static let asianLanguages: Set<String> = ["zh", "ja", "ko"]
    
    var selectedLanguage: String
    var translateToEnglish: Bool
    var suppressBlankAudio: Bool
    var showTimestamps: Bool
    var temperature: Double
    var noSpeechThreshold: Double
    var initialPrompt: String
    var useBeamSearch: Bool
    var beamSize: Int
    var useAsianAutocorrect: Bool
    
    var isAsianLanguage: Bool {
        Settings.asianLanguages.contains(selectedLanguage)
    }
    
    var shouldApplyAsianAutocorrect: Bool {
        isAsianLanguage && useAsianAutocorrect
    }
    
    init() {
        let prefs = AppPreferences.shared
        self.selectedLanguage = prefs.whisperLanguage
        self.translateToEnglish = prefs.translateToEnglish
        self.suppressBlankAudio = prefs.suppressBlankAudio
        self.showTimestamps = prefs.showTimestamps
        self.temperature = prefs.temperature
        self.noSpeechThreshold = prefs.noSpeechThreshold
        self.initialPrompt = prefs.initialPrompt
        self.useBeamSearch = prefs.useBeamSearch
        self.beamSize = prefs.beamSize
        self.useAsianAutocorrect = prefs.useAsianAutocorrect
    }
}


struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @ObservedObject private var microphoneService = MicrophoneService.shared
    // Observed, not just referenced: the download card reads its progress and
    // install state, and a plain `let manager = .shared` never redraws.
    @ObservedObject private var s1Manager = S1MiniModelManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) var dismiss
    @State private var isRecordingNewShortcut = false
    @State private var selectedTab = 0
    @State private var previousModelURL: URL?
    @State private var isConfirmingStatsReset = false
    private let automaticMicrophoneID = "__automatic__"
    
    private struct SettingsTabInfo: Identifiable {
        let id: Int
        let title: String
        let icon: String
    }

    private static let tabs: [SettingsTabInfo] = [
        .init(id: 0, title: "Shortcuts", icon: "command"),
        .init(id: 1, title: "Model", icon: "cpu"),
        .init(id: 2, title: "Transcription", icon: "text.bubble"),
        .init(id: 3, title: "Formatting", icon: "wand.and.stars"),
        .init(id: 4, title: "Analytics", icon: "chart.bar.xaxis"),
        .init(id: 5, title: "Audio", icon: "mic"),
        .init(id: 6, title: "Appearance", icon: "paintpalette"),
        .init(id: 7, title: "Advanced", icon: "gear"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar

            Rectangle().fill(palette.hairline).frame(width: 1)

            selectedContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(palette.detailBackground)
        }
        .frame(width: 840, height: 640)
        .background(palette.windowBackground)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Done") {
                    if viewModel.selectedEngine == "whisper" {
                        if viewModel.selectedModelURL != previousModelURL, let modelPath = viewModel.selectedModelURL?.path {
                            TranscriptionService.shared.reloadModel(with: modelPath)
                        }
                    }
                    dismiss()
                }
                .buttonStyle(FilledButtonStyle(height: 30))

                Spacer()

                Link(destination: URL(string: "https://github.com/vinitkumargoel/OpenSuperWhisper-v2")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "star")
                            .font(.system(size: 10))
                        Text("GitHub")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(palette.textQuaternary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(palette.windowBackground)
            .overlay(alignment: .top) {
                Rectangle().fill(palette.hairline).frame(height: 1)
            }
        }
        .themedWindow()
        .onAppear {
            previousModelURL = viewModel.selectedModelURL
            if viewModel.selectedEngine == "fluidaudio" {
                viewModel.initializeFluidAudioModels()
            }
        }
        .onChange(of: viewModel.selectedEngine) { _, newEngine in
            if newEngine == "fluidaudio" {
                viewModel.initializeFluidAudioModels()
            }
        }
        .onChange(of: viewModel.fluidAudioModelVersion) { _, _ in
            Task { @MainActor in
                TranscriptionService.shared.reloadEngine()
            }
        }
        .onChange(of: viewModel.selectedModelURL) { _, newURL in
            if viewModel.selectedEngine == "whisper", let modelPath = newURL?.path {
                Task { @MainActor in
                    TranscriptionService.shared.reloadModel(with: modelPath)
                }
            }
        }
    }

    // MARK: - Sidebar navigation

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(palette.textPrimary)
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 14)

            ForEach(Self.tabs) { tab in
                sidebarRow(tab)
            }

            Spacer()
        }
        .frame(width: 196)
        .frame(maxHeight: .infinity)
        .background(palette.railBackground)
    }

    private func sidebarRow(_ tab: SettingsTabInfo) -> some View {
        let isSelected = selectedTab == tab.id
        return Button {
            withAnimation(.easeOut(duration: 0.12)) { selectedTab = tab.id }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12.5))
                    .frame(width: 16)
                    .foregroundColor(isSelected ? palette.selectionText : palette.textTertiary)

                Text(tab.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? palette.selectionText : palette.textSecondary)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .background(
                RoundedRectangle(cornerRadius: palette.radiusSmall)
                    .fill(isSelected ? palette.selectionFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case 0: shortcutSettings
        case 1: modelSettings
        case 2: transcriptionSettings
        case 3: formattingSettings
        case 4: analyticsSettings
        case 5: audioSettings
        case 6: appearanceSettings
        default: advancedSettings
        }
    }

    // MARK: - Appearance

    private var appearanceSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Appearance")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(palette.textPrimary)
                Text("Every colour in the app comes from the selected theme, including the floating indicator.")
                    .font(.system(size: 12.5))
                    .foregroundColor(palette.textQuaternary)
                    .padding(.top, 3)
                    .padding(.bottom, 18)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(AppTheme.allCases) { theme in
                        ThemeCard(
                            theme: theme,
                            isSelected: themeManager.theme == theme,
                            systemScheme: themeManager.systemScheme
                        ) {
                            withAnimation(.easeOut(duration: 0.15)) {
                                themeManager.theme = theme
                            }
                        }
                    }
                }

                // Obsidian and Signal are built on near-black; saying so up front
                // is better than the user wondering why the toggle did nothing.
                Text(themeManager.theme.followsSystemAppearance
                     ? "Graphite follows your macOS appearance setting."
                     : "\(themeManager.theme.displayName) is a dark-only theme, so the app stays dark regardless of your macOS appearance setting.")
                    .font(.system(size: 11.5))
                    .foregroundColor(palette.textQuaternary)
                    .padding(.top, 14)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private var analyticsSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Usage Analytics")
                        .font(.headline)

                    Spacer()

                    Text("Typing estimate: 40 wpm")
                        .font(.caption2)
                        .foregroundColor(palette.textTertiary)

                    Button {
                        viewModel.refreshAnalytics()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(viewModel.isLoadingAnalytics)
                    .help("Refresh analytics")

                    // Statistics outlive the recordings they came from, so
                    // clearing them has to be its own action rather than a side
                    // effect of deleting history.
                    Button(role: .destructive) {
                        isConfirmingStatsReset = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(viewModel.isLoadingAnalytics)
                    .help("Reset statistics")
                }
                .confirmationDialog(
                    "Reset all statistics?",
                    isPresented: $isConfirmingStatsReset,
                    titleVisibility: .visible
                ) {
                    Button("Reset Statistics", role: .destructive) {
                        viewModel.resetStatistics()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Totals and the activity graph go back to zero. Your recordings and transcripts are not affected.")
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    AnalyticsMetricCard(title: "Today", value: "\(viewModel.analyticsSnapshot.todayRecordings)", detail: "recordings")
                    AnalyticsMetricCard(title: "Today Min", value: analyticsMinutes(viewModel.analyticsSnapshot.todayDuration), detail: "recorded")
                    AnalyticsMetricCard(title: "Today Words", value: analyticsNumber(viewModel.analyticsSnapshot.todayWords), detail: "transcribed")
                    AnalyticsMetricCard(title: "All", value: analyticsNumber(viewModel.analyticsSnapshot.totalRecordings), detail: "recordings")
                    AnalyticsMetricCard(title: "Total Min", value: analyticsMinutes(viewModel.analyticsSnapshot.totalDuration), detail: "recorded")
                    AnalyticsMetricCard(title: "Total Words", value: analyticsNumber(viewModel.analyticsSnapshot.totalWords), detail: "transcribed")
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    AnalyticsMetricCard(title: "Saved Today", value: TextUtil.formatDuration(viewModel.analyticsSnapshot.todayEstimatedTimeSaved), detail: "estimated")
                    AnalyticsMetricCard(title: "Saved Total", value: TextUtil.formatDuration(viewModel.analyticsSnapshot.estimatedTimeSaved), detail: "estimated")
                    AnalyticsMetricCard(title: "Avg Words", value: analyticsDecimal(viewModel.analyticsSnapshot.averageWordsPerRecording), detail: "per recording")
                    AnalyticsMetricCard(title: "Pace", value: analyticsDecimal(viewModel.analyticsSnapshot.averageWordsPerMinute), detail: "words/min")
                }

                AnalyticsActivitySection(
                    snapshot: viewModel.analyticsSnapshot,
                    range: $viewModel.analyticsRange
                )
            }
            .padding(14)
        }
        .onAppear {
            viewModel.refreshAnalytics()
        }
        .onReceive(NotificationCenter.default.publisher(for: RecordingStore.recordingsDidUpdateNotification)) { _ in
            viewModel.refreshAnalytics()
        }
    }

    private func analyticsNumber(_ value: Int) -> String {
        value.formatted(.number)
    }

    private func analyticsDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func analyticsMinutes(_ duration: TimeInterval) -> String {
        let minutes = duration / 60
        return minutes.formatted(.number.precision(.fractionLength(minutes < 10 ? 1 : 0)))
    }

    private var selectedMicrophoneID: Binding<String> {
        Binding(
            get: {
                microphoneService.selectedMicrophone?.id ?? automaticMicrophoneID
            },
            set: { newValue in
                if newValue == automaticMicrophoneID {
                    microphoneService.resetToDefault()
                    return
                }

                guard let microphone = microphoneService.availableMicrophones.first(where: { $0.id == newValue }) else {
                    return
                }
                microphoneService.selectMicrophone(microphone)
            }
        )
    }

    private var builtInMicrophones: [MicrophoneService.AudioDevice] {
        microphoneService.availableMicrophones.filter { $0.isBuiltIn }
    }

    private var externalMicrophones: [MicrophoneService.AudioDevice] {
        microphoneService.availableMicrophones.filter { !$0.isBuiltIn }
    }

    private var audioSettings: some View {
        Form {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Input Device")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Microphone")
                                .font(.subheadline)

                            Spacer()

                            Picker("", selection: selectedMicrophoneID) {
                                Text("Automatic").tag(automaticMicrophoneID)

                                if !builtInMicrophones.isEmpty {
                                    Divider()
                                    ForEach(builtInMicrophones) { microphone in
                                        Text(microphone.displayName).tag(microphone.id)
                                    }
                                }

                                if !externalMicrophones.isEmpty {
                                    Divider()
                                    ForEach(externalMicrophones) { microphone in
                                        Text(microphone.displayName).tag(microphone.id)
                                    }
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 260)
                            .disabled(microphoneService.availableMicrophones.isEmpty)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.textBackgroundColor).opacity(0.5))
                        .cornerRadius(8)

                        if microphoneService.availableMicrophones.isEmpty {
                            Text("No microphones available")
                                .font(.caption)
                                .foregroundColor(palette.textTertiary)
                        } else if let currentMicrophone = microphoneService.currentMicrophone {
                            Text("Active: \(currentMicrophone.displayName)")
                                .font(.caption)
                                .foregroundColor(palette.textTertiary)
                        }

                        Button {
                            microphoneService.refreshAvailableMicrophones()
                        } label: {
                            Label("Refresh Devices", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
            }
            .padding()
        }
        .onAppear {
            microphoneService.refreshAvailableMicrophones()
        }
    }

    private var formattingSettings: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("AI Auto Format")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Format with AI")
                                    .font(.subheadline)
                                Text("After transcription, an LLM corrects grammar and formatting before the text is saved and pasted.")
                                    .font(.caption)
                                    .foregroundColor(palette.textTertiary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.formattingEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: palette.accent))
                                .labelsHidden()
                        }

                        Picker("", selection: $viewModel.formattingBackend) {
                            ForEach(FormattingBackend.allCases) { backend in
                                Text(backend.title).tag(backend)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Text(viewModel.formattingBackend.subtitle)
                            .font(.caption)
                            .foregroundColor(palette.textTertiary)

                        if viewModel.formattingBackend == .s1mini {
                            onDeviceFormattingSection
                        } else {
                            apiFormattingSection
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                modelResidencySection

                formatTestSection

                formattingModesSection

                vocabularySection
            }
            .padding()
        }
    }

    private var apiFormattingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("API Base URL")
                                .font(.subheadline)
                            TextField("https://api.openai.com/v1", text: $viewModel.llmBaseURL)
                                .textFieldStyle(.roundedBorder)
                            Text("Any OpenAI-compatible endpoint: OpenAI, OpenRouter, Groq, Ollama (http://localhost:11434/v1), LM Studio, ...")
                                .font(.caption)
                                .foregroundColor(palette.textTertiary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("API Key")
                                .font(.subheadline)
                            SecureField("sk-...", text: $viewModel.llmApiKey)
                                .textFieldStyle(.roundedBorder)
                            Text("Leave empty for local servers that don't need a key.")
                                .font(.caption)
                                .foregroundColor(palette.textTertiary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Model")
                                .font(.subheadline)

                            HStack(spacing: 8) {
                                TextField("gpt-4o-mini", text: $viewModel.llmModel)
                                    .textFieldStyle(.roundedBorder)

                                if !viewModel.availableLLMModels.isEmpty {
                                    Picker("", selection: $viewModel.llmModel) {
                                        ForEach(viewModel.availableLLMModels, id: \.self) { model in
                                            Text(model).tag(model)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .frame(width: 180)
                                }

                                Button(viewModel.isFetchingLLMModels ? "Fetching..." : "Fetch Models") {
                                    viewModel.fetchLLMModels()
                                }
                                .disabled(viewModel.isFetchingLLMModels)
                                .controlSize(.small)
                            }

                            if let fetchError = viewModel.llmModelsFetchError {
                                Text(fetchError)
                                    .font(.caption)
                                    .foregroundColor(palette.danger)
                            } else if !viewModel.availableLLMModels.isEmpty {
                                Text("\(viewModel.availableLLMModels.count) models available from this endpoint.")
                                    .font(.caption)
                                    .foregroundColor(palette.textTertiary)
                            } else {
                                Text("Type a model id, or fetch the endpoint's model list and pick from it.")
                                    .font(.caption)
                                    .foregroundColor(palette.textTertiary)
                            }
                        }
        }
    }

    // MARK: - On-device (S1-mini)

    private var onDeviceFormattingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            s1DownloadCard

            VStack(alignment: .leading, spacing: 6) {
                Text("Default style")
                    .font(.subheadline)
                Text("S1-mini's system prompt is fixed by its training, so these three settings are how you steer it. Formatting Modes can override them per app.")
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)

                Picker("Styling", selection: $viewModel.s1DefaultStyling) {
                    ForEach(S1Styling.allCases) { Text($0.title).tag($0) }
                }
                Text(viewModel.s1DefaultStyling.detail)
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)

                Picker("Structure", selection: $viewModel.s1DefaultStructure) {
                    ForEach(S1Structure.allCases) { Text($0.title).tag($0) }
                }
                Text(viewModel.s1DefaultStructure.detail)
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)

                Picker("Context", selection: $viewModel.s1DefaultContext) {
                    ForEach(S1Context.allCases) { Text($0.title).tag($0) }
                }
                Text(viewModel.s1DefaultContext.detail)
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)
            }

            Text("S1-mini by Superwhisper — English only, and it normalizes rather than rewrites. Keep the API backend selected for modes that need a real prompt.")
                .font(.caption)
                .foregroundColor(palette.textTertiary)
        }
    }

    private var s1DownloadCard: some View {
        let manager = s1Manager
        let variant = manager.selectedVariant
        // installedRevision is read so SwiftUI re-evaluates after download/delete.
        let _ = manager.installedRevision
        let installed = manager.isInstalled(variant)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Model weights")
                        .font(.subheadline)
                    Text(installed
                         ? "Installed — \(ByteCountFormatter.string(fromByteCount: manager.installedBytes(variant), countStyle: .file))"
                         : "Not downloaded — \(ByteCountFormatter.string(fromByteCount: variant.approximateBytes, countStyle: .file))")
                        .font(.caption)
                        .foregroundColor(palette.textTertiary)
                }
                Spacer()
                if manager.isDownloading {
                    Button("Cancel") { manager.cancelDownload() }
                        .controlSize(.small)
                } else if installed {
                    Button("Delete") { manager.delete(variant) }
                        .controlSize(.small)
                } else {
                    Button("Download") { manager.download(variant) }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                }
            }

            Picker("Quantization", selection: $viewModel.s1MiniVariant) {
                ForEach(S1MiniModelManager.Variant.all) { Text($0.title).tag($0.id) }
            }
            .disabled(manager.isDownloading)

            if manager.isDownloading {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: manager.downloadProgress)
                    Text("\(manager.downloadingFile) — \(Int(manager.downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(palette.textTertiary)
                }
            }

            if let error = manager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(palette.danger)
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Model residency

    private var modelResidencySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Memory")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Load models when recording starts")
                            .font(.subheadline)
                        Text("Loading takes a second or two. Doing it while you are still speaking means you never wait for it afterwards.")
                            .font(.caption)
                            .foregroundColor(palette.textTertiary)
                    }
                    Spacer()
                    Toggle("", isOn: $viewModel.prewarmModelsOnRecord)
                        .toggleStyle(SwitchToggleStyle(tint: palette.accent))
                        .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Picker("Keep in memory after use", selection: $viewModel.modelIdleUnloadSeconds) {
                        Text("Release immediately").tag(0)
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                        Text("10 minutes").tag(600)
                        Text("Until quit").tag(-1)
                    }
                    Text(viewModel.modelIdleUnloadSeconds == 0
                         ? "Lowest memory: the transcription model is released before formatting starts, so the two never occupy memory at once."
                         : "Back-to-back dictation reuses the loaded models instead of reloading them.")
                        .font(.caption)
                        .foregroundColor(palette.textTertiary)
                }

                HStack {
                    Text(viewModel.residencySummary.isEmpty ? "—" : viewModel.residencySummary)
                        .font(.caption)
                        .foregroundColor(palette.textTertiary)
                    Spacer()
                    Button("Refresh") {
                        Task { await viewModel.refreshResidency() }
                    }
                    .controlSize(.small)
                    Button("Unload now") { viewModel.unloadModelsNow() }
                        .controlSize(.small)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
        .task { await viewModel.refreshResidency() }
    }

    // MARK: - Test

    private var formatTestSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Test formatting")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                Text("Runs the text below through the selected backend, exactly as a finished transcript would go.")
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)

                TextEditor(text: $viewModel.testInput)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 56)
                    .padding(4)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(6)

                HStack {
                    Button(viewModel.isTesting ? "Formatting..." : "Format") {
                        viewModel.runFormatTest()
                    }
                    .disabled(viewModel.isTesting)
                    .buttonStyle(.borderedProminent)

                    if !viewModel.testDuration.isEmpty {
                        Text(viewModel.testDuration)
                            .font(.caption)
                            .foregroundColor(palette.textTertiary)
                    }
                    Spacer()
                }

                if let error = viewModel.testError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(palette.danger)
                        .textSelection(.enabled)
                } else if !viewModel.testOutput.isEmpty {
                    Text(viewModel.testOutput)
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
    }

    private var formattingModesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Formatting Modes")
                    .font(.headline)
                    .foregroundColor(palette.textPrimary)
                Spacer()
                Button {
                    viewModel.addFormattingMode()
                } label: {
                    Label("Add Mode", systemImage: "plus")
                }
                .controlSize(.small)
            }

            Text("Presets with their own prompt. Optionally auto-select a mode based on the app you're dictating into.")
                .font(.caption)
                .foregroundColor(palette.textTertiary)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto-switch by active app")
                        .font(.subheadline)
                    Text("Uses the mode whose app list matches the app that was frontmost when recording started. Otherwise the active mode below is used.")
                        .font(.caption)
                        .foregroundColor(palette.textTertiary)
                }
                Spacer()
                Toggle("", isOn: $viewModel.autoSwitchFormattingMode)
                    .toggleStyle(SwitchToggleStyle(tint: palette.accent))
                    .labelsHidden()
            }

            HStack(spacing: 8) {
                Text("Active mode")
                    .font(.subheadline)
                Picker("", selection: $viewModel.activeFormattingModeID) {
                    ForEach(viewModel.formattingModes) { mode in
                        Text(mode.name.isEmpty ? "Untitled" : mode.name).tag(mode.id.uuidString)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
            }

            // Mode being edited
            Picker("Editing", selection: $viewModel.editingModeID) {
                ForEach(viewModel.formattingModes) { mode in
                    Text(mode.name.isEmpty ? "Untitled" : mode.name).tag(mode.id.uuidString)
                }
            }
            .pickerStyle(.segmented)

            if let modeBinding = viewModel.editingModeBinding() {
                modeEditor(modeBinding)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
    }

    private func modeEditor(_ mode: Binding<FormattingMode>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.subheadline)
                TextField("Mode name", text: mode.name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Auto-activate for apps")
                    .font(.subheadline)
                TextField("com.apple.mail, com.tinyspeck.slackmacgap", text: Binding(
                    get: { mode.wrappedValue.appBundleIDs.joined(separator: ", ") },
                    set: { newValue in
                        mode.wrappedValue.appBundleIDs = newValue
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                Text("Comma-separated app bundle IDs. Used only when auto-switch is on.")
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("On-device style")
                    .font(.subheadline)
                Text("Used when the on-device backend is selected. S1-mini cannot read the prompt below — these are its only controls.")
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)

                Picker("Styling", selection: Binding(
                    get: { mode.wrappedValue.styling ?? viewModel.s1DefaultStyling },
                    set: { mode.wrappedValue.styling = $0 }
                )) {
                    ForEach(S1Styling.allCases) { Text($0.title).tag($0) }
                }
                Picker("Structure", selection: Binding(
                    get: { mode.wrappedValue.structure ?? viewModel.s1DefaultStructure },
                    set: { mode.wrappedValue.structure = $0 }
                )) {
                    ForEach(S1Structure.allCases) { Text($0.title).tag($0) }
                }
                Picker("Context", selection: Binding(
                    get: { mode.wrappedValue.context ?? viewModel.s1DefaultContext },
                    set: { mode.wrappedValue.context = $0 }
                )) {
                    ForEach(S1Context.allCases) { Text($0.title).tag($0) }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Prompt")
                    .font(.subheadline)
                Text("Used by the API backend.")
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)
                TextEditor(text: mode.prompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 100)
                    .padding(6)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(palette.hairline, lineWidth: 1)
                    )
            }

            HStack {
                Button("Restore Default Prompt") {
                    mode.wrappedValue.prompt = AppPreferences.defaultFormattingPrompt
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Spacer()

                Button(role: .destructive) {
                    viewModel.deleteFormattingMode(mode.wrappedValue.id.uuidString)
                } label: {
                    Label("Delete Mode", systemImage: "trash")
                }
                .controlSize(.small)
                .disabled(viewModel.formattingModes.count <= 1)
            }
        }
        .padding(.top, 4)
    }

    private var vocabularySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Custom Vocabulary")
                    .font(.headline)
                    .foregroundColor(palette.textPrimary)
                Spacer()
                Button {
                    viewModel.addVocabularyRule()
                } label: {
                    Label("Add Word", systemImage: "plus")
                }
                .controlSize(.small)
            }

            Text("Fix names, jargon, and acronyms the model mishears. Applied after transcription — even when AI formatting is off.")
                .font(.caption)
                .foregroundColor(palette.textTertiary)

            if viewModel.vocabularyRules.isEmpty {
                Text("No replacements yet. Add one to correct terms like \"clod code\" → \"Claude Code\".")
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                HStack(spacing: 8) {
                    Text("Heard").font(.caption).foregroundColor(palette.textTertiary).frame(maxWidth: .infinity, alignment: .leading)
                    Text("Replace with").font(.caption).foregroundColor(palette.textTertiary).frame(maxWidth: .infinity, alignment: .leading)
                    Text("Aa").font(.caption).foregroundColor(palette.textTertiary).frame(width: 30)
                    Spacer().frame(width: 24)
                }

                ForEach($viewModel.vocabularyRules) { $rule in
                    HStack(spacing: 8) {
                        TextField("clod code", text: $rule.from)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        TextField("Claude Code", text: $rule.to)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        Toggle("", isOn: $rule.caseSensitive)
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .frame(width: 30)
                            .help("Case-sensitive match")
                        Button {
                            viewModel.deleteVocabularyRule(rule.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(palette.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 24)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
    }
    
    private var modelSettings: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Speech Recognition Engine")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                    
                    Picker("Engine", selection: $viewModel.selectedEngine) {
                        Text("Parakeet").tag("fluidaudio")
                        Text("Whisper").tag("whisper")
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 8)
                    
                    if viewModel.selectedEngine == "whisper" {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Whisper Model")
                                .font(.headline)
                                .foregroundColor(palette.textPrimary)
                            
                            Text("Download Models")
                                .font(.headline)
                                .foregroundColor(palette.textPrimary)
                                .padding(.top, 8)
                            
                            ScrollView {
                                VStack(spacing: 12) {
                                    ForEach($viewModel.downloadableModels) { $model in
                                        ModelDownloadItemView(model: $model, viewModel: viewModel)
                                    }
                                }
                            }
                            .frame(maxHeight: 200)
                            
                            if viewModel.isDownloading {
                                VStack(spacing: 8) {
                                    HStack {
                                        if viewModel.downloadProgress > 0 {
                                            ProgressView(value: viewModel.downloadProgress)
                                                .progressViewStyle(LinearProgressViewStyle())
                                        } else {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle())
                                        }
                                        
                                        Spacer()
                                        
                                        Button("Cancel") {
                                            viewModel.cancelDownload()
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    
                                    if let downloadingName = viewModel.downloadingModelName {
                                        Text("Downloading: \(downloadingName)")
                                            .font(.caption)
                                            .foregroundColor(palette.textTertiary)
                                    }
                                }
                                .padding(.top, 8)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Models Directory:")
                                        .font(.subheadline)
                                    Button(action: {
                                        NSWorkspace.shared.open(WhisperModelManager.shared.modelsDirectory)
                                    }) {
                                        Label("Open Folder", systemImage: "folder")
                                            .font(.subheadline)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Open models directory")
                                }
                                Text(WhisperModelManager.shared.modelsDirectory.path)
                                    .font(.caption)
                                    .foregroundColor(palette.textTertiary)
                                    .textSelection(.enabled)
                                    .padding(8)
                                    .background(Color(.textBackgroundColor).opacity(0.5))
                                    .cornerRadius(6)
                            }
                            .padding(.top, 8)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Parakeet Model")
                                .font(.headline)
                                .foregroundColor(palette.textPrimary)
                            
                            Text("Download Models")
                                .font(.headline)
                                .foregroundColor(palette.textPrimary)
                                .padding(.top, 8)
                            
                            ScrollView {
                                VStack(spacing: 12) {
                                    ForEach($viewModel.downloadableFluidAudioModels) { $model in
                                        FluidAudioModelDownloadItemView(model: $model, viewModel: viewModel)
                                    }
                                }
                            }
                            .frame(maxHeight: 200)
                            
                            if viewModel.isDownloading {
                                VStack(spacing: 8) {
                                    HStack {
                                        if viewModel.downloadProgress > 0 {
                                            ProgressView(value: viewModel.downloadProgress)
                                                .progressViewStyle(LinearProgressViewStyle())
                                        } else {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle())
                                        }
                                        
                                        Spacer()
                                        
                                        Button("Cancel") {
                                            viewModel.cancelDownload()
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    
                                    if let downloadingName = viewModel.downloadingModelName {
                                        Text("Downloading: \(downloadingName)")
                                            .font(.caption)
                                            .foregroundColor(palette.textTertiary)
                                    }
                                }
                                .padding(.top, 8)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Models Directory:")
                                        .font(.subheadline)
                                    Button(action: {
                                        let cacheDir = AsrModels.defaultCacheDirectory(for: .v3)
                                        let parentDir = cacheDir.deletingLastPathComponent()
                                        NSWorkspace.shared.open(parentDir)
                                    }) {
                                        Label("Open Folder", systemImage: "folder")
                                            .font(.subheadline)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Open models directory")
                                }
                                Text(AsrModels.defaultCacheDirectory(for: .v3).deletingLastPathComponent().path)
                                    .font(.caption)
                                    .foregroundColor(palette.textTertiary)
                                    .textSelection(.enabled)
                                    .padding(8)
                                    .background(Color(.textBackgroundColor).opacity(0.5))
                                    .cornerRadius(6)
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
            }
        }
        .padding()
    }
    
    private var transcriptionSettings: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Language Settings
                VStack(alignment: .leading, spacing: 16) {
                    Text("Language Settings")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Transcription Language")
                            .font(.subheadline)
                        
                        Picker("Language", selection: $viewModel.selectedLanguage) {
                            ForEach(LanguageUtil.availableLanguages, id: \.self) { code in
                                Text(LanguageUtil.languageNames[code] ?? code)
                                    .tag(code)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack {
                            Text("Translate to English")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.translateToEnglish)
                                .toggleStyle(SwitchToggleStyle(tint: palette.accent))
                                .labelsHidden()
                        }
                        .padding(.top, 4)
                        
                        if Settings.asianLanguages.contains(viewModel.selectedLanguage) {
                            HStack {
                                Text("Use Asian Autocorrect")
                                    .font(.subheadline)
                                Spacer()
                                Toggle("", isOn: $viewModel.useAsianAutocorrect)
                                    .toggleStyle(SwitchToggleStyle(tint: palette.accent))
                                    .labelsHidden()
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                
                // Output Options
                VStack(alignment: .leading, spacing: 16) {
                    Text("Output Options")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Show Timestamps")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.showTimestamps)
                                .toggleStyle(SwitchToggleStyle(tint: palette.accent))
                                .labelsHidden()
                        }
                        
                        HStack {
                            Text("Suppress Blank Audio")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.suppressBlankAudio)
                                .toggleStyle(SwitchToggleStyle(tint: palette.accent))
                                .labelsHidden()
                        }
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add Space After Sentence")
                                    .font(.subheadline)
                                Text("Appends a space when transcription ends with punctuation")
                                    .font(.caption)
                                    .foregroundColor(palette.textTertiary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.addSpaceAfterSentence)
                                .toggleStyle(SwitchToggleStyle(tint: palette.accent))
                                .labelsHidden()
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-paste into focused app")
                                    .font(.subheadline)
                                Text("When off — or if Accessibility isn't granted — text is copied to the clipboard instead")
                                    .font(.caption)
                                    .foregroundColor(palette.textTertiary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.autoPasteEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: palette.accent))
                                .labelsHidden()
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Keep transcript on the clipboard")
                                    .font(.subheadline)
                                Text("Leave the transcript on the clipboard after pasting instead of restoring what was there before")
                                    .font(.caption)
                                    .foregroundColor(palette.textTertiary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.keepTranscriptOnClipboard)
                                .toggleStyle(SwitchToggleStyle(tint: palette.accent))
                                .labelsHidden()
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Spoken punctuation commands")
                                    .font(.subheadline)
                                Text("Turns words like \u{201C}period\u{201D} and \u{201C}new line\u{201D} into punctuation. Supports: \(DictationCommandProcessor.supportedSummary)")
                                    .font(.caption)
                                    .foregroundColor(palette.textTertiary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.dictationCommandsEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: palette.accent))
                                .labelsHidden()
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                // Initial Prompt
                VStack(alignment: .leading, spacing: 16) {
                    Text("Initial Prompt")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $viewModel.initialPrompt)
                            .frame(height: 60)
                            .padding(6)
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(palette.hairline, lineWidth: 1)
                            )
                        
                        Text("Optional text to guide the model's transcription")
                            .font(.caption)
                            .foregroundColor(palette.textTertiary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                
                // Transcriptions Directory
                VStack(alignment: .leading, spacing: 16) {
                    Text("Transcriptions Directory")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Directory:")
                                .font(.subheadline)
                            Spacer()
                            Button(action: {
                                NSWorkspace.shared.open(Recording.recordingsDirectory)
                            }) {
                                Label("Open Folder", systemImage: "folder")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.borderless)
                            .help("Open transcriptions directory")
                        }
                        
                        Text(Recording.recordingsDirectory.path)
                            .font(.caption)
                            .foregroundColor(palette.textTertiary)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.textBackgroundColor).opacity(0.5))
                            .cornerRadius(6)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
            }
            .padding()
        }
    }

    private var advancedSettings: some View {
        Form {
            VStack(spacing: 20) {
                // Decoding Strategy
                VStack(alignment: .leading, spacing: 16) {
                    Text("Decoding Strategy")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Use Beam Search")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.useBeamSearch)
                                .toggleStyle(SwitchToggleStyle(tint: palette.accent))
                                .labelsHidden()
                                .help("Beam search can provide better results but is slower")
                        }
                        
                        if viewModel.useBeamSearch {
                            HStack {
                                Text("Beam Size:")
                                    .font(.subheadline)
                                Spacer()
                                Stepper("\(viewModel.beamSize)", value: $viewModel.beamSize, in: 1...10)
                                    .help("Number of beams to use in beam search")
                                    .frame(width: 120)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                
                // Model Parameters
                VStack(alignment: .leading, spacing: 16) {
                    Text("Model Parameters")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                    
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Temperature:")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f", viewModel.temperature))
                                    .font(.subheadline)
                                    .foregroundColor(palette.textTertiary)
                            }
                            
                            Slider(value: $viewModel.temperature, in: 0.0...1.0, step: 0.1)
                                .help("Higher values make the output more random")
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("No Speech Threshold:")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f", viewModel.noSpeechThreshold))
                                    .font(.subheadline)
                                    .foregroundColor(palette.textTertiary)
                            }
                            
                            Slider(value: $viewModel.noSpeechThreshold, in: 0.0...1.0, step: 0.1)
                                .help("Threshold for detecting speech vs. silence")
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                
                // Debug Options
                VStack(alignment: .leading, spacing: 16) {
                    Text("Debug Options")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                    
                    HStack {
                        Text("Debug Mode")
                            .font(.subheadline)
                        Spacer()
                        Toggle("", isOn: $viewModel.debugMode)
                            .toggleStyle(SwitchToggleStyle(tint: palette.accent))
                            .labelsHidden()
                            .help("Enable additional logging and debugging information")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
            }
            .padding()
        }
    }
    
    private var useModifierKey: Bool {
        viewModel.modifierOnlyHotkey != .none
    }
    
    private var shortcutSettings: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Recording Trigger
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recording Trigger")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("", selection: Binding(
                            get: { useModifierKey },
                            set: { newValue in
                                if !newValue {
                                    viewModel.modifierOnlyHotkey = .none
                                } else if viewModel.modifierOnlyHotkey == .none {
                                    viewModel.modifierOnlyHotkey = .leftCommand
                                }
                            }
                        )) {
                            Text("Key Combination").tag(false)
                            Text("Single Modifier Key").tag(true)
                        }
                        .pickerStyle(.segmented)
                        
                        if useModifierKey {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Modifier Key")
                                        .font(.subheadline)
                                    Spacer()
                                    Picker("", selection: $viewModel.modifierOnlyHotkey) {
                                        ForEach(ModifierKey.allCases.filter { $0 != .none }) { key in
                                            Text(key.displayName).tag(key)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 200)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color(.textBackgroundColor).opacity(0.5))
                                .cornerRadius(8)
                                
                                Text("One-tap to toggle recording")
                                    .font(.caption)
                                    .foregroundColor(palette.textTertiary)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Shortcut")
                                        .font(.subheadline)
                                    Spacer()
                                    KeyboardShortcuts.Recorder("", name: .toggleRecord)
                                        .frame(width: 150)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color(.textBackgroundColor).opacity(0.5))
                                .cornerRadius(8)
                                
                                if isRecordingNewShortcut {
                                    Text("Press your new shortcut combination...")
                                        .foregroundColor(palette.textTertiary)
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                
                // Recording Behavior
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recording Behavior")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hold to Record")
                                    .font(.subheadline)
                                Text("Hold the shortcut to record, release to stop")
                                    .font(.caption)
                                    .foregroundColor(palette.textTertiary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.holdToRecord)
                                .toggleStyle(SwitchToggleStyle(tint: palette.accent))
                                .labelsHidden()
                        }
                        
                        HStack {
                            Text("Play sound when recording starts")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.playSoundOnRecordStart)
                                .toggleStyle(SwitchToggleStyle(tint: palette.accent))
                                .labelsHidden()
                                .help("Play a notification sound when recording begins")
                        }

                        HStack {
                            Text("Mute system sound while recording")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.pauseMediaDuringRecording)
                                .toggleStyle(SwitchToggleStyle(tint: palette.accent))
                                .labelsHidden()
                                .help("Set system output volume to 0 when recording starts and restore it when recording stops")
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Launch at Login")
                                    .font(.subheadline)
                                Text("Start OpenSuperWhisper automatically when you log in")
                                    .font(.caption)
                                    .foregroundColor(palette.textTertiary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.launchAtLogin)
                                .toggleStyle(SwitchToggleStyle(tint: palette.accent))
                                .labelsHidden()
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-delete old recordings")
                                    .font(.subheadline)
                                Text("Removes completed, non-starred recordings older than the chosen age")
                                    .font(.caption)
                                    .foregroundColor(palette.textTertiary)
                            }
                            Spacer()
                            Picker("", selection: $viewModel.historyRetentionDays) {
                                Text("Never").tag(0)
                                Text("7 days").tag(7)
                                Text("30 days").tag(30)
                                Text("90 days").tag(90)
                                Text("1 year").tag(365)
                            }
                            .labelsHidden()
                            .frame(width: 120)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                // Recording Indicator
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recording Indicator")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Position")
                                    .font(.subheadline)
                                Text("Where the floating indicator appears, or hide it entirely")
                                    .font(.caption)
                                    .foregroundColor(palette.textTertiary)
                            }
                            Spacer()
                            Picker("", selection: $viewModel.indicatorPosition) {
                                ForEach(IndicatorPosition.allCases) { position in
                                    Text(position.displayName).tag(position)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 180)
                        }

                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
            }
            .padding()
        }
    }
}

struct SettingsFluidAudioModel: Identifiable {
    let id = UUID()
    let name: String
    let version: String
    var isDownloaded: Bool
    let description: String
    var downloadProgress: Double = 0.0
}

struct SettingsFluidAudioModels {
    static let availableModels = [
        SettingsFluidAudioModel(
            name: "Parakeet v3",
            version: "v3",
            isDownloaded: false,
            description: "Multilingual, 25 languages"
        ),
        SettingsFluidAudioModel(
            name: "Parakeet v2",
            version: "v2",
            isDownloaded: false,
            description: "English-only, higher recall"
        )
    ]
}

enum OnboardingModelType {
    case whisper(url: URL, size: Int)
    case parakeet(version: String)
}

struct OnboardingUnifiedModel: Identifiable {
    let id = UUID()
    let name: String
    var isDownloaded: Bool
    let description: String
    let type: OnboardingModelType
    var downloadProgress: Double = 0.0
}

struct OnboardingUnifiedModels {
    static let availableModels = [
        OnboardingUnifiedModel(
            name: "Whisper V3 Large",
            isDownloaded: false,
            description: "High accuracy, best quality",
            type: .whisper(
                url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin?download=true")!,
                size: 1624
            )
        ),
        OnboardingUnifiedModel(
            name: "Parakeet v3",
            isDownloaded: false,
            description: "Fastest processing and accurate",
            type: .parakeet(version: "v3")
        ),
        OnboardingUnifiedModel(
            name: "Parakeet v2",
            isDownloaded: false,
            description: "Fastest processing and English-only, higher recall",
            type: .parakeet(version: "v2")
        ),
        OnboardingUnifiedModel(
            name: "Whisper Medium",
            isDownloaded: false,
            description: "Balanced speed and accuracy",
            type: .whisper(
                url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin?download=true")!,
                size: 874
            )
        ),
        OnboardingUnifiedModel(
            name: "Whisper Small",
            isDownloaded: false,
            description: "Very fast processing",
            type: .whisper(
                url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin?download=true")!,
                size: 574
            )
        )
    ]
}

struct FluidAudioModelDownloadItemView: View {
    @Environment(\.palette) private var palette
    @Binding var model: SettingsFluidAudioModel
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showError = false
    @State private var errorMessage = ""
    
    var isSelected: Bool {
        viewModel.fluidAudioModelVersion == model.version
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if model.isDownloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(palette.textTertiary)
                            .imageScale(.small)
                    }
                }
                
                Text(model.description)
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)
                
                if viewModel.isDownloading && viewModel.downloadingModelName == model.name {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.7)
                        .padding(.top, 4)
                } else if model.downloadProgress > 0 && model.downloadProgress < 1 {
                    ProgressView(value: model.downloadProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 6)
                        .padding(.top, 4)
                }
            }
            
            Spacer()
            
            if viewModel.isDownloading && viewModel.downloadingModelName == model.name {
                Button("Cancel") {
                    viewModel.cancelDownload()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if model.isDownloaded {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(palette.accent)
                        .imageScale(.large)
                } else {
                    Button(action: {
                        viewModel.fluidAudioModelVersion = model.version
                    }) {
                        Text("Select")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } else {
                Button(action: {
                    Task {
                        do {
                            try await viewModel.downloadFluidAudioModel(model)
                        } catch is CancellationError {
                            // Don't show error for manual cancellation
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isDownloading)
            }
        }
        .padding(12)
        .background(isSelected ? Color(.controlBackgroundColor).opacity(0.7) : Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            if model.isDownloaded && !isSelected {
                viewModel.fluidAudioModelVersion = model.version
            }
        }
        .alert("Download Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}

struct AnalyticsMetricCard: View {
    @Environment(\.palette) private var palette
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(palette.textTertiary)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(detail)
                .font(.caption2)
                .foregroundColor(palette.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.textBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}

struct AnalyticsActivitySection: View {
    let snapshot: AnalyticsSnapshot
    @Binding var range: AnalyticsRange

    private var series: [AnalyticsDay] { snapshot.series(for: range) }
    private var summary: AnalyticsRangeSummary { snapshot.summary(for: range) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activity")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Picker("", selection: $range) {
                    ForEach(AnalyticsRange.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
            }

            AnalyticsActivityChart(series: series, range: range)
                .frame(height: 150)

            HStack(spacing: 8) {
                AnalyticsSummaryChip(title: "Words", value: summary.words.formatted(.number))
                AnalyticsSummaryChip(title: "Recordings", value: summary.recordings.formatted(.number))
                AnalyticsSummaryChip(title: "Time Saved", value: TextUtil.formatDuration(summary.estimatedTimeSaved))
                AnalyticsSummaryChip(title: "Active Days", value: "\(summary.activeDays)/\(range.days)")
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor).opacity(0.25))
        .cornerRadius(10)
    }
}

struct AnalyticsActivityChart: View {
    let series: [AnalyticsDay]
    let range: AnalyticsRange
    @Environment(\.palette) private var palette

    private var hasData: Bool { series.contains { $0.words > 0 } }

    // Fewer x labels on longer ranges so they don't overlap.
    private var strideDays: Int {
        switch range {
        case .week: return 1
        case .month: return 5
        case .quarter: return 15
        }
    }

    var body: some View {
        if !hasData {
            RoundedRectangle(cornerRadius: palette.radiusCard)
                .fill(palette.groupBackground)
                .overlay(
                    Text("No activity in this range yet")
                        .font(.caption)
                        .foregroundColor(palette.textQuaternary)
                )
        } else {
            Chart(series) { day in
                BarMark(
                    x: .value("Date", day.date, unit: .day),
                    y: .value("Words", day.words)
                )
                .foregroundStyle(palette.accent)
                .cornerRadius(range == .quarter ? 1.5 : 3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: strideDays)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 9))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                        .font(.system(size: 9))
                }
            }
        }
    }
}

struct AnalyticsSummaryChip: View {
    let title: String
    let value: String
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(palette.textQuaternary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.ghostFill)
        .overlay(RoundedRectangle(cornerRadius: palette.radiusControl).stroke(palette.ghostBorder, lineWidth: 1))
        .cornerRadius(palette.radiusControl)
    }
}

struct ModelDownloadItemView: View {
    @Environment(\.palette) private var palette
    @Binding var model: SettingsDownloadableModel
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showError = false
    @State private var errorMessage = ""
    
    var isSelected: Bool {
        if let selectedURL = viewModel.selectedModelURL {
            let filename = model.url.lastPathComponent
            return selectedURL.lastPathComponent == filename
        }
        return false
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if model.isDownloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(palette.textTertiary)
                            .imageScale(.small)
                    }
                }
                
                Text(model.description)
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)
                
                if model.downloadProgress > 0 && model.downloadProgress < 1 {
                    ProgressView(value: model.downloadProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 6)
                        .padding(.top, 4)
                }
            }
            
            Spacer()
            
            if viewModel.isDownloading && viewModel.downloadingModelName == model.name {
                Button("Cancel") {
                    viewModel.cancelDownload()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if model.isDownloaded {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(palette.accent)
                        .imageScale(.large)
                } else {
                    Button(action: {
                        let modelPath = WhisperModelManager.shared.modelsDirectory.appendingPathComponent(model.url.lastPathComponent).path
                        viewModel.selectedModelURL = URL(fileURLWithPath: modelPath)
                    }) {
                        Text("Select")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } else {
                Button(action: {
                    Task {
                        do {
                            try await viewModel.downloadModel(model)
                        } catch is CancellationError {
                            // Don't show error for manual cancellation
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isDownloading)
            }
        }
        .padding(12)
        .background(isSelected ? Color(.controlBackgroundColor).opacity(0.7) : Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            if model.isDownloaded && !isSelected {
                let modelPath = WhisperModelManager.shared.modelsDirectory.appendingPathComponent(model.url.lastPathComponent).path
                viewModel.selectedModelURL = URL(fileURLWithPath: modelPath)
            }
        }
        .alert("Download Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}
