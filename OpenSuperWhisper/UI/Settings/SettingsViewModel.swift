import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    /// One instance for every surface that edits preferences — the Settings
    /// window, Home's quick settings and the menu-bar panel — so they never
    /// disagree.
    static let shared = SettingsViewModel()

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

    }
}
