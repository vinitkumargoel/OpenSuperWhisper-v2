import Foundation

/// Builds the exact input format S1-mini was trained on.
///
/// Two things in here are not stylistic choices and must not be "improved":
///
/// 1. The system prompt is verbatim from the model card. It is part of the
///    trained input format, not an instruction. Rewording it makes the model
///    hallucinate.
/// 2. The assistant turn opens with an empty `<think>` block. S1-mini was
///    trained with thinking disabled; without this prefix the model emits an
///    empty think block and stops, which is the usual cause of blank output.
///
/// The template is written out by hand rather than run through the repo's
/// Jinja chat template, because the template defaults thinking *on* and the
/// flag that disables it is easy to lose. A literal string cannot drift.
enum S1MiniPrompt {
    /// Verbatim from the model card. Do not reword.
    static let systemPrompt =
        "You are a text normalizer for speech-to-text transcripts. The input begins "
        + "with a control line specifying the styling, structure, and context settings; "
        + "clean the transcript to match those settings and output only the cleaned text."

    /// `[Styling: ...] [Structure: ...] [Context: ...]` — the model's only
    /// steering mechanism. Values outside the trained sets garble the output,
    /// which is why these come from enums rather than free text.
    static func controlLine(styling: S1Styling, structure: S1Structure, context: S1Context) -> String {
        "[Styling: \(styling.rawValue)] [Structure: \(structure.rawValue)] [Context: \(context.rawValue)]"
    }

    /// The full prompt, ready to tokenize with `addSpecialTokens: false` — the
    /// special tokens are already written out here.
    static func build(
        transcript: String,
        styling: S1Styling,
        structure: S1Structure,
        context: S1Context
    ) -> String {
        let control = controlLine(styling: styling, structure: structure, context: context)
        return """
        <|im_start|>system
        \(systemPrompt)<|im_end|>
        <|im_start|>user
        \(control)
        \(transcript)<|im_end|>
        <|im_start|>assistant
        <think>

        </think>


        """
    }

    /// Output length tracks input length closely, so sizing the budget to the
    /// input is both safer and much cheaper than a flat 1024. The formula is
    /// the model card's own recommendation.
    static func maxTokens(forPromptTokens promptTokenCount: Int) -> Int {
        max(64, Int(Double(promptTokenCount) * 1.3) + 32)
    }

    /// Strips anything the model may echo around the answer. S1-mini normally
    /// returns bare text, but a stray think block or fence should never reach
    /// the user's clipboard.
    static func cleanOutput(_ raw: String) -> String {
        var text = raw

        if let thinkEnd = text.range(of: "</think>") {
            text = String(text[thinkEnd.upperBound...])
        }
        for token in ["<|im_end|>", "<|endoftext|>", "<|im_start|>"] {
            text = text.replacingOccurrences(of: token, with: "")
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("```") {
            var lines = text.components(separatedBy: .newlines)
            if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
            if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" { lines.removeLast() }
            text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text
    }

    /// Splits a transcript that would exceed the model's comfortable input
    /// range into sentence-aligned chunks. Dictation is almost never this
    /// long, so the common path returns a single chunk untouched.
    ///
    /// - Parameter maxCharacters: roughly 4 characters per token, so this is
    ///   about 250 tokens per pass — well clear of the model card's ~1,000-token
    ///   ceiling rather than pressed against it.
    ///
    ///   The previous 3,200 was sized to sit just under that ceiling, which put
    ///   every long dictation into the range where output degrades: a 2,937-char
    ///   transcript went through as a single 923-token pass and looped. Smaller
    ///   passes are also *faster* end to end (5.2 s versus 5.9 s on that
    ///   transcript) because a short pass carries a small token budget, so a
    ///   generation that does go wrong has less room to run. There is no
    ///   quality cost: retention measured identically at both sizes.
    static func chunk(_ text: String, maxCharacters: Int = 1000) -> [String] {
        guard text.count > maxCharacters else { return [text] }

        // Sentence-ish boundaries: keep the terminator with the sentence it ends.
        var sentences: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == "." || character == "!" || character == "?" || character == "\n" {
                sentences.append(current)
                current = ""
            }
        }
        if !current.isEmpty { sentences.append(current) }

        var chunks: [String] = []
        var buffer = ""
        for sentence in sentences {
            if buffer.count + sentence.count > maxCharacters, !buffer.isEmpty {
                chunks.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
                buffer = ""
            }
            buffer += sentence
        }
        if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return chunks.isEmpty ? [text] : chunks
    }
}
