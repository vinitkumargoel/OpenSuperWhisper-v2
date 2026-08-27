import AppKit
import Combine
import SwiftUI

/// Owns the selected theme, persists it, and keeps `NSApp`'s appearance in step.
@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var theme: AppTheme {
        didSet {
            guard theme != oldValue else { return }
            AppPreferences.shared.appTheme = theme.rawValue
            applyAppearance()
        }
    }

    /// The system's appearance, tracked so Graphite can follow it. Read from the
    /// global default rather than `NSApp.effectiveAppearance`, because Obsidian
    /// and Signal pin that to dark and would mask a system change.
    @Published private(set) var systemScheme: ColorScheme

    private init() {
        theme = AppTheme(rawValue: AppPreferences.shared.appTheme) ?? .default
        systemScheme = ThemeManager.readSystemScheme()
    }

    /// Called once at launch, after `NSApplication` exists.
    func start() {
        applyAppearance()
        DistributedNotificationCenter.default.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The default is written slightly after the notification fires.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Task { @MainActor in
                    guard let self else { return }
                    let scheme = Self.readSystemScheme()
                    if scheme != self.systemScheme { self.systemScheme = scheme }
                }
            }
        }
    }

    /// The scheme the UI is actually drawing in.
    var scheme: ColorScheme { theme.effectiveScheme(system: systemScheme) }

    var palette: Palette { theme.palette(for: scheme) }

    private func applyAppearance() {
        NSApp?.appearance = theme.nsAppearance
    }

    private static func readSystemScheme() -> ColorScheme {
        let name = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")
        return name?.lowercased().contains("dark") == true ? .dark : .light
    }
}

// MARK: - Ambient access

/// Non-observing access to the live palette, for AppKit code and for the few
/// helpers that run outside a `View` body. Inside views, prefer
/// `@Environment(\.palette)` so SwiftUI knows to redraw.
enum Theme {
    @MainActor static var current: AppTheme { ThemeManager.shared.theme }
    @MainActor static var palette: Palette { ThemeManager.shared.palette }
    @MainActor static var scheme: ColorScheme { ThemeManager.shared.scheme }
}

// MARK: - Environment

private struct PaletteKey: EnvironmentKey {
    @MainActor static var defaultValue: Palette { AppTheme.default.palette(for: .dark) }
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension View {
    /// Applies the current theme to a window's root view: injects the palette and
    /// pins the colour scheme when the theme demands one. Descendants that read
    /// `@Environment(\.palette)` redraw when the selection changes.
    func themedWindow() -> some View {
        modifier(ThemedWindow())
    }
}

private struct ThemedWindow: ViewModifier {
    @ObservedObject private var manager = ThemeManager.shared

    func body(content: Content) -> some View {
        content
            .environment(\.palette, manager.palette)
            .preferredColorScheme(manager.theme.forcedColorScheme)
            .tint(manager.palette.accent)
    }
}
