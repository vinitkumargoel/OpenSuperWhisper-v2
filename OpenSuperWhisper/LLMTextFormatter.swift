import Foundation

enum LLMTextFormatterError: LocalizedError {
    case invalidURL
    case missingAPIKey
    case emptyOutput
    case httpError(Int, String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The formatting API base URL is invalid."
        case .missingAPIKey:
            return "No API key configured for formatting."
        case .emptyOutput:
            return "The formatting model returned an empty response."
        case .httpError(let code, let message):
            return "Formatting request failed (HTTP \(code)): \(message)"
        case .decodingFailed:
            return "Could not decode the formatting API response."
        }
    }
}

/// Formats transcripts via any OpenAI-compatible chat completions API
/// (OpenAI, OpenRouter, Groq, Ollama, LM Studio, llama.cpp server, ...).
struct LLMTextFormatter {
    private let timeout: TimeInterval = 60

    func format(_ text: String, modelOverride: String? = nil) async throws -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return text }

        let prefs = AppPreferences.shared
        let baseURL = Self.normalizedBaseURL(prefs.llmBaseURL)
        let apiKey = prefs.llmApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let override = modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = override.isEmpty
            ? prefs.llmModel.trimmingCharacters(in: .whitespacesAndNewlines)
            : override
        // Resolve the active formatting mode's prompt (falls back to the
        // legacy single prompt when no modes are configured).
        let instruction = prefs.resolveFormattingPrompt().trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: baseURL + "/chat/completions") else {
            throw LLMTextFormatterError.invalidURL
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": instruction.isEmpty ? AppPreferences.defaultFormattingPrompt : instruction],
                ["role": "user", "content": trimmedText],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMTextFormatterError.decodingFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
            throw LLMTextFormatterError.httpError(http.statusCode, String(message))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMTextFormatterError.decodingFailed
        }

        let cleaned = Self.cleanOutput(content)
        guard !cleaned.isEmpty else {
            throw LLMTextFormatterError.emptyOutput
        }
        return cleaned
    }

    /// Lists model ids from {baseURL}/models for the settings picker.
    static func fetchAvailableModels(baseURL: String, apiKey: String) async throws -> [String] {
        guard let url = URL(string: normalizedBaseURL(baseURL) + "/models") else {
            throw LLMTextFormatterError.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMTextFormatterError.decodingFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
            throw LLMTextFormatterError.httpError(http.statusCode, String(message))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else {
            throw LLMTextFormatterError.decodingFailed
        }
        return models.compactMap { $0["id"] as? String }.sorted()
    }

    static func normalizedBaseURL(_ raw: String) -> String {
        var base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base = String(base.dropLast())
        }
        // Bare host[:port] input like "100.105.72.106:8317/v1" — assume http.
        if !base.isEmpty, !base.lowercased().hasPrefix("http://"), !base.lowercased().hasPrefix("https://") {
            base = "http://" + base
        }
        return base
    }

    private static func cleanOutput(_ output: String) -> String {
        var cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.hasPrefix("```") {
            var lines = cleaned.components(separatedBy: .newlines)
            if let first = lines.first, first.hasPrefix("```") {
                lines.removeFirst()
            }
            if let last = lines.last, last.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
                lines.removeLast()
            }
            cleaned = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleaned
    }
}

enum FinalTextProcessor {
    /// - Parameter onFormattingFailed: called when AI formatting was enabled but
    ///   errored. The raw transcript is still returned, so callers should report
    ///   this rather than let a bad API key look like a bad transcription.
    static func formatIfNeeded(
        _ text: String,
        onWillFormat: (() async -> Void)? = nil,
        onFormattingFailed: ((Error) -> Void)? = nil
    ) async -> String {
        // Spoken punctuation/formatting commands ("period", "new line") are
        // resolved first, on the raw transcript, when the user enables them.
        var input = text
        if AppPreferences.shared.dictationCommandsEnabled {
            input = DictationCommandProcessor.apply(input)
        }

        // Custom-vocabulary substitutions always apply — even with AI formatting
        // off — so proper nouns and jargon are corrected in the pasted text.
        guard AppPreferences.shared.formattingEnabled else {
            return VocabularyProcessor.applyConfigured(input)
        }

        do {
            await onWillFormat?()
            let formatted: String
            switch AppPreferences.shared.formattingBackendValue {
            case .api:
                formatted = try await LLMTextFormatter().format(input)
            case .s1mini:
                let axes = AppPreferences.shared.resolveS1Axes()
                let output = try await S1MiniFormatter.shared.format(
                    input,
                    styling: axes.styling,
                    structure: axes.structure,
                    context: axes.context
                )
                // Filler-only speech normalizes to nothing. That is a correct
                // result from the model, but pasting an empty string would
                // look like a failure, so the raw transcript stands instead.
                formatted = output.isEmpty ? input : output
            }
            return VocabularyProcessor.applyConfigured(formatted)
        } catch {
            print("LLM formatting failed: \(error.localizedDescription)")
            onFormattingFailed?(error)
            return VocabularyProcessor.applyConfigured(input)
        }
    }

    static func applyPastePostProcessing(_ text: String) -> String {
        guard AppPreferences.shared.addSpaceAfterSentence,
              let lastChar = text.last,
              lastChar.isPunctuation else {
            return text
        }
        return text + " "
    }
}
