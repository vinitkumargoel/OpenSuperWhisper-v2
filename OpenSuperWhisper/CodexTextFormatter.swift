import Foundation

enum CodexTextFormatterError: LocalizedError {
    case emptyOutput
    case launchFailed(String)
    case timedOut
    case failed(Int32, String)

    var errorDescription: String? {
        switch self {
        case .emptyOutput:
            return "Codex returned an empty response."
        case .launchFailed(let message):
            return "Failed to launch Codex: \(message)"
        case .timedOut:
            return "Codex formatting timed out."
        case .failed(let code, let message):
            return "Codex exited with code \(code): \(message)"
        }
    }
}

struct CodexTextFormatter {
    private let timeout: TimeInterval = 90

    func format(_ text: String) async throws -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return text }

        let prefs = AppPreferences.shared
        let executable = prefs.codexExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = prefs.codexModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = prefs.codexFormattingPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        return try await Task.detached(priority: .userInitiated) {
            try runCodex(
                executable: executable.isEmpty ? "codex" : executable,
                model: model.isEmpty ? "gpt-5.2" : model,
                instruction: instruction.isEmpty ? AppPreferences.defaultCodexFormattingPrompt : instruction,
                text: trimmedText
            )
        }.value
    }

    private func runCodex(executable: String, model: String, instruction: String, text: String) throws -> String {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensuperwhisper-codex-\(UUID().uuidString).txt")
        let errorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensuperwhisper-codex-\(UUID().uuidString).err")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }

        let prompt = """
        \(instruction)

        Transcript:
        \(text)
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            executable,
            "exec",
            "-c",
            "model_reasoning_effort=\"low\"",
            "--model",
            model,
            "--sandbox",
            "read-only",
            "--skip-git-repo-check",
            "--ephemeral",
            "--color",
            "never",
            "--output-last-message",
            outputURL.path,
            "-"
        ]
        process.environment = codexEnvironment()

        let inputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        process.standardError = errorHandle

        do {
            try process.run()
        } catch {
            try? errorHandle.close()
            throw CodexTextFormatterError.launchFailed(error.localizedDescription)
        }

        if let input = prompt.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(input)
        }
        inputPipe.fileHandleForWriting.closeFile()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        if process.isRunning {
            process.terminate()
            try? errorHandle.close()
            throw CodexTextFormatterError.timedOut
        }

        try? errorHandle.close()

        guard process.terminationStatus == 0 else {
            let message = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
            throw CodexTextFormatterError.failed(process.terminationStatus, message)
        }

        let rawOutput = (try? String(contentsOf: outputURL, encoding: .utf8))
            ?? ""
        let cleaned = cleanCodexOutput(rawOutput)
        guard !cleaned.isEmpty else {
            throw CodexTextFormatterError.emptyOutput
        }
        return cleaned
    }

    private func codexEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let fallbackPath = [
            "\(home)/.nvm/versions/node/v20.17.0/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ].joined(separator: ":")

        if let currentPath = environment["PATH"], !currentPath.isEmpty {
            environment["PATH"] = "\(currentPath):\(fallbackPath)"
        } else {
            environment["PATH"] = fallbackPath
        }

        return environment
    }

    private func cleanCodexOutput(_ output: String) -> String {
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
    static func formatIfNeeded(_ text: String, onWillFormat: (() async -> Void)? = nil) async -> String {
        guard AppPreferences.shared.codexFormattingEnabled else {
            return text
        }

        do {
            await onWillFormat?()
            return try await CodexTextFormatter().format(text)
        } catch {
            print("Codex formatting failed: \(error.localizedDescription)")
            return text
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
