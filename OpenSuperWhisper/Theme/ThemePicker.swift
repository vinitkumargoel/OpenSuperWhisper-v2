import SwiftUI

/// A selectable card for one theme: a miniature of the main window, the
/// indicator pill as it will actually look, and the theme's name.
///
/// The miniature is drawn from the same `Palette` the app uses, so it can never
/// drift from the real thing.
struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool
    /// The system scheme, so Graphite previews the appearance it would adopt.
    let systemScheme: ColorScheme
    let action: () -> Void

    @Environment(\.palette) private var chrome
    @State private var isHovered = false

    private var p: Palette { theme.palette(for: theme.effectiveScheme(system: systemScheme)) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                preview

                HStack(spacing: 6) {
                    Text(theme.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(chrome.textPrimary)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(chrome.accent)
                    }

                    Spacer(minLength: 0)
                }

                Text(theme.tagline)
                    .font(.system(size: 10.5))
                    .foregroundColor(chrome.textQuaternary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: chrome.radiusCard)
                    .fill(isSelected ? chrome.cardSelectedFill : (isHovered ? chrome.hoverFill : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: chrome.radiusCard)
                    .stroke(isSelected ? chrome.cardSelectedBorder : chrome.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(theme.displayName) theme")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// A 3-pane miniature of the main window with the pill floating over it.
    private var preview: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                // Rail
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(p.brandMarkFill)
                        .frame(width: 10, height: 10)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(p.selectionFill)
                        .frame(height: 7)
                    bar(p.textQuaternary.opacity(0.5), width: 26)
                    bar(p.textQuaternary.opacity(0.5), width: 20)
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(p.buttonFill)
                        .frame(height: 11)
                }
                .padding(6)
                .frame(width: 44)
                .frame(maxHeight: .infinity)
                .background(p.railBackground)

                Rectangle().fill(p.hairline).frame(width: 1)

                // List
                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(p.cardSelectedFill)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(p.cardSelectedBorder, lineWidth: 1))
                        .frame(height: 16)
                    bar(p.textQuaternary.opacity(0.45), width: 40)
                    bar(p.textQuaternary.opacity(0.45), width: 30)
                    Spacer(minLength: 0)
                }
                .padding(6)
                .frame(width: 56)
                .frame(maxHeight: .infinity)
                .background(p.listBackground)

                Rectangle().fill(p.hairline).frame(width: 1)

                // Detail
                VStack(alignment: .leading, spacing: 4) {
                    bar(p.textPrimary.opacity(0.75), width: 52)
                    bar(p.textPrimary.opacity(0.75), width: 44)
                    bar(p.textSecondary.opacity(0.45), width: 48)
                    Spacer(minLength: 0)
                    HStack(spacing: 2) {
                        ForEach(0..<14, id: \.self) { i in
                            Capsule().fill(p.waveform)
                                .frame(width: 1.5, height: [3, 7, 4, 9, 5, 8, 3, 6, 10, 4, 7, 3, 8, 5][i])
                        }
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(p.detailBackground)
            }
            .frame(height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(p.hairline, lineWidth: 1))

            // The pill, floating.
            HStack(spacing: 6) {
                Circle().fill(p.live).frame(width: 5, height: 5)
                Text("0:07")
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(p.pillText)
                HStack(spacing: 1.5) {
                    ForEach(0..<7, id: \.self) { i in
                        Capsule().fill(p.pillBar)
                            .frame(width: 1.5, height: [4, 7, 9, 5, 8, 4, 6][i])
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(p.pillFill)
                    .overlay(Capsule().stroke(p.pillBorder, lineWidth: 1))
                    .shadow(color: .black.opacity(p.pillShadowOpacity), radius: 5, y: 2)
            )
            .offset(y: 10)
        }
        .padding(.bottom, 10)
    }

    private func bar(_ color: Color, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: width, height: 3)
    }
}
