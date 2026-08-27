import SwiftUI

// MARK: - Color helpers

extension Color {
    /// `Color(hex: 0x1D1E21)` — opaque sRGB from a 24-bit hex literal.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    static func white(_ opacity: Double) -> Color { Color.white.opacity(opacity) }
    static func black(_ opacity: Double) -> Color { Color.black.opacity(opacity) }
}

// MARK: - Palette

/// Every colour, radius and font the UI is allowed to use.
///
/// Views never reach for `Color.blue` or a hard-coded `Color(red:green:blue:)`;
/// they read a semantic token from here. That is what makes three themes
/// possible without touching a single view, and what keeps the palette honest —
/// if a token doesn't exist, the colour doesn't belong in the app.
struct Palette {
    // Surfaces, back to front.
    let windowBackground: Color
    let titlebar: Color
    let railBackground: Color
    let listBackground: Color
    let detailBackground: Color
    /// Fill for grouped-row containers in Settings.
    let groupBackground: Color

    /// The only divider colour. One hairline, everywhere.
    let hairline: Color

    // Text ramp, most to least prominent.
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let textQuaternary: Color

    // Selection & hover.
    let selectionFill: Color
    let selectionText: Color
    let hoverFill: Color
    let cardSelectedFill: Color
    let cardSelectedBorder: Color

    /// The theme's one accent. In Obsidian and Graphite this is deliberately
    /// achromatic — it is an *emphasis*, not a brand colour.
    let accent: Color
    /// Legible foreground when drawn on top of `accent`.
    let accentOn: Color

    let brandMarkFill: Color
    let brandMarkForeground: Color

    /// Filled ("primary") buttons — the record button, Copy text.
    let buttonFill: Color
    let buttonText: Color

    // Text fields, popup buttons.
    let fieldFill: Color
    let fieldBorder: Color

    // Secondary / bordered buttons and chips.
    let ghostFill: Color
    let ghostBorder: Color

    let tagFill: Color
    let tagText: Color

    let waveform: Color
    /// Destructive actions and error text. Never used for anything else.
    let danger: Color

    let toggleOff: Color
    let toggleOn: Color
    let toggleKnob: Color
    let toggleKnobOn: Color

    // Floating indicator pill. It sits over other people's windows, so it
    // carries its own values rather than inheriting the window surfaces.
    let pillFill: Color
    let pillText: Color
    let pillBorder: Color
    let pillBar: Color
    let pillChip: Color
    /// Shown only while the microphone is live. This is the one colour in the
    /// app that means exactly one thing.
    let live: Color

    // Corner radii.
    let radiusSmall: CGFloat
    let radiusControl: CGFloat
    let radiusCard: CGFloat
    let radiusButton: CGFloat

    /// Point size and design for transcript body text. Signal reads better in a
    /// serif; the others stay in the system face.
    let transcriptFont: Font
    let pillShadowOpacity: Double
}
