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
    /// `ambiguous` = the phrase is also an everyday English word ("a period of
    /// time", "comma separated values"), so it only converts when the
    /// surrounding words don't read as ordinary prose.
    private struct Command {
        let phrases: [String]
        let replacement: String
        let attaches: Bool
        var ambiguous: Bool = false
    }

    // Ordered longest-phrase-first so multi-word commands win over single words.
    private static let commands: [Command] = [
        Command(phrases: ["new paragraph"], replacement: "\n\n", attaches: false),
        Command(phrases: ["new line", "newline"], replacement: "\n", attaches: false),
        Command(phrases: ["full stop"], replacement: ".", attaches: true),
        Command(phrases: ["question mark"], replacement: "?", attaches: true),
        Command(phrases: ["exclamation mark", "exclamation point"], replacement: "!", attaches: true),
        Command(phrases: ["open parenthesis", "open paren"], replacement: "(", attaches: false),
        Command(phrases: ["close parenthesis", "close paren"], replacement: ")", attaches: true),
        Command(phrases: ["period"], replacement: ".", attaches: true, ambiguous: true),
        Command(phrases: ["semicolon"], replacement: ";", attaches: true, ambiguous: true),
        Command(phrases: ["colon"], replacement: ":", attaches: true, ambiguous: true),
        Command(phrases: ["comma"], replacement: ",", attaches: true, ambiguous: true),
        Command(phrases: ["ellipsis"], replacement: "…", attaches: true, ambiguous: true),
        Command(phrases: ["hyphen", "dash"], replacement: "-", attaches: true, ambiguous: true),
    ]

    /// Words that turn a following command word into a noun ("a period", "the comma").
    private static let determiners = [
        "a", "an", "the", "this", "that", "these", "those", "one", "each",
        "every", "per", "of", "in", "any", "some", "no",
        "my", "your", "his", "her", "its", "our", "their"
    ]

    /// Words that follow a command word when it is being used as a noun
    /// ("comma separated", "colon cancer", "period of time").
    private static let nounFollowers = [
        "of", "is", "are", "was", "were", "key", "separated", "delimited", "cancer"
    ]

    /// Abbreviations whose trailing dot does not end a sentence.
    private static let abbreviations: Set<String> = [
        "e.g", "i.e", "etc", "vs", "mr", "mrs", "ms", "dr", "prof",
        "fig", "approx", "st", "jr", "sr", "inc", "ltd"
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
                let guards = command.ambiguous
                    ? "(?<!\\b(?:\(determiners.joined(separator: "|"))) )"
                    : ""
                let trailingGuard = command.ambiguous
                    ? "(?!\\s+(?:\(nounFollowers.joined(separator: "|")))\\b)"
                    : ""
                // Only spaces/tabs are absorbed - a \s* here would swallow the
                // newline a previously-applied "new line" command just inserted.
                let pattern = "[ \\t]*\\b\(guards)\(escaped)\\b\(trailingGuard)[ \\t]*"
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

    /// Capitalize the first letter of the text, the first letter after a newline,
    /// and the first letter after a genuine sentence end.
    ///
    /// A `.` is *not* a sentence end when it belongs to a decimal ("v1.2"), an
    /// abbreviation ("e.g. this", "etc. and"), or an initial ("U.S. based") —
    /// capitalizing there mangles ordinary text. Built with String concatenation
    /// because some letters uppercase to multiple graphemes (e.g. "ß" → "SS"),
    /// which would trap `Character(String)`.
    private static func capitalizeSentences(_ text: String) -> String {
        let chars = Array(text)
        var result = ""
        var capitalizeNext = true

        for (index, c) in chars.enumerated() {
            if capitalizeNext, c.isLetter {
                result += c.uppercased()
                capitalizeNext = false
                continue
            }

            result.append(c)

            if c == "\n" {
                capitalizeNext = true
            } else if c == "!" || c == "?" {
                capitalizeNext = true
            } else if c == "." {
                capitalizeNext = endsSentence(chars, dotIndex: index)
            } else if !c.isWhitespace {
                capitalizeNext = false
            }
        }
        return result
    }

    /// Whether the `.` at `dotIndex` terminates a sentence.
    private static func endsSentence(_ chars: [Character], dotIndex: Int) -> Bool {
        // "3.5" / "v1.2" — a decimal point, not a full stop.
        if dotIndex > 0, chars[dotIndex - 1].isNumber { return false }

        // ". 5 items" — a number can't start a sentence here either.
        var next = dotIndex + 1
        while next < chars.count, chars[next] == " " || chars[next] == "\t" { next += 1 }
        if next < chars.count, chars[next].isNumber { return false }

        // Collect the token immediately before the dot, allowing inner dots so
        // "e.g" and "U.S" are seen whole.
        var start = dotIndex
        while start > 0 {
            let prev = chars[start - 1]
            guard prev.isLetter || prev == "." else { break }
            start -= 1
        }
        let token = String(chars[start..<dotIndex]).lowercased()

        if abbreviations.contains(token) { return false }
        // A lone initial ("J." in "J. Smith").
        if token.count == 1 { return false }

        // A dotted initialism - every part is a single letter ("U.S.", "a.m.").
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count > 1, parts.allSatisfy({ $0.count == 1 }) { return false }

        return true
    }
}
