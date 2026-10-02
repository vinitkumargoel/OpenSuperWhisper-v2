import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case home, library, insights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        case .insights: return "Insights"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .library: return "square.grid.2x2"
        case .insights: return "chart.bar.xaxis"
        }
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case shortcuts, audio, model, transcription, formatting, modes, appearance, advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shortcuts: return "Shortcuts"
        case .audio: return "Audio"
        case .model: return "Model"
        case .transcription: return "Transcription"
        case .formatting: return "Formatting"
        case .modes: return "Modes & Vocabulary"
        case .appearance: return "Appearance"
        case .advanced: return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .shortcuts: return "keyboard"
        case .audio: return "mic.fill"
        case .model: return "cpu"
        case .transcription: return "text.bubble"
        case .formatting: return "wand.and.stars"
        case .modes: return "book.closed"
        case .appearance: return "paintpalette"
        case .advanced: return "slider.horizontal.3"
        }
    }

    var color: Color {
        switch self {
        case .shortcuts: return Color(hex: 0x5B5BF6)
        case .audio: return Color(hex: 0xFF4D5E)
        case .model: return Color(hex: 0x0E9F9A)
        case .transcription: return Color(hex: 0x3B82F6)
        case .formatting: return Color(hex: 0x8B5CF6)
        case .modes: return Color(hex: 0xEC4899)
        case .appearance: return Color(hex: 0xF97316)
        case .advanced: return Color(hex: 0x64748B)
        }
    }

    /// Words a settings search should match for this page.
    var keywords: [String] {
        switch self {
        case .shortcuts: return ["hotkey", "key", "hold", "record", "sound", "mute", "login", "launch", "delete", "retention", "indicator", "position", "esc"]
        case .audio: return ["microphone", "mic", "input", "device", "level", "bluetooth", "mute", "sound"]
        case .model: return ["engine", "parakeet", "whisper", "download", "model", "storage", "folder"]
        case .transcription: return ["language", "translate", "paste", "clipboard", "punctuation", "space", "blank", "timestamps", "prompt", "asian", "autocorrect", "folder"]
        case .formatting: return ["ai", "llm", "api", "openai", "key", "s1", "on-device", "style", "memory", "test", "format"]
        case .modes: return ["mode", "prompt", "app", "vocabulary", "replace", "word", "jargon"]
        case .appearance: return ["theme", "dark", "light", "accent", "colour", "color", "indicator", "frosted", "text size"]
        case .advanced: return ["beam", "temperature", "threshold", "debug", "decoder"]
        }
    }

    /// Sidebar grouping: a gap is drawn before these pages.
    var startsGroup: Bool { self == .model || self == .appearance }
}

/// Window-level navigation: which main tab is showing, which settings page is
/// open, and the commands that reach across windows (open Settings at a page,
/// jump to Insights from the menu bar…).
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var tab: MainTab = .home
    @Published var settingsPage: SettingsPage = .shortcuts
    /// Selected recording in the Library.
    @Published var selectedRecordingID: UUID?
    /// Bumped to ask the main window to focus its search field.
    @Published var focusSearchRequest = 0

    private init() {}

    func show(_ tab: MainTab) {
        self.tab = tab
        (NSApp.delegate as? AppDelegate)?.showMainWindow()
    }

    func openSettings(_ page: SettingsPage? = nil) {
        if let page { settingsPage = page }
        SettingsWindowController.shared.show()
    }

    func reveal(_ recordingID: UUID) {
        selectedRecordingID = recordingID
        show(.library)
    }
}

/// Human-readable form of whatever starts a recording: "Right ⌥" or "⌥ `".
@MainActor
enum HotkeyDescription {
    static var current: String {
        let modifier = ModifierKey(rawValue: AppPreferences.shared.modifierOnlyHotkey) ?? .none
        if modifier != .none { return short(modifier) }
        if let shortcut = KeyboardShortcuts.getShortcut(for: .toggleRecord) { return shortcut.description }
        return "⌥ `"
    }

    static func short(_ key: ModifierKey) -> String {
        switch key {
        case .none: return ""
        case .leftCommand: return "Left ⌘"
        case .rightCommand: return "Right ⌘"
        case .leftOption: return "Left ⌥"
        case .rightOption: return "Right ⌥"
        case .leftShift: return "Left ⇧"
        case .rightShift: return "Right ⇧"
        case .leftControl: return "Left ⌃"
        case .rightControl: return "Right ⌃"
        case .fn: return "Fn"
        }
    }

    /// "Hold Right ⌥ to dictate" / "Press ⌥ ` to dictate".
    static var instruction: String {
        AppPreferences.shared.holdToRecord ? "Hold \(current)" : "Press \(current)"
    }
}
