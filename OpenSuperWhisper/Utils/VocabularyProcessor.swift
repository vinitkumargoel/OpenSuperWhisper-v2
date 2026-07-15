import Foundation

/// A single spoken-term → written-term substitution used to fix proper nouns,
/// jargon, and acronyms that the transcription model mishears consistently.
struct VocabularyRule: Codable, Identifiable, Equatable {
    var id: UUID
    /// The (mis)transcribed text to look for, e.g. "clod code".
    var from: String
    /// The corrected replacement, e.g. "Claude Code".
    var to: String
    /// When true, only replace when the surrounding case matches exactly.
    var caseSensitive: Bool

    init(id: UUID = UUID(), from: String = "", to: String = "", caseSensitive: Bool = false) {
        self.id = id
        self.from = from
        self.to = to
        self.caseSensitive = caseSensitive
    }
}

/// Applies the user's custom-vocabulary substitutions to a transcript as a
/// deterministic post-processing pass (whole-word, order-preserving).
enum VocabularyProcessor {
    static func apply(_ text: String, rules: [VocabularyRule]) -> String {
        guard !text.isEmpty, !rules.isEmpty else { return text }

        var result = text
        for rule in rules {
            let from = rule.from.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !from.isEmpty else { continue }

            let escaped = NSRegularExpression.escapedPattern(for: from)
            // Add word boundaries only where the term edge is a word character,
            // so multi-word and symbol-containing terms still match sensibly.
            let leading = (from.first?.isLetter == true || from.first?.isNumber == true) ? "\\b" : ""
            let trailing = (from.last?.isLetter == true || from.last?.isNumber == true) ? "\\b" : ""
            let pattern = leading + escaped + trailing

            var options: NSRegularExpression.Options = []
            if !rule.caseSensitive { options.insert(.caseInsensitive) }

            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            let template = NSRegularExpression.escapedTemplate(for: rule.to)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: template)
        }
        return result
    }

    /// Convenience overload using the globally-configured rules.
    static func applyConfigured(_ text: String) -> String {
        apply(text, rules: AppPreferences.shared.vocabularyRules)
    }
}
