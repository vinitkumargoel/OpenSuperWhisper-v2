import Foundation

@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T
    
    var wrappedValue: T {
        get { UserDefaults.standard.object(forKey: key) as? T ?? defaultValue }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

@propertyWrapper
struct OptionalUserDefault<T> {
    let key: String
    
    var wrappedValue: T? {
        get { UserDefaults.standard.object(forKey: key) as? T }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

final class AppPreferences {
    static let shared = AppPreferences()
    static let defaultFormattingPrompt = """
    Rewrite the transcript into clean, grammatically correct, well-formatted text. Remove filler words, repeated false starts, transcription artifacts, timestamps, bracketed annotations, speaker labels, and non-content notes. Preserve the speaker's meaning, names, numbers, language, and intent. Do not summarize, answer questions, add new ideas, or wrap the output in quotes or Markdown. Return only the final cleaned text.
    """

    /// Seeds Whisper's decoder with a well-punctuated, tech-aware sample so the
    /// output favors correct casing, punctuation and common technical spellings.
    /// Whisper treats `initialPrompt` as preceding context (a style hint), not an
    /// instruction — so this is written as a natural, exemplary sentence.
    static let defaultInitialPrompt = """
    Here is a clear, well-punctuated transcription with correct capitalization, complete sentences, and natural paragraph breaks. Technical terms, product names, and acronyms such as API, macOS, iOS, GitHub, JSON, URL, SQL, and OpenSuperWhisper are spelled correctly.
    """

    private init() {
        migrateOldPreferences()
    }
    
    private func migrateOldPreferences() {
        if let oldPath = UserDefaults.standard.string(forKey: "selectedModelPath"),
           UserDefaults.standard.string(forKey: "selectedWhisperModelPath") == nil {
            UserDefaults.standard.set(oldPath, forKey: "selectedWhisperModelPath")
        }
    }
    
    // Engine settings
    @UserDefault(key: "selectedEngine", defaultValue: "whisper")
    var selectedEngine: String
    
    // Model settings
    var selectedModelPath: String? {
        get {
            if selectedEngine == "whisper" {
                return selectedWhisperModelPath
            }
            return nil
        }
        set {
            if selectedEngine == "whisper" {
                selectedWhisperModelPath = newValue
            }
        }
    }
    
    @OptionalUserDefault(key: "selectedWhisperModelPath")
    var selectedWhisperModelPath: String?
    
    @UserDefault(key: "fluidAudioModelVersion", defaultValue: "v3")
    var fluidAudioModelVersion: String
    
    @UserDefault(key: "whisperLanguage", defaultValue: "en")
    var whisperLanguage: String
    
    // Transcription settings
    @UserDefault(key: "translateToEnglish", defaultValue: false)
    var translateToEnglish: Bool
    
    @UserDefault(key: "suppressBlankAudio", defaultValue: true)
    var suppressBlankAudio: Bool
    
    @UserDefault(key: "showTimestamps", defaultValue: false)
    var showTimestamps: Bool
    
    @UserDefault(key: "temperature", defaultValue: 0.0)
    var temperature: Double
    
    @UserDefault(key: "noSpeechThreshold", defaultValue: 0.6)
    var noSpeechThreshold: Double
    
    @UserDefault(key: "initialPrompt", defaultValue: AppPreferences.defaultInitialPrompt)
    var initialPrompt: String
    
    @UserDefault(key: "useBeamSearch", defaultValue: false)
    var useBeamSearch: Bool
    
    @UserDefault(key: "beamSize", defaultValue: 5)
    var beamSize: Int
    
    @UserDefault(key: "debugMode", defaultValue: false)
    var debugMode: Bool
    
    @UserDefault(key: "playSoundOnRecordStart", defaultValue: false)
    var playSoundOnRecordStart: Bool

    @UserDefault(key: "pauseMediaDuringRecording", defaultValue: true)
    var pauseMediaDuringRecording: Bool
    
    @UserDefault(key: "hasCompletedOnboarding", defaultValue: false)
    var hasCompletedOnboarding: Bool
    
    @UserDefault(key: "useAsianAutocorrect", defaultValue: true)
    var useAsianAutocorrect: Bool
    
    @OptionalUserDefault(key: "selectedMicrophoneData")
    var selectedMicrophoneData: Data?
    
    @UserDefault(key: "modifierOnlyHotkey", defaultValue: "none")
    var modifierOnlyHotkey: String
    
    @UserDefault(key: "holdToRecord", defaultValue: true)
    var holdToRecord: Bool
    
    @UserDefault(key: "addSpaceAfterSentence", defaultValue: true)
    var addSpaceAfterSentence: Bool

    /// When on, transcribed text is auto-pasted into the focused app; when off
    /// (or when Accessibility permission is missing) it is left on the clipboard.
    @UserDefault(key: "autoPasteEnabled", defaultValue: true)
    var autoPasteEnabled: Bool

    /// When on, the transcript stays on the clipboard after an auto-paste
    /// instead of the previous clipboard contents being restored.
    @UserDefault(key: "keepTranscriptOnClipboard", defaultValue: true)
    var keepTranscriptOnClipboard: Bool

    /// Auto-delete completed recordings older than N days. 0 = keep forever.
    @UserDefault(key: "historyRetentionDays", defaultValue: 0)
    var historyRetentionDays: Int

    /// Resolve spoken punctuation/formatting commands ("period", "new line").
    @UserDefault(key: "dictationCommandsEnabled", defaultValue: false)
    var dictationCommandsEnabled: Bool

    // Raw value of IndicatorPosition (see IndicatorWindowManager.swift)
    @UserDefault(key: "indicatorPosition", defaultValue: "nearCursor")
    var indicatorPosition: String

    // Raw value of AppTheme (see Theme/AppTheme.swift). Drives every colour in
    // the app, including the indicator pill — which is why the old
    // `indicatorStyle` preference no longer exists.
    @UserDefault(key: "appTheme", defaultValue: "obsidian")
    var appTheme: String

    // LLM formatting (any OpenAI-compatible endpoint).
    // Key names for the toggle and prompt predate the LLM backend, kept for migration.
    @UserDefault(key: "codexFormattingEnabled", defaultValue: false)
    var formattingEnabled: Bool

    @UserDefault(key: "llmBaseURL", defaultValue: "https://api.openai.com/v1")
    var llmBaseURL: String

    @UserDefault(key: "llmApiKey", defaultValue: "")
    var llmApiKey: String

    @UserDefault(key: "llmModel", defaultValue: "gpt-4o-mini")
    var llmModel: String

    @UserDefault(key: "codexFormattingPrompt", defaultValue: AppPreferences.defaultFormattingPrompt)
    var formattingPrompt: String

    // MARK: - Formatting backend

    /// Raw value of `FormattingBackend`. Defaults to the API endpoint so
    /// existing setups are untouched by the on-device addition.
    @UserDefault(key: "formattingBackend", defaultValue: "api")
    var formattingBackend: String

    var formattingBackendValue: FormattingBackend {
        get { FormattingBackend(rawValue: formattingBackend) ?? .api }
        set { formattingBackend = newValue.rawValue }
    }

    /// Which MLX quantization of S1-mini to use — see `S1MiniModelManager.Variant`.
    @UserDefault(key: "s1MiniVariant", defaultValue: "4bit")
    var s1MiniVariant: String

    /// Fallback control-line axes, used when the active formatting mode does
    /// not carry its own.
    @UserDefault(key: "s1DefaultStyling", defaultValue: "semi-formal")
    var s1DefaultStyling: String

    /// Defaults to `lists` rather than `prose`: when the speaker does not
    /// enumerate anything the model leaves the text as prose anyway (measured —
    /// flowing speech comes back with zero bullets and full retention), so this
    /// only changes the output where a list was actually dictated.
    @UserDefault(key: "s1DefaultStructure", defaultValue: "lists")
    var s1DefaultStructure: String

    @UserDefault(key: "s1DefaultContext", defaultValue: "general")
    var s1DefaultContext: String

    // MARK: - Model residency

    /// Load the transcription model and the on-device formatter the moment
    /// recording starts, so the load overlaps with the user speaking instead
    /// of making them wait afterwards.
    @UserDefault(key: "prewarmModelsOnRecord", defaultValue: true)
    var prewarmModelsOnRecord: Bool

    /// Seconds to keep models in memory after the pipeline finishes.
    /// `0` releases immediately; a negative value keeps them resident.
    @UserDefault(key: "modelIdleUnloadSeconds", defaultValue: 60)
    var modelIdleUnloadSeconds: Int

    /// Resolves the control-line axes for the current formatting request,
    /// following the same mode-priority rules as `resolveFormattingPrompt`.
    func resolveS1Axes() -> (styling: S1Styling, structure: S1Structure, context: S1Context) {
        let fallback = (
            styling: S1Styling(rawValue: s1DefaultStyling) ?? .semiFormal,
            structure: S1Structure(rawValue: s1DefaultStructure) ?? .prose,
            context: S1Context(rawValue: s1DefaultContext) ?? .general
        )

        let modes = formattingModes
        guard !modes.isEmpty else { return fallback }

        var selected: FormattingMode?
        if autoSwitchFormattingMode,
           let bundleID = FocusUtils.lastFrontmostBundleID,
           let matched = modes.first(where: { $0.appBundleIDs.contains(bundleID) }) {
            selected = matched
        } else if let active = modes.first(where: { $0.id.uuidString == activeFormattingModeID }) {
            selected = active
        } else {
            selected = modes.first
        }

        guard let mode = selected else { return fallback }
        return (
            styling: mode.styling ?? fallback.styling,
            structure: mode.structure ?? fallback.structure,
            context: mode.context ?? fallback.context
        )
    }

    // MARK: - Custom Vocabulary (word replacements)

    @UserDefault(key: "vocabularyRulesData", defaultValue: Data())
    private var vocabularyRulesData: Data

    /// User-defined spoken→written substitutions applied after transcription.
    var vocabularyRules: [VocabularyRule] {
        get {
            guard !vocabularyRulesData.isEmpty,
                  let decoded = try? JSONDecoder().decode([VocabularyRule].self, from: vocabularyRulesData) else {
                return []
            }
            return decoded
        }
        set {
            vocabularyRulesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    // MARK: - Formatting Modes (prompt presets)

    @UserDefault(key: "formattingModesData", defaultValue: Data())
    private var formattingModesData: Data

    /// Named formatting presets. Seeded from the legacy single prompt on first use.
    var formattingModes: [FormattingMode] {
        get {
            guard !formattingModesData.isEmpty,
                  let decoded = try? JSONDecoder().decode([FormattingMode].self, from: formattingModesData) else {
                return []
            }
            return decoded
        }
        set {
            formattingModesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    /// UUID string of the manually-selected active mode.
    @UserDefault(key: "activeFormattingModeID", defaultValue: "")
    var activeFormattingModeID: String

    /// When on, the mode auto-switches based on the app that was frontmost
    /// when recording started (via matching app bundle IDs).
    @UserDefault(key: "autoSwitchFormattingMode", defaultValue: false)
    var autoSwitchFormattingMode: Bool

    /// Ensures at least one mode exists, migrating the legacy single prompt.
    func ensureDefaultFormattingMode() {
        guard formattingModes.isEmpty else { return }
        let existing = formattingPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let seed = FormattingMode(
            name: "General",
            prompt: existing.isEmpty ? AppPreferences.defaultFormattingPrompt : existing
        )
        formattingModes = [seed]
        activeFormattingModeID = seed.id.uuidString
    }
}
