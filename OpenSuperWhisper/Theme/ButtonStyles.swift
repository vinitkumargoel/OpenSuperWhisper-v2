import SwiftUI

/// The app's one filled button: the record button, "Copy text", "Grant Access".
/// There is deliberately no second filled style — if two buttons in a view both
/// want to be filled, one of them is wrong.
struct FilledButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    var height: CGFloat = 28
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(palette.buttonText)
            .padding(.horizontal, 13)
            .frame(height: height)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: palette.radiusButton)
                    .fill(palette.buttonFill)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .contentShape(Rectangle())
    }
}

/// Bordered secondary button — "Re-format", "Play", anything that isn't the one
/// primary action in view.
struct GhostButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    var height: CGFloat = 28
    /// Destructive actions borrow the danger colour for their label only; they
    /// never become a filled red button.
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(isDestructive ? palette.danger : palette.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: palette.radiusControl)
                    .fill(isDestructive ? Color.clear : palette.ghostFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: palette.radiusControl)
                    .stroke(isDestructive ? Color.clear : palette.ghostBorder, lineWidth: 1)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(Rectangle())
    }
}

/// A square icon button, as used in the transcript header.
struct IconButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    var size: CGFloat = 27
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5))
            .foregroundColor(isActive ? palette.textPrimary : palette.textTertiary)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: palette.radiusSmall)
                    .fill(palette.ghostFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: palette.radiusSmall)
                    .stroke(palette.ghostBorder, lineWidth: 1)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(Rectangle())
    }
}
