import AppKit
import Carbon
import Combine
import Foundation
import KeyboardShortcuts
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

    @Published var codexFormattingEnabled: Bool {
        didSet {
            AppPreferences.shared.codexFormattingEnabled = codexFormattingEnabled
        }
    }

    @Published var codexExecutablePath: String {
        didSet {
            AppPreferences.shared.codexExecutablePath = codexExecutablePath
        }
    }

    @Published var codexModel: String {
        didSet {
            AppPreferences.shared.codexModel = codexModel
        }
    }

    @Published var codexFormattingPrompt: String {
        didSet {
            AppPreferences.shared.codexFormattingPrompt = codexFormattingPrompt
        }
    }

    @Published var analyticsSnapshot: AnalyticsSnapshot = .empty
    @Published var isLoadingAnalytics: Bool = false
    
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
        self.useAsianAutocorrect = prefs.useAsianAutocorrect
        self.modifierOnlyHotkey = ModifierKey(rawValue: prefs.modifierOnlyHotkey) ?? .none
        self.holdToRecord = prefs.holdToRecord
        self.addSpaceAfterSentence = prefs.addSpaceAfterSentence
        self.codexFormattingEnabled = prefs.codexFormattingEnabled
        self.codexExecutablePath = prefs.codexExecutablePath
        self.codexModel = prefs.codexModel
        self.codexFormattingPrompt = prefs.codexFormattingPrompt
        
        if let savedPath = prefs.selectedWhisperModelPath ?? prefs.selectedModelPath {
            self.selectedModelURL = URL(fileURLWithPath: savedPath)
        }
        loadAvailableModels()
        initializeDownloadableModels()
        initializeFluidAudioModels()
        refreshAnalytics()
    }

    func refreshAnalytics() {
        isLoadingAnalytics = true
        Task {
            do {
                let recordings = try await RecordingStore.shared.fetchAnalyticsRecordings()
                let snapshot = AnalyticsSnapshot(recordings: recordings)
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
                try await manager.initialize(models: models)
                
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

struct CodexFormattingModel: Identifiable {
    let id: String
    let displayName: String
    let description: String

    static let availableModels = [
        CodexFormattingModel(
            id: "gpt-5.4",
            displayName: "gpt-5.4",
            description: "Strong model for everyday coding."
        ),
        CodexFormattingModel(
            id: "gpt-5.4-mini",
            displayName: "GPT-5.4-Mini",
            description: "Small, fast, and cost-efficient model for simpler coding tasks."
        ),
        CodexFormattingModel(
            id: "gpt-5.3-codex",
            displayName: "gpt-5.3-codex",
            description: "Coding-optimized model."
        ),
        CodexFormattingModel(
            id: "gpt-5.3-codex-spark",
            displayName: "GPT-5.3-Codex-Spark",
            description: "Ultra-fast coding model."
        ),
        CodexFormattingModel(
            id: "gpt-5.2",
            displayName: "gpt-5.2",
            description: "Optimized for professional work and long-running agents."
        ),
        CodexFormattingModel(
            id: "codex-auto-review",
            displayName: "Codex Auto Review",
            description: "Automatic approval review model for Codex."
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
    @Environment(\.dismiss) var dismiss
    @State private var isRecordingNewShortcut = false
    @State private var selectedTab = 0
    @State private var previousModelURL: URL?
    private let automaticMicrophoneID = "__automatic__"
    
    var body: some View {
        TabView(selection: $selectedTab) {

             // Shortcut Settings
            shortcutSettings
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
                }
                .tag(0)
            // Model Settings
            modelSettings
                .tabItem {
                    Label("Model", systemImage: "cpu")
                }
                .tag(1)
            
            // Transcription Settings
            transcriptionSettings
                .tabItem {
                    Label("Transcription", systemImage: "text.bubble")
                }
                .tag(2)

            formattingSettings
                .tabItem {
                    Label("Formatting", systemImage: "wand.and.stars")
                }
                .tag(3)

            analyticsSettings
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar.xaxis")
                }
                .tag(4)

            audioSettings
                .tabItem {
                    Label("Audio", systemImage: "mic")
                }
                .tag(5)
            
            // Advanced Settings
            advancedSettings
                .tabItem {
                    Label("Advanced", systemImage: "gear")
                }
                .tag(6)
            }
        .padding()
        .frame(width: 620)
        .background(Color(.windowBackgroundColor))
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
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                
                Spacer()
                
                Link(destination: URL(string: "https://github.com/vinitkumargoel/OpenSuperWhisper-v2")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "star")
                            .font(.system(size: 10))
                        Text("GitHub")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(.windowBackgroundColor))
        }
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

    private var analyticsSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Usage Analytics")
                        .font(.headline)

                    Spacer()

                    Text("Typing estimate: 40 wpm")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Button {
                        viewModel.refreshAnalytics()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(viewModel.isLoadingAnalytics)
                    .help("Refresh analytics")
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

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Last 7 Days")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("Words / recordings / audio")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    VStack(spacing: 4) {
                        ForEach(viewModel.analyticsSnapshot.lastSevenDays) { day in
                            AnalyticsDayRow(
                                day: day,
                                maxWords: max(viewModel.analyticsSnapshot.lastSevenDays.map(\.words).max() ?? 0, 1)
                            )
                        }
                    }
                }
                .padding(10)
                .background(Color(.controlBackgroundColor).opacity(0.25))
                .cornerRadius(8)
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
                        .foregroundColor(.primary)

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
                                .foregroundColor(.secondary)
                        } else if let currentMicrophone = microphoneService.currentMicrophone {
                            Text("Active: \(currentMicrophone.displayName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
        Form {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Codex Auto Format")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Format with Codex")
                                    .font(.subheadline)
                                Text("After transcription, Codex corrects grammar and formatting before the text is saved and pasted.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.codexFormattingEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Codex Command")
                                .font(.subheadline)
                            TextField("codex", text: $viewModel.codexExecutablePath)
                                .textFieldStyle(.roundedBorder)
                            Text("Use a full path if the app cannot find the logged-in Codex CLI.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Model")
                                .font(.subheadline)

                            Picker("Model", selection: $viewModel.codexModel) {
                                ForEach(CodexFormattingModel.availableModels) { model in
                                    Text(model.displayName).tag(model.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if let selectedModel = CodexFormattingModel.availableModels.first(where: { $0.id == viewModel.codexModel }) {
                                Text(selectedModel.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Selected model: \(viewModel.codexModel)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Text("Detected from Codex model cache. Default: gpt-5.2")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 16) {
                    Text("System Prompt")
                        .font(.headline)
                        .foregroundColor(.primary)

                    TextEditor(text: $viewModel.codexFormattingPrompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 150)
                        .padding(6)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )

                    Button("Restore Default Prompt") {
                        viewModel.codexFormattingPrompt = AppPreferences.defaultCodexFormattingPrompt
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
            }
            .padding()
        }
    }
    
    private var modelSettings: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Speech Recognition Engine")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
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
                                .foregroundColor(.primary)
                            
                            Text("Download Models")
                                .font(.headline)
                                .foregroundColor(.primary)
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
                                            .foregroundColor(.secondary)
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
                                    .foregroundColor(.secondary)
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
                                .foregroundColor(.primary)
                            
                            Text("Download Models")
                                .font(.headline)
                                .foregroundColor(.primary)
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
                                            .foregroundColor(.secondary)
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
                                    .foregroundColor(.secondary)
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
        Form {
            VStack(spacing: 20) {
                // Language Settings
                VStack(alignment: .leading, spacing: 16) {
                    Text("Language Settings")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
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
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }
                        .padding(.top, 4)
                        
                        if Settings.asianLanguages.contains(viewModel.selectedLanguage) {
                            HStack {
                                Text("Use Asian Autocorrect")
                                    .font(.subheadline)
                                Spacer()
                                Toggle("", isOn: $viewModel.useAsianAutocorrect)
                                    .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
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
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Show Timestamps")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.showTimestamps)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }
                        
                        HStack {
                            Text("Suppress Blank Audio")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.suppressBlankAudio)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add Space After Sentence")
                                    .font(.subheadline)
                                Text("Appends a space when transcription ends with punctuation")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.addSpaceAfterSentence)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
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
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $viewModel.initialPrompt)
                            .frame(height: 60)
                            .padding(6)
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        
                        Text("Optional text to guide the model's transcription")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                        .foregroundColor(.primary)
                    
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
                            .foregroundColor(.secondary)
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
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Use Beam Search")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.useBeamSearch)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
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
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Temperature:")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f", viewModel.temperature))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
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
                                    .foregroundColor(.secondary)
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
                        .foregroundColor(.primary)
                    
                    HStack {
                        Text("Debug Mode")
                            .font(.subheadline)
                        Spacer()
                        Toggle("", isOn: $viewModel.debugMode)
                            .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
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
        Form {
            VStack(spacing: 20) {
                // Recording Trigger
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recording Trigger")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
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
                                    .foregroundColor(.secondary)
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
                                        .foregroundColor(.secondary)
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
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hold to Record")
                                    .font(.subheadline)
                                Text("Hold the shortcut to record, release to stop")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.holdToRecord)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }
                        
                        HStack {
                            Text("Play sound when recording starts")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.playSoundOnRecordStart)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                                .help("Play a notification sound when recording begins")
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
                            .foregroundColor(.blue)
                            .imageScale(.small)
                    }
                }
                
                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
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
                        .foregroundColor(.green)
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
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(detail)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.textBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}

struct AnalyticsDayRow: View {
    let day: AnalyticsDay
    let maxWords: Int

    private var barFraction: Double {
        guard maxWords > 0 else { return 0 }
        return Double(day.words) / Double(maxWords)
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(day.date, format: .dateTime.weekday(.abbreviated))
                    .font(.caption)
                    .fontWeight(.medium)
                Text(day.date, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 66, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.separatorColor).opacity(0.25))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.8))
                        .frame(width: day.words == 0 ? 0 : max(4, geometry.size.width * barFraction))
                }
            }
            .frame(height: 6)

            HStack(spacing: 4) {
                Text("\(day.words.formatted(.number))w")
                    .font(.caption)
                    .foregroundColor(.primary)
                    .frame(width: 54, alignment: .trailing)
                Text("\(day.recordings)r")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 28, alignment: .trailing)
                Text(TextUtil.formatDuration(day.duration))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 46, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(.textBackgroundColor).opacity(0.35))
        .cornerRadius(6)
    }
}

struct ModelDownloadItemView: View {
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
                            .foregroundColor(.blue)
                            .imageScale(.small)
                    }
                }
                
                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
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
                        .foregroundColor(.green)
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
