import Foundation
import AVFoundation

protocol TranscriptionEngine: AnyObject {
    var isModelLoaded: Bool { get }
    var engineName: String { get }
    
    func initialize() async throws
    /// Releases the model weights. The engine must be usable again after a
    /// subsequent `initialize()`.
    func unload()
    func transcribeAudio(url: URL, settings: Settings) async throws -> String
    func cancelTranscription()
    func getSupportedLanguages() -> [String]
}

