import Foundation

/// Which engine cleans up the transcript once AI formatting is enabled.
enum FormattingBackend: String, CaseIterable, Identifiable {
    /// Any OpenAI-compatible chat completions endpoint (OpenAI, OpenRouter,
    /// Groq, Ollama, LM Studio, llama.cpp server, ...).
    case api

    /// S1-mini by Superwhisper, running on-device through MLX. Loaded when
    /// recording starts and released again once the pipeline goes idle.
    case s1mini

    var id: String { rawValue }

    var title: String {
        switch self {
        case .api: return "API endpoint"
        case .s1mini: return "On-device"
        }
    }

    var subtitle: String {
        switch self {
        case .api:
            return "Send the transcript to an OpenAI-compatible URL. Free-text prompts, any model."
        case .s1mini:
            return "Run S1-mini by Superwhisper locally. Nothing leaves the Mac; works offline."
        }
    }
}

/// The three control-line axes S1-mini was trained on. The model has no other
/// steering mechanism — its system prompt is fixed — so these replace the
/// free-text prompt when the on-device backend is selected.
enum S1Styling: String, CaseIterable, Identifiable, Codable {
    case casual
    case semiCasual = "semi-casual"
    case semiFormal = "semi-formal"
    case formal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .casual: return "Casual"
        case .semiCasual: return "Semi-casual"
        case .semiFormal: return "Semi-formal"
        case .formal: return "Formal"
        }
    }

    var detail: String {
        switch self {
        case .casual:
            return "All lowercase, apostrophes stripped, colloquialisms kept."
        case .semiCasual:
            return "Keeps your phrasing. Capitalizes \"I\"; sentence starts stay lowercase."
        case .semiFormal:
            return "Standard written English. Contractions kept, \"gonna\" becomes \"going to\"."
        case .formal:
            return "Like semi-formal, with contractions expanded to \"I am\", \"cannot\"."
        }
    }
}

enum S1Structure: String, CaseIterable, Identifiable, Codable {
    case prose
    case lists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prose: return "Prose"
        case .lists: return "Lists"
        }
    }

    var detail: String {
        switch self {
        case .prose: return "Everything stays in sentences and paragraphs."
        case .lists: return "May break three or more enumerable items into bullets."
        }
    }
}

enum S1Context: String, CaseIterable, Identifiable, Codable {
    case general
    case email

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .email: return "Email"
        }
    }

    var detail: String {
        switch self {
        case .general: return "Flowing text."
        case .email: return "Greeting line, body, and sign-off block."
        }
    }
}

/// Settings for one manual reformat. Defaults mirror whatever the user has
/// configured, so the Reformat button reproduces the live pipeline unless they
/// deliberately change something in the popover.
struct ReformatOptions {
    var backend: FormattingBackend
    /// API backend only; nil uses the configured model.
    var model: String?
    var styling: S1Styling
    var structure: S1Structure
    var context: S1Context

    /// Reads the current settings, including the active formatting mode's axes.
    static func fromCurrentSettings() -> ReformatOptions {
        let prefs = AppPreferences.shared
        let axes = prefs.resolveS1Axes()
        return ReformatOptions(
            backend: prefs.formattingBackendValue,
            model: nil,
            styling: axes.styling,
            structure: axes.structure,
            context: axes.context
        )
    }
}
