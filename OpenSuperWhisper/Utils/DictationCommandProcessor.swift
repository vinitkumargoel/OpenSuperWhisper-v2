import Foundation

/// Turns spoken punctuation/formatting commands into real characters, e.g.
/// "send it today period new line thanks" → "Send it today.\nThanks".
///
/// Opt-in via `AppPreferences.dictationCommandsEnabled`. Applied to the raw
/// transcript before AI formatting / vocabulary substitution.
enum DictationCommandProcessor {

    /// A spoken phrase and the literal it becomes.
    /// `attaches` = punctuation that hugs the previous word (no space before,
    /// one space after). Otherwise the replacement consumes surrounding spaces.
    private struct Command {
        let phrases: [String]
        let replacement: String
        let attaches: Bool
    }

    // Ordered longest-phrase-first so multi-word commands win over single words.
    private static let commands: [Command] = [
        Command(phrases: ["new paragraph"], replacement: "\n\n", attaches: false),
        Command(phrases: ["new line", "newline"], replacement: "\n", attaches: false),
        Command(phrases: ["full stop", "period"], replacement: ".", attaches: true),
        Command(phrases: ["question mark"], replacement: "?", attaches: true),
        Command(phrases: ["exclamation mark", "exclamation point"], replacement: "!", attaches: true),
        Command(phrases: ["open parenthesis", "open paren"], replacement: "(", attaches: false),
        Command(phrases: ["close parenthesis", "close paren"], replacement: ")", attaches: true),
        Command(phrases: ["semicolon"], replacement: ";", attaches: true),
        Command(phrases: ["colon"], replacement: ":", attaches: true),
        Command(phrases: ["comma"], replacement: ",", attaches: true),
        Command(phrases: ["ellipsis"], replacement: "…", attaches: true),
        Command(phrases: ["hyphen", "dash"], replacement: "-", attaches: true),
    ]

    /// A short reference list for the settings UI.
    static let supportedSummary = "new line · new paragraph · period · comma · question mark · exclamation mark · colon · semicolon · open/close parenthesis"

    static func apply(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text

        for command in commands {
            for phrase in command.phrases {
                let escaped = NSRegularExpression.escapedPattern(for: phrase)
                // Match the phrase as whole words, case-insensitive, with any
                // surrounding whitespace so we can control spacing ourselves.
                let pattern = "\\s*\\b\(escaped)\\b\\s*"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
                let replacement = command.attaches ? command.replacement + " " : command.replacement
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: replacement)
            }
        }

        result = tidy(result)
        return capitalizeSentences(result)
    }

    /// Collapse doubled spaces and trim spaces around newlines / string ends.
    private static func tidy(_ text: String) -> String {
        var t = text
        t = t.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: " +([.,?!:;])", with: "$1", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Capitalize the first letter of the text and the first letter after
    /// sentence-ending punctuation or a newline. Built with String concatenation
    /// because some letters uppercase to multiple graphemes (e.g. "ß" → "SS"),
    /// which would trap `Character(String)`.
    private static func capitalizeSentences(_ text: String) -> String {
        var result = ""
        var capitalizeNext = true
        for c in text {
            if capitalizeNext, c.isLetter {
                result += c.uppercased()
                capitalizeNext = false
            } else {
                result.append(c)
                if ".!?\n".contains(c) {
                    capitalizeNext = true
                } else if !c.isWhitespace {
                    capitalizeNext = false
                }
            }
        }
        return result
    }
}
