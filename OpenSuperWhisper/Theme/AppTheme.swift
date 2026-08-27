import AppKit
import SwiftUI

/// The three shipped looks. Obsidian is the default.
///
/// A theme owns its whole palette *and* the appearance it requires: Obsidian
/// and Signal are built on near-black and only work in dark, so they force it.
/// Graphite is the native look and follows the system.
enum AppTheme: String, CaseIterable, Identifiable {
    case obsidian
    case graphite
    case signal

    static let `default`: AppTheme = .obsidian

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .obsidian: return "Obsidian"
        case .graphite: return "Graphite"
        case .signal:   return "Signal"
        }
    }

    var tagline: String {
        switch self {
        case .obsidian: return "Monochrome. Red means the mic is live."
        case .graphite: return "Native macOS. Follows light and dark."
        case .signal:   return "Warm dark with a single amber accent."
        }
    }

    /// `nil` means "follow the system".
    var forcedColorScheme: ColorScheme? {
        switch self {
        case .obsidian, .signal: return .dark
        case .graphite:          return nil
        }
    }

    var followsSystemAppearance: Bool { forcedColorScheme == nil }

    /// The appearance to pin on `NSApp`, so AppKit-drawn chrome (title bars,
    /// menus, the indicator panel) matches the SwiftUI content.
    var nsAppearance: NSAppearance? {
        switch forcedColorScheme {
        case .dark:  return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        case .none:  return nil
        }
    }

    /// The colour scheme this theme actually renders in right now.
    func effectiveScheme(system: ColorScheme) -> ColorScheme {
        forcedColorScheme ?? system
    }

    func palette(for scheme: ColorScheme) -> Palette {
        switch self {
        case .obsidian: return Self.obsidianPalette
        case .signal:   return Self.signalPalette
        case .graphite: return scheme == .dark ? Self.graphiteDark : Self.graphiteLight
        }
    }

    // MARK: - Obsidian

    private static let obsidianPalette = Palette(
        windowBackground: Color(hex: 0x000000),
        titlebar: Color(hex: 0x08080A),
        railBackground: Color(hex: 0x0A0A0B),
        listBackground: Color(hex: 0x000000),
        detailBackground: Color(hex: 0x000000),
        groupBackground: Color(hex: 0x0D0D0F),
        hairline: .white(0.075),
        textPrimary: Color(hex: 0xF2F2F4),
        textSecondary: Color(hex: 0xC8C9CD),
        textTertiary: Color(hex: 0x9A9BA1),
        textQuaternary: Color(hex: 0x6D6E75),
        selectionFill: Color(hex: 0x1D1E21),
        selectionText: Color(hex: 0xF5F5F7),
        hoverFill: .white(0.045),
        cardSelectedFill: Color(hex: 0x161618),
        cardSelectedBorder: .white(0.10),
        accent: Color(hex: 0xF2F2F4),
        accentOn: Color(hex: 0x0A0A0B),
        brandMarkFill: Color(hex: 0x1D1E21),
        brandMarkForeground: Color(hex: 0xF2F2F4),
        buttonFill: Color(hex: 0xF4F4F6),
        buttonText: Color(hex: 0x0A0A0B),
        fieldFill: Color(hex: 0x111113),
        fieldBorder: .white(0.07),
        ghostFill: .white(0.055),
        ghostBorder: .white(0.07),
        tagFill: .white(0.07),
        tagText: Color(hex: 0xA9AAB0),
        waveform: Color(hex: 0x3C3D42),
        danger: Color(hex: 0xE0645C),
        toggleOff: Color(hex: 0x2A2B2F),
        toggleOn: Color(hex: 0xF2F2F4),
        toggleKnob: .white,
        toggleKnobOn: Color(hex: 0x0A0A0B),
        pillFill: Color(hex: 0x151517),
        pillText: Color(hex: 0xF2F2F4),
        pillBorder: .white(0.10),
        pillBar: Color(hex: 0xE9E9EC),
        pillChip: .white(0.09),
        live: Color(hex: 0xFF453A),
        radiusSmall: 7,
        radiusControl: 8,
        radiusCard: 10,
        radiusButton: 10,
        transcriptFont: .system(size: 14),
        pillShadowOpacity: 0.42
    )

    // MARK: - Graphite (light)

    private static let graphiteLight = Palette(
        windowBackground: Color(hex: 0xFFFFFF),
        titlebar: Color(hex: 0xF6F6F7),
        railBackground: Color(hex: 0xF1F1F3),
        listBackground: Color(hex: 0xFBFBFC),
        detailBackground: Color(hex: 0xFFFFFF),
        groupBackground: Color(hex: 0xFBFBFC),
        hairline: .black(0.10),
        textPrimary: Color(hex: 0x1C1C1E),
        textSecondary: Color(hex: 0x3A3A3E),
        textTertiary: Color(hex: 0x5C5C62),
        textQuaternary: Color(hex: 0x8A8A91),
        selectionFill: Color(hex: 0xE0E0E4),
        selectionText: Color(hex: 0x1C1C1E),
        hoverFill: .black(0.045),
        cardSelectedFill: Color(hex: 0xE6E6EA),
        cardSelectedBorder: .black(0.11),
        accent: Color(hex: 0x1C1C1E),
        accentOn: Color(hex: 0xFFFFFF),
        brandMarkFill: Color(hex: 0x1C1C1E),
        brandMarkForeground: Color(hex: 0xFFFFFF),
        buttonFill: Color(hex: 0x1C1C1E),
        buttonText: Color(hex: 0xFFFFFF),
        fieldFill: Color(hex: 0xFFFFFF),
        fieldBorder: .black(0.14),
        ghostFill: Color(hex: 0xF2F2F4),
        ghostBorder: .black(0.09),
        tagFill: .black(0.06),
        tagText: Color(hex: 0x5C5C62),
        waveform: Color(hex: 0xC3C3C9),
        danger: Color(hex: 0xD0342C),
        toggleOff: Color(hex: 0xD3D3D8),
        toggleOn: Color(hex: 0x1C1C1E),
        toggleKnob: .white,
        toggleKnobOn: .white,
        pillFill: Color(hex: 0x1B1B1D),
        pillText: Color(hex: 0xF4F4F6),
        pillBorder: .white(0.08),
        pillBar: Color(hex: 0xE9E9EC),
        pillChip: .white(0.10),
        live: Color(hex: 0xFF453A),
        radiusSmall: 6,
        radiusControl: 6,
        radiusCard: 8,
        radiusButton: 7,
        transcriptFont: .system(size: 14),
        pillShadowOpacity: 0.42
    )

    // MARK: - Graphite (dark)

    private static let graphiteDark = Palette(
        windowBackground: Color(hex: 0x1D1D1F),
        titlebar: Color(hex: 0x262628),
        railBackground: Color(hex: 0x252527),
        listBackground: Color(hex: 0x1D1D1F),
        detailBackground: Color(hex: 0x1D1D1F),
        groupBackground: Color(hex: 0x232325),
        hairline: .white(0.11),
        textPrimary: Color(hex: 0xF2F2F4),
        textSecondary: Color(hex: 0xC9CACE),
        textTertiary: Color(hex: 0x98999F),
        textQuaternary: Color(hex: 0x77787E),
        selectionFill: Color(hex: 0x3A3A3D),
        selectionText: Color(hex: 0xFFFFFF),
        hoverFill: .white(0.06),
        cardSelectedFill: Color(hex: 0x313134),
        cardSelectedBorder: .white(0.13),
        accent: Color(hex: 0xF2F2F4),
        accentOn: Color(hex: 0x1C1C1E),
        brandMarkFill: Color(hex: 0xF2F2F4),
        brandMarkForeground: Color(hex: 0x1C1C1E),
        buttonFill: Color(hex: 0xF2F2F4),
        buttonText: Color(hex: 0x1C1C1E),
        fieldFill: Color(hex: 0x171719),
        fieldBorder: .white(0.12),
        ghostFill: .white(0.07),
        ghostBorder: .white(0.10),
        tagFill: .white(0.08),
        tagText: Color(hex: 0xB4B5BA),
        waveform: Color(hex: 0x55565B),
        danger: Color(hex: 0xFF6961),
        toggleOff: Color(hex: 0x48484C),
        toggleOn: Color(hex: 0xF2F2F4),
        toggleKnob: .white,
        toggleKnobOn: Color(hex: 0x1C1C1E),
        pillFill: Color(hex: 0x1B1B1D),
        pillText: Color(hex: 0xF4F4F6),
        pillBorder: .white(0.08),
        pillBar: Color(hex: 0xE9E9EC),
        pillChip: .white(0.10),
        live: Color(hex: 0xFF453A),
        radiusSmall: 6,
        radiusControl: 6,
        radiusCard: 8,
        radiusButton: 7,
        transcriptFont: .system(size: 14),
        pillShadowOpacity: 0.42
    )

    // MARK: - Signal

    private static let signalPalette = Palette(
        windowBackground: Color(hex: 0x0D0E0F),
        titlebar: Color(hex: 0x0D0E0F),
        railBackground: Color(hex: 0x0D0E0F),
        listBackground: Color(hex: 0x0D0E0F),
        detailBackground: Color(hex: 0x0D0E0F),
        groupBackground: Color(hex: 0x131416),
        hairline: .white(0.075),
        textPrimary: Color(hex: 0xEDEAE3),
        textSecondary: Color(hex: 0xC4C1BA),
        textTertiary: Color(hex: 0x93918C),
        textQuaternary: Color(hex: 0x77767F),
        selectionFill: Color(hex: 0xF5C542, opacity: 0.11),
        selectionText: Color(hex: 0xF5C542),
        hoverFill: .white(0.04),
        cardSelectedFill: Color(hex: 0xF5C542, opacity: 0.08),
        cardSelectedBorder: Color(hex: 0xF5C542, opacity: 0.22),
        accent: Color(hex: 0xF5C542),
        accentOn: Color(hex: 0x191400),
        brandMarkFill: Color(hex: 0xF5C542),
        brandMarkForeground: Color(hex: 0x191400),
        buttonFill: Color(hex: 0xF5C542),
        buttonText: Color(hex: 0x191400),
        fieldFill: Color(hex: 0x141517),
        fieldBorder: .white(0.07),
        ghostFill: .white(0.05),
        ghostBorder: .white(0.07),
        tagFill: .white(0.06),
        tagText: Color(hex: 0xA3A099),
        waveform: Color(hex: 0x3D3F42),
        danger: Color(hex: 0xE0645C),
        toggleOff: Color(hex: 0x2C2D31),
        toggleOn: Color(hex: 0xF5C542),
        toggleKnob: .white,
        toggleKnobOn: Color(hex: 0x191400),
        pillFill: Color(hex: 0x141517),
        pillText: Color(hex: 0xEDEAE3),
        pillBorder: .white(0.09),
        pillBar: Color(hex: 0xEDEAE3),
        pillChip: Color(hex: 0xF5C542, opacity: 0.16),
        live: Color(hex: 0xF5C542),
        radiusSmall: 9,
        radiusControl: 9,
        radiusCard: 12,
        radiusButton: 12,
        transcriptFont: .system(size: 15, design: .serif),
        pillShadowOpacity: 0.5
    )
}
