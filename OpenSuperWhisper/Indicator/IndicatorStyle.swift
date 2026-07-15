import SwiftUI

/// Selectable visual templates for the floating recording indicator.
/// Only the *look* changes (background, accent, shape) — the content
/// (dot · timer · level meter · progress) stays the same across templates.
enum IndicatorStyle: String, CaseIterable, Identifiable {
    case classic
    case glass
    case graphite
    case indigo
    case minimal
    case outline

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic:  return "Classic"
        case .glass:    return "Glass"
        case .graphite: return "Graphite"
        case .indigo:   return "Indigo"
        case .minimal:  return "Minimal"
        case .outline:  return "Outline"
        }
    }

    /// Tint for the pulsing dot and the level meter.
    var accent: Color {
        switch self {
        case .classic, .glass, .minimal: return .red
        case .graphite, .outline:        return SettingsTheme.accent
        case .indigo:                    return .white
        }
    }

    /// Foreground color for the pill's text.
    var textColor: Color {
        switch self {
        case .graphite, .indigo: return .white
        default:                 return .primary
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .minimal:            return 12
        case .graphite, .indigo:  return 18
        default:                  return 24
        }
    }

    var usesMaterial: Bool {
        switch self {
        case .graphite, .indigo, .outline: return false
        default:                           return true
        }
    }

    var strokeColor: Color? {
        switch self {
        case .glass:   return Color.white.opacity(0.18)
        case .outline: return SettingsTheme.accent.opacity(0.6)
        default:       return nil
        }
    }

    var shadowOpacity: Double {
        switch self {
        case .graphite: return 0.25
        case .indigo:   return 0.30
        case .minimal:  return 0.10
        default:        return 0.15
        }
    }

    /// The tint layer drawn over the (optional) material.
    func fillColor(_ scheme: ColorScheme) -> Color {
        switch self {
        case .classic:
            return scheme == .dark ? Color.black.opacity(0.24) : Color.white.opacity(0.24)
        case .glass:
            return Color.clear
        case .graphite:
            return Color.black.opacity(0.82)
        case .indigo:
            return SettingsTheme.accent
        case .minimal:
            return scheme == .dark ? Color.black.opacity(0.38) : Color.white.opacity(0.55)
        case .outline:
            return scheme == .dark ? Color.black.opacity(0.5) : Color.white.opacity(0.72)
        }
    }

    static var current: IndicatorStyle {
        IndicatorStyle(rawValue: AppPreferences.shared.indicatorStyle) ?? .classic
    }
}

/// A small non-animated rendering of the pill in a given style, for the
/// settings template picker.
struct IndicatorStylePreview: View {
    let style: IndicatorStyle
    var isSelected: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private let bars: [CGFloat] = [0.4, 0.7, 1.0, 0.6, 0.35]

    var body: some View {
        let rect = RoundedRectangle(cornerRadius: style.cornerRadius)
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                Circle()
                    .fill(style.accent)
                    .frame(width: 8, height: 8)
                Text("0:04")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(style.textColor)
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    ForEach(bars.indices, id: \.self) { i in
                        Capsule()
                            .fill(style.accent)
                            .frame(width: 2.5, height: 4 + 12 * bars[i])
                    }
                }
                .frame(height: 16)
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background {
                rect
                    .fill(style.fillColor(colorScheme))
                    .background { if style.usesMaterial { rect.fill(Material.thinMaterial) } }
                    .overlay { if let s = style.strokeColor { rect.stroke(s, lineWidth: 1.5) } }
                    .shadow(color: .black.opacity(style.shadowOpacity), radius: 6, x: 0, y: 3)
            }
            .clipShape(rect)

            Text(style.displayName)
                .font(.caption2)
                .foregroundColor(isSelected ? SettingsTheme.accent : .secondary)
                .fontWeight(isSelected ? .semibold : .regular)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? SettingsTheme.accent.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? SettingsTheme.accent : Color.gray.opacity(0.25), lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
    }
}
