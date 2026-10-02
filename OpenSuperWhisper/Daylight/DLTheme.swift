import AppKit
import CoreText
import SwiftUI

// MARK: - Colour helpers

extension NSColor {
    /// `NSColor(hex: 0x151826)` — opaque sRGB from a 24-bit hex literal.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// A colour that resolves to `light` or `dark` with the drawing appearance.
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hex: dark) : NSColor(hex: light)
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(nsColor: NSColor(hex: hex, alpha: opacity))
    }

    fileprivate static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: .dynamic(light, dark))
    }
}

// MARK: - Tokens

/// Daylight's design tokens. Surfaces and text follow the window's light/dark
/// appearance on their own; the accent comes from `\.dlAccent` because the user
/// picks it.
enum DL {
    // Surfaces, back to front.
    static let background = Color.dynamic(0xF3F5F9, 0x15161C)
    static let window = Color.dynamic(0xF6F7FB, 0x1A1B22)
    static let card = Color.dynamic(0xFFFFFF, 0x22232C)
    static let raised = Color.dynamic(0xFFFFFF, 0x2A2B35)
    static let field = Color.dynamic(0xFFFFFF, 0x1C1D24)
    static let sidebar = Color.dynamic(0xEEF0F6, 0x1C1D24)
    static let well = Color.dynamic(0xEEF0F5, 0x2A2B35)

    // Text ramp.
    static let ink = Color.dynamic(0x151826, 0xECEDF3)
    static let ink2 = Color.dynamic(0x2A2F45, 0xD3D5DF)
    static let sub = Color.dynamic(0x5B6275, 0xA3A7B7)
    static let faint = Color.dynamic(0x8E94A6, 0x737889)

    // Lines.
    static let line = Color.dynamic(0xE3E6EE, 0x30323D)
    static let line2 = Color.dynamic(0xECEEF4, 0x292A34)

    // Meaningful colours. Live is the microphone and nothing else.
    static let live = Color.dynamic(0xFF4D5E, 0xFF5E6D)
    static let liveSoft = Color.dynamic(0xFFEDEF, 0x3B2026)
    static let ok = Color.dynamic(0x13A26B, 0x34C38A)
    static let okSoft = Color.dynamic(0xE3F6EE, 0x17332A)
    static let warn = Color.dynamic(0xD9820B, 0xF0A33A)
    static let warnSoft = Color.dynamic(0xFFF4E0, 0x3A2D15)
    static let star = Color(hex: 0xF5A524)

    static let shadow = Color.black.opacity(0.06)

    // Radii.
    static let radiusSmall: CGFloat = 8
    static let radiusControl: CGFloat = 10
    static let radiusCard: CGFloat = 16
    static let radiusHero: CGFloat = 22

    // Type. Manrope for display, SF for body, SF Mono for numbers that line up.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        DLFonts.isManropeAvailable
            ? .custom("Manrope", size: size).weight(weight)
            : .system(size: size, weight: weight, design: .rounded)
    }

    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Accent

/// The user-selectable accent. Each is a two-stop gradient; `color` is the
/// first stop and is what flat accents (toggles, selection) use.
enum DLAccent: String, CaseIterable, Identifiable {
    case indigo, coral, teal, amber, rose, graphite

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    private var stops: (UInt32, UInt32) {
        switch self {
        case .indigo: return (0x5B5BF6, 0x8B5CF6)
        case .coral: return (0xF0565F, 0xFF8A65)
        case .teal: return (0x0E9F9A, 0x14B8A6)
        case .amber: return (0xE38A00, 0xF5B83D)
        case .rose: return (0xE0458F, 0xF472B6)
        case .graphite: return (0x3F4656, 0x6B7280)
        }
    }

    var color: Color { Color(hex: stops.0) }
    var color2: Color { Color(hex: stops.1) }

    var gradient: LinearGradient {
        LinearGradient(colors: [color, color2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Pale tint for selected rows, badges and icon wells.
    var soft: Color { color.opacity(0.12) }
    var softer: Color { color.opacity(0.06) }
}

private struct DLAccentKey: EnvironmentKey {
    static let defaultValue: DLAccent = .indigo
}

private struct DLTranscriptSizeKey: EnvironmentKey {
    static let defaultValue: CGFloat = 15
}

extension EnvironmentValues {
    var dlAccent: DLAccent {
        get { self[DLAccentKey.self] }
        set { self[DLAccentKey.self] = newValue }
    }

    /// Point size for transcript reading text, from Settings › Appearance.
    var dlTranscriptSize: CGFloat {
        get { self[DLTranscriptSizeKey.self] }
        set { self[DLTranscriptSizeKey.self] = newValue }
    }
}

// MARK: - Fonts

enum DLFonts {
    private(set) static var isManropeAvailable = false

    /// Registers the bundled Manrope variable font for this process. Safe to
    /// call more than once.
    static func register() {
        guard !isManropeAvailable else { return }
        guard let url = Bundle.main.url(forResource: "Manrope", withExtension: "ttf") else { return }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            isManropeAvailable = true
        } else {
            // Already registered by an earlier call counts as available.
            isManropeAvailable = NSFont(name: "Manrope", size: 12) != nil
        }
    }
}

// MARK: - Window root

extension View {
    /// Applies Daylight to a window's root view: accent, transcript size and the
    /// forced colour scheme when the user picked Light or Dark.
    func daylight() -> some View {
        modifier(DaylightRoot())
    }
}

private struct DaylightRoot: ViewModifier {
    @ObservedObject private var appearance = AppearanceManager.shared

    func body(content: Content) -> some View {
        content
            .environment(\.dlAccent, appearance.accent)
            .environment(\.dlTranscriptSize, appearance.transcriptSize.pointSize)
            .preferredColorScheme(appearance.mode.colorScheme)
            .tint(appearance.accent.color)
    }
}
