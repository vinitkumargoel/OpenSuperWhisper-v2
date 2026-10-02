import AppKit
import Combine
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case light, dark, auto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .auto: return "Auto"
        }
    }

    var subtitle: String {
        switch self {
        case .light: return "Bright and airy. The default."
        case .dark: return "Soft charcoal, never pure black."
        case .auto: return "Follows your macOS setting."
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .auto: return nil
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .auto: return nil
        }
    }
}

enum IndicatorStyle: String, CaseIterable, Identifiable {
    case frosted, solid
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum TranscriptTextSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var pointSize: CGFloat {
        switch self {
        case .small: return 13.5
        case .medium: return 15
        case .large: return 17
        }
    }
}

/// Owns Daylight's appearance choices, persists them and keeps `NSApp`'s
/// appearance in step.
@MainActor
final class AppearanceManager: ObservableObject {
    static let shared = AppearanceManager()

    @Published var mode: AppearanceMode {
        didSet {
            AppPreferences.shared.appearanceMode = mode.rawValue
            applyAppearance()
        }
    }

    @Published var accent: DLAccent {
        didSet { AppPreferences.shared.accentColor = accent.rawValue }
    }

    @Published var indicatorStyle: IndicatorStyle {
        didSet { AppPreferences.shared.indicatorStyle = indicatorStyle.rawValue }
    }

    @Published var transcriptSize: TranscriptTextSize {
        didSet { AppPreferences.shared.transcriptTextSize = transcriptSize.rawValue }
    }

    private init() {
        let prefs = AppPreferences.shared
        Self.migrateLegacyThemeIfNeeded(prefs)
        mode = AppearanceMode(rawValue: prefs.appearanceMode ?? "") ?? .light
        accent = DLAccent(rawValue: prefs.accentColor) ?? .indigo
        indicatorStyle = IndicatorStyle(rawValue: prefs.indicatorStyle) ?? .frosted
        transcriptSize = TranscriptTextSize(rawValue: prefs.transcriptTextSize) ?? .medium
    }

    /// Called once at launch, after `NSApplication` exists.
    func start() {
        DLFonts.register()
        applyAppearance()
    }

    private func applyAppearance() {
        NSApp?.appearance = mode.nsAppearance
    }

    /// Daylight starts light for everyone — moving away from the dark-only
    /// themes is the point of the redesign. What carries over is the accent:
    /// Graphite keeps its graphite accent and follows the system, Signal keeps
    /// its amber.
    private static func migrateLegacyThemeIfNeeded(_ prefs: AppPreferences) {
        guard prefs.appearanceMode == nil else { return }
        switch prefs.legacyAppTheme {
        case "graphite":
            prefs.appearanceMode = AppearanceMode.auto.rawValue
            prefs.accentColor = DLAccent.graphite.rawValue
        case "signal":
            prefs.appearanceMode = AppearanceMode.light.rawValue
            prefs.accentColor = DLAccent.amber.rawValue
        default:
            prefs.appearanceMode = AppearanceMode.light.rawValue
        }
    }
}
