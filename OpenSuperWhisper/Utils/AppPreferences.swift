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

    /// Auto-delete completed recordings older than N days. 0 = keep forever.
    @UserDefault(key: "historyRetentionDays", defaultValue: 0)
    var historyRetentionDays: Int

    /// Resolve spoken punctuation/formatting commands ("period", "new line").
    @UserDefault(key: "dictationCommandsEnabled", defaultValue: false)
    var dictationCommandsEnabled: Bool

    // Raw value of IndicatorPosition (see IndicatorWindowManager.swift)
    @UserDefault(key: "indicatorPosition", defaultValue: "nearCursor")
    var indicatorPosition: String

    // Raw value of IndicatorStyle (see IndicatorStyle.swift)
    @UserDefault(key: "indicatorStyle", defaultValue: "classic")
    var indicatorStyle: String

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
