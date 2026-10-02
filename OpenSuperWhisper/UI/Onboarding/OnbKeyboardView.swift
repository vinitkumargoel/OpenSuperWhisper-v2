import SwiftUI

/// A Mac keyboard drawn from the user's own layout, with the keys of the
/// chosen dictation shortcut lit in the accent.
struct OnbKeyboardView: View {
    let selectedShortcut: OnboardingShortcutOption
    var width: CGFloat = 700

    @State private var labels: [UInt16: String] = OnbKeyboardView.resolveLabels()

    private let gap: CGFloat = 5
    private let pad: CGFloat = 12
    private let refUnits: CGFloat = 14.5
    private let refGaps: CGFloat = 13

    private static let row0: [UInt16] = [50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24]
    private static let row1: [UInt16] = [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30]
    private static let row2: [UInt16] = [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39]
    private static let row3: [UInt16] = [6, 7, 8, 9, 11, 45, 46, 43, 47, 44]

    /// US labels for layouts the provider cannot resolve (ISO/JIS).
    private static let usLabels: [UInt16: String] = [
        50: "`", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0", 27: "-", 24: "=",
        12: "Q", 13: "W", 14: "E", 15: "R", 17: "T", 16: "Y", 32: "U", 34: "I", 31: "O", 35: "P", 33: "[", 30: "]", 42: "\\",
        0: "A", 1: "S", 2: "D", 3: "F", 5: "G", 4: "H", 38: "J", 40: "K", 37: "L", 41: ";", 39: "'",
        6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 45: "N", 46: "M", 43: ",", 47: ".", 44: "/",
    ]

    private static func resolveLabels() -> [UInt16: String] {
        KeyboardLayoutProvider.shared.resolveInfo()?.labels ?? usLabels
    }

    private var u: CGFloat { (width - pad * 2 - gap * refGaps) / refUnits }
    private var rowWidth: CGFloat { refUnits * u + refGaps * gap }

    private func wide(single: Int, wideCount: Int) -> CGFloat {
        (rowWidth - CGFloat(single) * u - CGFloat(single + wideCount - 1) * gap) / CGFloat(wideCount)
    }

    private func lit(_ id: String) -> Bool {
        switch selectedShortcut {
        case .keyCombination: return id == "leftOption" || id == "tilde"
        case .rightOption: return id == "rightOption"
        }
    }

    private func key(_ label: String, _ w: CGFloat, _ h: CGFloat? = nil, lit: Bool = false) -> some View {
        OnbKey(label: label, width: w, height: h ?? u, lit: lit)
    }

    var body: some View {
        let backspace = rowWidth - 13 * u - 13 * gap
        let caps = wide(single: 11, wideCount: 2)
        let shift = wide(single: 10, wideCount: 2)
        let cmd = u * 1.25
        let space = rowWidth - 7 * u - cmd * 2 - 10 * gap

        VStack(spacing: gap) {
            HStack(spacing: gap) {
                key(labels[50] ?? "`", u, lit: lit("tilde"))
                ForEach(Array(Self.row0.dropFirst()), id: \.self) { key(labels[$0] ?? "", u) }
                key("⌫", backspace)
            }
            HStack(spacing: gap) {
                key("⇥", backspace)
                ForEach(Self.row1, id: \.self) { key(labels[$0] ?? "", u) }
                key(labels[42] ?? "\\", u)
            }
            HStack(spacing: gap) {
                key("⇪", caps)
                ForEach(Self.row2, id: \.self) { key(labels[$0] ?? "", u) }
                key("⏎", caps)
            }
            HStack(spacing: gap) {
                key("⇧", shift)
                ForEach(Self.row3, id: \.self) { key(labels[$0] ?? "", u) }
                key("⇧", shift)
            }
            HStack(spacing: gap) {
                key("fn", u)
                key("⌃", u)
                key("⌥", u, lit: lit("leftOption"))
                key("⌘", cmd)
                key("", space)
                key("⌘", cmd)
                key("⌥", u, lit: lit("rightOption"))
                key("←", u)
                VStack(spacing: 2) {
                    key("↑", u, u / 2 - 1)
                    key("↓", u, u / 2 - 1)
                }
                key("→", u)
            }
        }
        .padding(pad)
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DL.well))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(DL.line2, lineWidth: 1))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedShortcut)
    }

    /// Horizontal centre (from the leading edge) of the lit key, for the caption.
    static func highlightCenterX(for option: OnboardingShortcutOption, width: CGFloat) -> CGFloat {
        let gap: CGFloat = 5, pad: CGFloat = 12
        let u = (width - pad * 2 - gap * 13) / 14.5
        let cmd = u * 1.25
        let rowWidth = 14.5 * u + 13 * gap
        let space = rowWidth - 7 * u - cmd * 2 - 10 * gap
        switch option {
        case .rightOption:
            return pad + 3 * u + 3 * gap + cmd + gap + space + gap + cmd + gap + u / 2
        case .keyCombination:
            return pad + 2 * u + 2 * gap + u / 2
        }
    }
}

private struct OnbKey: View {
    let label: String
    let width: CGFloat
    let height: CGFloat
    let lit: Bool
    @Environment(\.dlAccent) private var accent

    var body: some View {
        Text(label)
            .font(.system(size: height > 30 ? 11.5 : 9, weight: .medium))
            .foregroundStyle(lit ? Color.white : DL.sub)
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(lit ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(DL.card))
                    .shadow(color: lit ? accent.color.opacity(0.35) : .black.opacity(0.08), radius: lit ? 6 : 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(lit ? Color.clear : DL.line, lineWidth: 1)
            )
            .scaleEffect(lit ? 1.04 : 1)
    }
}
