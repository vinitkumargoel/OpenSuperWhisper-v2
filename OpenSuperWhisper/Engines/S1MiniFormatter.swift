import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Runs S1-mini by Superwhisper on-device through MLX.
///
/// The actor owns the loaded model and is the only thing that can load or free
/// it, so "is it in memory right now" has exactly one answer. Loading is never
/// triggered by app launch — see `ModelResidency`, which prewarms this at the
/// moment recording starts so the load overlaps with the user still talking.
actor S1MiniFormatter {
    static let shared = S1MiniFormatter()

    private var container: ModelContainer?
    private var loadTask: Task<ModelContainer, Error>?
    /// Directory the loaded container came from, so switching quantization
    /// while a model is resident reloads instead of silently using the old one.
    private var loadedDirectory: URL?

    private init() {}

    var isLoaded: Bool { container != nil }

    // MARK: - Loading

    /// Loads the model if it isn't already. Safe to call repeatedly and from
    /// anywhere: concurrent callers await the same load rather than starting
    /// a second one.
    @discardableResult
    func load() async throws -> ModelContainer {
        let directory = await MainActor.run { S1MiniModelManager.shared.selectedDirectory }
        let installed = await MainActor.run { S1MiniModelManager.shared.isSelectedInstalled }
        guard installed else { throw S1MiniError.notInstalled }

        if let container, loadedDirectory == directory {
            return container
        }
        if loadedDirectory != nil, loadedDirectory != directory {
            unloadNow()
        }
        if let loadTask {
            return try await loadTask.value
        }

        let task = Task<ModelContainer, Error> {
            // MLX caches GPU buffers aggressively by default, which on a
            // 16 GB machine can hold hundreds of megabytes long after a
            // generation finishes. A small cache is the right trade for a
            // model that runs for under a second at a time.
            MLX.Memory.cacheLimit = 64 * 1024 * 1024

            do {
                return try await LLMModelFactory.shared.loadContainer(
                    from: directory,
                    using: S1MiniTokenizerLoader()
                )
            } catch {
                throw S1MiniError.loadFailed(error.localizedDescription)
            }
        }
        loadTask = task

        do {
            let loaded = try await task.value
            container = loaded
            loadedDirectory = directory
            loadTask = nil
            return loaded
        } catch {
            loadTask = nil
            throw error
        }
    }

    /// Loads in the background and swallows errors — used at recording start,
    /// where a failure should surface later at the actual format call rather
    /// than interrupting the recording the user just began.
    func prewarm() {
        guard container == nil, loadTask == nil else { return }
        Task { [weak self] in
            _ = try? await self?.load()
        }
    }

    func unload() {
        unloadNow()
    }

    private func unloadNow() {
        loadTask?.cancel()
        loadTask = nil
        container = nil
        loadedDirectory = nil
        // Dropping the container releases the weights, but MLX's buffer cache
        // survives it; clearing is what actually returns the memory.
        MLX.Memory.clearCache()
    }

    // MARK: - Formatting

    /// Formats one transcript. Long transcripts are split at sentence
    /// boundaries and formatted chunk by chunk, because the model is built for
    /// dictation-length input.
    func format(
        _ text: String,
        styling: S1Styling,
        structure: S1Structure,
        context: S1Context
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        let container = try await load()
        let chunks = S1MiniPrompt.chunk(trimmed)

        var results: [String] = []
        results.reserveCapacity(chunks.count)
        for chunk in chunks {
            let output = try await generate(
                container: container,
                transcript: chunk,
                styling: styling,
                structure: structure,
                context: context
            )
            // Filler-only input legitimately returns an empty string — the
            // model card is explicit that this is a valid result, not a
            // failure — so empty chunks are dropped rather than thrown on.
            if !output.isEmpty { results.append(output) }
        }

        // Free the scratch buffers this generation allocated. The weights stay
        // resident; ModelResidency decides when those go.
        MLX.Memory.clearCache()

        return results.joined(separator: "\n\n")
    }

    private func generate(
        container: ModelContainer,
        transcript: String,
        styling: S1Styling,
        structure: S1Structure,
        context: S1Context
    ) async throws -> String {
        let prompt = S1MiniPrompt.build(
            transcript: transcript,
            styling: styling,
            structure: structure,
            context: context
        )

        return try await container.perform { modelContext in
            // The prompt already spells out every special token, so the
            // tokenizer must not add its own.
            let tokens = modelContext.tokenizer.encode(text: prompt, addSpecialTokens: false)
            let input = LMInput(tokens: MLXArray(tokens))

            let parameters = GenerateParameters(
                maxTokens: S1MiniPrompt.maxTokens(forPromptTokens: tokens.count),
                // Normalization is a deterministic transformation. The model
                // ships do_sample: false for the same reason.
                temperature: 0,
                // S1-mini is a normalizer, not a summarizer: it reproduces
                // repetition the ASR handed it rather than collapsing it. Under
                // greedy decoding a phrase Whisper stuttered can capture the
                // argmax and consume the entire token budget — a six-minute
                // recording lost 56% of its content that way. 1.1 is the
                // measured optimum on real transcripts: 1.05 does not break the
                // loop, and 1.15+ starts deleting repeats the speaker genuinely
                // made.
                repetitionPenalty: 1.1,
                repetitionContextSize: 64
            )

            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: parameters,
                context: modelContext
            )

            // Second line of defence. The penalty above fixes every case seen in
            // practice, but an unpunctuated monologue can still run the budget
            // out, so generation stops once the tail has genuinely locked up.
            var guardState = LoopGuard()
            var output = ""
            for await generation in stream {
                if let chunk = generation.chunk {
                    output += chunk
                    if guardState.isLooping(appending: chunk) { break }
                }
            }
            return S1MiniPrompt.cleanOutput(output)
        }
    }
}

/// Stops generation once the output has locked into a repeating tail.
///
/// The thresholds are deliberately loose, and the reason matters: real dictation
/// repeats itself constantly. In the transcript this was tuned against the
/// speaker says "Once everything is paid off" twice and "I am 32 right now"
/// three times, and any guard tight enough to catch a runaway in a few
/// repetitions also truncates that — measured at 0.55 content retention versus
/// 0.98 for the settings below. Six identical twelve-word windows is not
/// hesitation, it is a stuck sampler.
///
/// Works on decoded text rather than token ids because `MLXLMCommon.generate`
/// yields `.chunk(String)`; the window was re-tuned in word space rather than
/// converted from the token-space figure.
///
/// Evaluates once per completed word rather than once per streamed chunk. That
/// matters twice over: a chunk can carry several words or half of one, so
/// chunk-boundary sampling would both skip windows and key them on fragments —
/// and the thresholds above were tuned against a harness that stepped per word,
/// so anything else would not be measuring what was tuned.
private struct LoopGuard {
    private static let windowWords = 12
    private static let maxRepeats = 6

    /// Only the current window is retained, so this stays flat in memory
    /// however long generation runs.
    private var window: [String] = []
    /// A chunk can end mid-word; the fragment waits here for its remainder.
    private var partial = ""
    private var counts: [String: Int] = [:]
    private var tripped = false

    /// Feed each streamed chunk in order. Amortised O(1) per word.
    mutating func isLooping(appending chunk: String) -> Bool {
        guard !tripped else { return true }
        partial += chunk

        while let boundary = partial.rangeOfCharacter(from: .whitespacesAndNewlines) {
            let word = String(partial[..<boundary.lowerBound])
            partial = String(partial[boundary.upperBound...])
            guard !word.isEmpty else { continue }
            if consume(word) {
                tripped = true
                return true
            }
        }
        return false
    }

    private mutating func consume(_ word: String) -> Bool {
        window.append(word.lowercased())
        if window.count > Self.windowWords { window.removeFirst() }
        guard window.count == Self.windowWords else { return false }

        let key = window.joined(separator: " ")
        let seen = (counts[key] ?? 0) + 1
        counts[key] = seen
        return seen > Self.maxRepeats
    }
}

/// Adapts swift-transformers' tokenizer to the protocol mlx-swift-lm expects.
/// mlx-swift-lm 3.x deliberately ships no tokenizer of its own so callers can
/// pick their own implementation; this is that choice.
private struct S1MiniTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
        return Bridge(upstream)
    }

    private struct Bridge: MLXLMCommon.Tokenizer {
        private let upstream: any Tokenizers.Tokenizer

        init(_ upstream: any Tokenizers.Tokenizer) {
            self.upstream = upstream
        }

        func encode(text: String, addSpecialTokens: Bool) -> [Int] {
            upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
        }

        func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
            upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
        }

        func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
        func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

        var bosToken: String? { upstream.bosToken }
        var eosToken: String? { upstream.eosToken }
        var unknownToken: String? { upstream.unknownToken }

        func applyChatTemplate(
            messages: [[String: any Sendable]],
            tools: [[String: any Sendable]]?,
            additionalContext: [String: any Sendable]?
        ) throws -> [Int] {
            // Unused: S1-mini's prompt is built by hand precisely so the
            // template's thinking-on default can never apply.
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
