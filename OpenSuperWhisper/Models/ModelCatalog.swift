import FluidAudio
import Foundation
import SwiftUI

enum SpeechEngine: String, CaseIterable, Identifiable {
    /// Stored as "fluidaudio" in preferences, for continuity with older builds.
    case parakeet = "fluidaudio"
    case whisper = "whisper"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .parakeet: return "Parakeet"
        case .whisper: return "Whisper"
        }
    }

    var summary: String {
        switch self {
        case .parakeet:
            return "Runs on the Apple Neural Engine. About 80 ms per dictation. English, plus 25 languages with v3 and Ultra."
        case .whisper:
            return "99 languages and translation to English. Runs on the GPU — slower, but the broadest coverage."
        }
    }

    var icon: String {
        switch self {
        case .parakeet: return "bolt"
        case .whisper: return "waveform"
        }
    }

    static var current: SpeechEngine {
        SpeechEngine(rawValue: AppPreferences.shared.selectedEngine) ?? .whisper
    }
}

/// One speech model the user can download and use. The single source of names,
/// descriptions and sizes — onboarding and Settings both read from here.
struct SpeechModel: Identifiable, Equatable {
    enum Source: Equatable {
        case parakeet(version: String)
        case whisper(url: URL)
    }

    let id: String
    let name: String
    let detail: String
    let source: Source
    /// Download size in MB, when it is known before downloading.
    let sizeMB: Int?
    let languages: String
    let speed: Int
    let accuracy: Int
    var recommended = false

    var engine: SpeechEngine {
        switch source {
        case .parakeet: return .parakeet
        case .whisper: return .whisper
        }
    }

    var whisperFileName: String? {
        if case .whisper(let url) = source { return url.lastPathComponent }
        return nil
    }

    var parakeetVersion: String? {
        if case .parakeet(let version) = source { return version }
        return nil
    }

    var sizeText: String? {
        guard let sizeMB else { return nil }
        return ModelCatalog.formatMB(Double(sizeMB))
    }
}

enum ModelCatalog {
    static let parakeet: [SpeechModel] = [
        SpeechModel(
            id: "parakeet-v2", name: "Parakeet v2",
            detail: "Recommended for English: most accurate, ~80 ms per dictation",
            source: .parakeet(version: "v2"), sizeMB: 443, languages: "English",
            speed: 5, accuracy: 5, recommended: true
        ),
        SpeechModel(
            id: "parakeet-ultra", name: "Parakeet Ultra",
            detail: "Multilingual, 25 languages, best on long recordings",
            source: .parakeet(version: "ultra"), sizeMB: nil, languages: "25 languages",
            speed: 4, accuracy: 5
        ),
        SpeechModel(
            id: "parakeet-v3", name: "Parakeet v3",
            detail: "Multilingual, 25 languages",
            source: .parakeet(version: "v3"), sizeMB: nil, languages: "25 languages",
            speed: 5, accuracy: 4
        ),
    ]

    static let whisper: [SpeechModel] = [
        SpeechModel(
            id: "whisper-large-v3-turbo", name: "Whisper Large v3 Turbo",
            detail: "High accuracy, best quality",
            source: .whisper(url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin?download=true")!),
            sizeMB: 1624, languages: "99 languages", speed: 2, accuracy: 5
        ),
        SpeechModel(
            id: "whisper-turbo-q8", name: "Whisper Turbo · 8-bit",
            detail: "Balanced speed and accuracy",
            source: .whisper(url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin?download=true")!),
            sizeMB: 874, languages: "99 languages", speed: 3, accuracy: 4
        ),
        SpeechModel(
            id: "whisper-turbo-q5", name: "Whisper Turbo · 5-bit",
            detail: "Smallest and fastest Whisper",
            source: .whisper(url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin?download=true")!),
            sizeMB: 574, languages: "99 languages", speed: 4, accuracy: 3
        ),
    ]

    /// Onboarding order: the recommended model first.
    static let all: [SpeechModel] = parakeet + whisper

    static func models(for engine: SpeechEngine) -> [SpeechModel] {
        engine == .parakeet ? parakeet : whisper
    }

    static func model(id: String) -> SpeechModel? {
        all.first { $0.id == id }
    }

    /// The model the transcription service will use right now, if it is one of
    /// the catalogue's (the bundled tiny model is not).
    static var activeModel: SpeechModel? {
        let prefs = AppPreferences.shared
        switch SpeechEngine.current {
        case .parakeet:
            return parakeet.first { $0.parakeetVersion == prefs.fluidAudioModelVersion }
        case .whisper:
            guard let path = prefs.selectedWhisperModelPath else { return nil }
            let file = URL(fileURLWithPath: path).lastPathComponent
            return whisper.first { $0.whisperFileName == file }
        }
    }

    /// Short name of what is loaded, for status lines: "Parakeet v2".
    static var activeModelName: String {
        if let activeModel { return activeModel.name }
        if SpeechEngine.current == .whisper,
           let path = AppPreferences.shared.selectedWhisperModelPath {
            let file = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            return file.replacingOccurrences(of: "ggml-", with: "Whisper ")
        }
        return SpeechEngine.current.title
    }

    static func formatMB(_ mb: Double) -> String {
        mb >= 1000 ? String(format: "%.1f GB", mb / 1000) : "\(Int(mb.rounded())) MB"
    }

    static func formatBytes(_ bytes: Int64) -> String {
        formatMB(Double(bytes) / 1_000_000)
    }
}
