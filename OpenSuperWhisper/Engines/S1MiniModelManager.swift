import Foundation

/// Downloads and stores the S1-mini weights.
///
/// The weights live beside the Whisper models in Application Support rather
/// than inside the bundle: at 347 MB they are far too big to ship, and the
/// user should be able to delete them without reinstalling the app.
@MainActor
final class S1MiniModelManager: ObservableObject {
    static let shared = S1MiniModelManager()

    /// The 4-bit MLX conversion. Quality is measured on a 4-bit-class build in
    /// the model card, so this is the default rather than a compromise.
    struct Variant: Identifiable, Equatable {
        let id: String
        let repo: String
        let title: String
        let approximateBytes: Int64

        static let fourBit = Variant(
            id: "4bit",
            repo: "mlx-community/S1-mini-MLX-4bit",
            title: "4-bit (recommended)",
            approximateBytes: 347_000_000
        )
        static let eightBit = Variant(
            id: "8bit",
            repo: "mlx-community/S1-mini-MLX-8bit",
            title: "8-bit (higher fidelity)",
            approximateBytes: 645_000_000
        )

        static let all: [Variant] = [.fourBit, .eightBit]
    }

    /// Files required for a usable model directory. `chat_template.jinja` is
    /// deliberately absent — the prompt is built by hand, see `S1MiniPrompt`.
    private static let requiredFiles = [
        "config.json",
        "model.safetensors",
        "tokenizer.json",
        "tokenizer_config.json",
    ]

    private static let optionalFiles = [
        "generation_config.json",
        "model.safetensors.index.json",
    ]

    @Published private(set) var isDownloading = false
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var downloadingFile: String = ""
    @Published private(set) var lastError: String?
    /// Bumped whenever the on-disk state changes, so SwiftUI re-reads `isInstalled`.
    @Published private(set) var installedRevision = 0

    private var downloadTask: Task<Void, Never>?

    private init() {}

    // MARK: - Locations

    var baseDirectory: URL {
        let applicationSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport.appendingPathComponent(
            Bundle.main.bundleIdentifier ?? "OpenSuperWhisper"
        )
    }

    func directory(for variant: Variant) -> URL {
        baseDirectory.appendingPathComponent("s1-mini-mlx-\(variant.id)")
    }

    var selectedVariant: Variant {
        Variant.all.first { $0.id == AppPreferences.shared.s1MiniVariant } ?? .fourBit
    }

    var selectedDirectory: URL { directory(for: selectedVariant) }

    // MARK: - State

    func isInstalled(_ variant: Variant) -> Bool {
        let directory = directory(for: variant)
        return Self.requiredFiles.allSatisfy { name in
            let url = directory.appendingPathComponent(name)
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                return false
            }
            return size > 0
        }
    }

    var isSelectedInstalled: Bool { isInstalled(selectedVariant) }

    func installedBytes(_ variant: Variant) -> Int64 {
        let directory = directory(for: variant)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return contents.reduce(into: Int64(0)) { total, url in
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    // MARK: - Download

    func download(_ variant: Variant) {
        guard !isDownloading else { return }
        isDownloading = true
        downloadProgress = 0
        lastError = nil

        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.performDownload(variant)
                await MainActor.run {
                    self.isDownloading = false
                    self.downloadProgress = 1
                    self.downloadingFile = ""
                    self.installedRevision += 1
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isDownloading = false
                    self.downloadingFile = ""
                }
            } catch {
                await MainActor.run {
                    self.isDownloading = false
                    self.downloadingFile = ""
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadingFile = ""
    }

    func delete(_ variant: Variant) {
        // Unload first: deleting weights out from under a loaded model would
        // leave the formatter holding a directory that no longer exists.
        Task {
            await S1MiniFormatter.shared.unload()
            try? FileManager.default.removeItem(at: directory(for: variant))
            await MainActor.run { self.installedRevision += 1 }
        }
    }

    private func performDownload(_ variant: Variant) async throws {
        let directory = directory(for: variant)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Downloaded into a staging directory so an interrupted download never
        // leaves a half-written model that `isInstalled` would accept.
        let staging = directory.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let files = Self.requiredFiles + Self.optionalFiles
        // model.safetensors is ~97% of the bytes, so weight the progress bar by
        // size rather than by file count or it sits at 0 and then jumps to done.
        let weights: [String: Double] = [
            "model.safetensors": 0.94,
            "tokenizer.json": 0.05,
        ]
        let defaultWeight = (1.0 - weights.values.reduce(0, +))
            / Double(files.count - weights.count)

        var completed = 0.0
        for name in files {
            try Task.checkCancellation()
            let weight = weights[name] ?? defaultWeight
            await MainActor.run { self.downloadingFile = name }

            let url = URL(string: "https://huggingface.co/\(variant.repo)/resolve/main/\(name)")!
            do {
                try await downloadFile(
                    from: url,
                    to: staging.appendingPathComponent(name),
                    onProgress: { [weak self] fraction in
                        Task { @MainActor in
                            self?.downloadProgress = min(1, completed + weight * fraction)
                        }
                    }
                )
            } catch {
                // Optional files genuinely may not exist in a given repo.
                if Self.optionalFiles.contains(name) {
                    completed += weight
                    continue
                }
                throw error
            }
            completed += weight
            await MainActor.run { self.downloadProgress = min(1, completed) }
        }

        // Swap staging into place only once every required file is present.
        for name in Self.requiredFiles {
            let staged = staging.appendingPathComponent(name)
            guard let size = try? staged.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size > 0 else {
                throw S1MiniError.downloadIncomplete(name)
            }
        }
        for name in files {
            let staged = staging.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: staged.path) else { continue }
            let destination = directory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: staged, to: destination)
        }
        try? FileManager.default.removeItem(at: staging)
    }

    private func downloadFile(
        from url: URL,
        to destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        // A delegate-driven download task, not URLSession.bytes: iterating an
        // AsyncBytes sequence one byte at a time over a 335 MB file means ~335
        // million awaits, and this type is @MainActor, so it would run that
        // loop on the main thread and freeze the UI for minutes.
        let delegate = DownloadProgressDelegate(onProgress: onProgress)
        let (temporaryURL, response) = try await URLSession.shared.download(
            from: url, delegate: delegate
        )
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw S1MiniError.downloadFailed(url.lastPathComponent)
        }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        onProgress(1)
    }
}

/// Reports byte progress for one file download. `URLSession.download` gives no
/// progress on its own, and a delegate keeps the transfer off the main thread.
private final class DownloadProgressDelegate: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    // Required by the protocol; `URLSession.download(from:delegate:)` returns
    // the file itself, so nothing to do here.
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}

}

enum S1MiniError: LocalizedError {
    case notInstalled
    case downloadFailed(String)
    case downloadIncomplete(String)
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "S1-mini is not downloaded yet. Open Settings › Formatting and download it."
        case .downloadFailed(let file):
            return "Could not download \(file) from Hugging Face."
        case .downloadIncomplete(let file):
            return "The download finished without \(file); the model was not installed."
        case .loadFailed(let message):
            return "Could not load S1-mini: \(message)"
        }
    }
}
