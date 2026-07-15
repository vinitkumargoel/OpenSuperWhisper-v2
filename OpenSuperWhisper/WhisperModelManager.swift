import Combine
import Foundation

class WhisperDownloadDelegate: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate {
    private let progressCallback: (Double) -> Void
    private var expectedContentLength: Int64 = 0
    var completionHandler: ((URL?, Error?) -> Void)?
    weak var downloadTask: URLSessionDownloadTask?
    
    init(progressCallback: @escaping (Double) -> Void) {
        self.progressCallback = progressCallback
        super.init()
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // A 404/403/500 response still "finishes" the download with the error
        // page's bytes — reject anything that isn't a 2xx before accepting the file.
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let error = NSError(
                domain: "WhisperModelManager",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Model download failed: server returned HTTP \(http.statusCode)"]
            )
            completionHandler?(nil, error)
            completionHandler = nil
            return
        }
        completionHandler?(location, nil)
        completionHandler = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {

        if expectedContentLength <= 0 {
            expectedContentLength = totalBytesExpectedToWrite
        }
        // Content-Length can be missing (-1) or zero; skip ratio updates rather
        // than reporting NaN/negative progress.
        guard expectedContentLength > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(expectedContentLength)

        DispatchQueue.main.async { [weak self] in
            self?.progressCallback(progress)
        }

    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            completionHandler?(nil, error)
        } else {
        }
    }
}

class WhisperModelManager {
    static let shared = WhisperModelManager()
    
    private let modelsDirectoryName = "whisper-models"
    private var activeDownloadTasks: [String: URLSessionDownloadTask] = [:]
    private let downloadTasksLock = NSLock()
    
    var modelsDirectory: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDirectory = applicationSupport.appendingPathComponent(Bundle.main.bundleIdentifier!).appendingPathComponent(modelsDirectoryName)
        return modelsDirectory
    }
    
    private init() {
        createModelsDirectoryIfNeeded()
        copyDefaultModelIfNeeded()
    }
    
    private func createModelsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create models directory: \(error)")
        }
    }
    
    private func copyDefaultModelIfNeeded() {
        let defaultModelName = "ggml-tiny.en.bin"
        let destinationURL = modelsDirectory.appendingPathComponent(defaultModelName)
        
        // Check if model already exists
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            return
        }
        
        // Look for the model in the bundle
        if let bundleURL = Bundle.main.url(forResource: "ggml-tiny.en", withExtension: "bin") {
            do {
                try FileManager.default.copyItem(at: bundleURL, to: destinationURL)
                print("Copied default model to: \(destinationURL.path)")
            } catch {
                print("Failed to copy default model: \(error)")
            }
        }
    }

    // Call this on every startup to ensure at least one model is present
    public func ensureDefaultModelPresent() {
        let defaultModelName = "ggml-tiny.en.bin"
        let destinationURL = modelsDirectory.appendingPathComponent(defaultModelName)
        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            copyDefaultModelIfNeeded()
        }
    }
    
    func getAvailableModels() -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "bin" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            print("Failed to get available models: \(error)")
            return []
        }
    }
    
    // Download model with progress callback using delegate
    func downloadModel(url: URL, name: String, progressCallback: @escaping (Double) -> Void) async throws {
        let destinationURL = modelsDirectory.appendingPathComponent(name)
        
        // Check if model already exists (and is actually a valid model, not a
        // leftover corrupt download from before validation existed)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            if (try? Self.validateModelFile(at: destinationURL)) != nil {
                print("Model already exists at: \(destinationURL.path)")
                DispatchQueue.main.async {
                    progressCallback(1.0)
                }
                return
            }
            print("Existing model file is invalid, re-downloading: \(destinationURL.path)")
            try? FileManager.default.removeItem(at: destinationURL)
        }
        
        print("Starting model download:")
        print("- URL: \(url.absoluteString)")
        print("- Destination: \(destinationURL.path)")
        
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = WhisperDownloadDelegate(progressCallback: progressCallback)
            let configuration = URLSessionConfiguration.default
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForResource = 600 // 10 minutes timeout for large models
            
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: .main)
            print("Initiating download...")
            
            // Create a download task without completion handler
            let downloadTask = session.downloadTask(with: url)
            delegate.downloadTask = downloadTask
            
            // Store task for cancellation
            downloadTasksLock.lock()
            activeDownloadTasks[name] = downloadTask
            downloadTasksLock.unlock()
            
            // Add completion handling to delegate
            delegate.completionHandler = { [weak self] location, error in
                // Remove task from active downloads
                self?.downloadTasksLock.lock()
                self?.activeDownloadTasks.removeValue(forKey: name)
                self?.downloadTasksLock.unlock()
                
                // Check if cancelled
                if let error = error as? URLError, error.code == .cancelled {
                    print("Download cancelled")
                    continuation.resume(throwing: CancellationError())
                    return
                }
                
                if let error = error {
                    print("Download failed with error: \(error)")
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let location = location else {
                    let error = NSError(domain: "WhisperModelManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No download URL received"])
                    continuation.resume(throwing: error)
                    return
                }
                
                do {
                    print("Download completed. Moving file to destination...")
                    try FileManager.default.moveItem(at: location, to: destinationURL)

                    do {
                        try WhisperModelManager.validateModelFile(at: destinationURL)
                    } catch {
                        try? FileManager.default.removeItem(at: destinationURL)
                        throw error
                    }

                    print("Model successfully saved to: \(destinationURL.path)")

                    DispatchQueue.main.async {
                        progressCallback(1.0)
                    }

                    continuation.resume(returning: ())
                } catch {
                    print("Failed to save downloaded model: \(error)")
                    continuation.resume(throwing: error)
                }
            }
            
            downloadTask.resume()
        }
    }
    
    // Cancel download task
    func cancelDownload(name: String) {
        downloadTasksLock.lock()
        defer { downloadTasksLock.unlock() }
        
        if let task = activeDownloadTasks[name] {
            task.cancel()
            activeDownloadTasks.removeValue(forKey: name)
            print("Cancelled download for: \(name)")
        }
    }
    
    // Check if specific model is downloaded
    func isModelDownloaded(name: String) -> Bool {
        let modelPath = modelsDirectory.appendingPathComponent(name).path
        return FileManager.default.fileExists(atPath: modelPath)
    }

    /// Rejects files that are not GGML whisper models (e.g. an HTML error page
    /// saved by a failed download): checks the GGML magic ("ggml", 0x67676d6c
    /// little-endian) and a sane minimum size.
    static func validateModelFile(at url: URL) throws {
        let minimumModelSize: Int64 = 1_000_000

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? Int64) ?? 0

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let magicData = try handle.read(upToCount: 4) ?? Data()

        let ggmlMagic: UInt32 = 0x67676d6c
        let magic: UInt32 = magicData.count == 4
            ? magicData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            : 0

        guard magic == ggmlMagic, fileSize >= minimumModelSize else {
            throw NSError(
                domain: "WhisperModelManager",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Downloaded file is not a valid Whisper model (corrupt download or server error page). Please try again."]
            )
        }
    }
}
