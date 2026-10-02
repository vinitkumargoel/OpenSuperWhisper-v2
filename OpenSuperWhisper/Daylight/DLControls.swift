import SwiftUI

// MARK: - Buttons

enum DLButtonKind {
    /// Accent gradient with white text. One per surface.
    case primary
    /// White card with a hairline border.
    case secondary
    /// No chrome until hovered.
    case ghost
    /// Pale red fill with red text, for delete and reset.
    case dangerSoft
    /// Solid red, the confirm button inside a destructive dialog.
    case danger
}

struct DLButtonStyle: ButtonStyle {
    var kind: DLButtonKind = .secondary
    var size: ControlSize = .regular
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        DLButtonBody(configuration: configuration, kind: kind, size: size, fullWidth: fullWidth)
    }
}

private struct DLButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: DLButtonKind
    let size: ControlSize
    let fullWidth: Bool
    @Environment(\.dlAccent) private var accent
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    private var height: CGFloat {
        switch size {
        case .mini: return 22
        case .small: return 26
        case .large, .extraLarge: return 40
        default: return 30
        }
    }

    private var fontSize: CGFloat {
        switch size {
        case .mini: return 11
        case .small: return 12
        case .large, .extraLarge: return 14.5
        default: return 13
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .mini: return 8
        case .small: return 10
        case .large, .extraLarge: return 20
        default: return 12
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size == .large ? 12 : DL.radiusSmall, style: .continuous)
        configuration.label
            .font(.system(size: fontSize, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .foregroundStyle(foreground)
            .background { background(shape) }
            .overlay {
                if kind == .secondary {
                    shape.strokeBorder(DL.line, lineWidth: 1)
                }
            }
            .shadow(color: kind == .primary && isEnabled ? accent.color.opacity(0.28) : .clear, radius: 8, y: 3)
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }

    private var foreground: Color {
        switch kind {
        case .primary, .danger: return .white
        case .secondary, .ghost: return DL.ink
        case .dangerSoft: return DL.live
        }
    }

    @ViewBuilder
    private func background(_ shape: RoundedRectangle) -> some View {
        switch kind {
        case .primary:
            shape.fill(accent.gradient).brightness(hovering && isEnabled ? 0.04 : 0)
        case .secondary:
            shape.fill(hovering && isEnabled ? DL.well : DL.card)
        case .ghost:
            shape.fill(hovering && isEnabled ? DL.well : .clear)
        case .dangerSoft:
            shape.fill(DL.liveSoft.opacity(hovering ? 1 : 0.85))
        case .danger:
            shape.fill(DL.live).brightness(hovering ? 0.04 : 0)
        }
    }
}

extension ButtonStyle where Self == DLButtonStyle {
    static var dlPrimary: DLButtonStyle { DLButtonStyle(kind: .primary) }
    static var dlSecondary: DLButtonStyle { DLButtonStyle(kind: .secondary) }
    static var dlGhost: DLButtonStyle { DLButtonStyle(kind: .ghost) }
    static var dlDangerSoft: DLButtonStyle { DLButtonStyle(kind: .dangerSoft) }
    static var dlDanger: DLButtonStyle { DLButtonStyle(kind: .danger) }

    static func dl(_ kind: DLButtonKind, size: ControlSize = .regular, fullWidth: Bool = false) -> DLButtonStyle {
        DLButtonStyle(kind: kind, size: size, fullWidth: fullWidth)
    }
}

/// Square bordered icon button, e.g. the toolbar gear.
struct DLIconButtonStyle: ButtonStyle {
    var size: CGFloat = 30
    var bordered = true
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        DLIconButtonBody(configuration: configuration, size: size, bordered: bordered, tint: tint)
    }
}

private struct DLIconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let size: CGFloat
    let bordered: Bool
    let tint: Color?
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DL.radiusSmall, style: .continuous)
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint ?? DL.sub)
            .frame(width: size, height: size)
            .background(shape.fill(hovering ? DL.well : (bordered ? DL.card : .clear)))
            .overlay { if bordered { shape.strokeBorder(DL.line, lineWidth: 1) } }
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .onHover { hovering = $0 }
    }
}

extension ButtonStyle where Self == DLIconButtonStyle {
    static var dlIcon: DLIconButtonStyle { DLIconButtonStyle() }
    static func dlIcon(size: CGFloat = 30, bordered: Bool = true, tint: Color? = nil) -> DLIconButtonStyle {
        DLIconButtonStyle(size: size, bordered: bordered, tint: tint)
    }
}

/// Plain label that highlights on hover — for list rows and menu-like buttons.
struct DLRowButtonStyle: ButtonStyle {
    var selected = false
    var radius: CGFloat = DL.radiusSmall

    func makeBody(configuration: Configuration) -> some View {
        DLRowButtonBody(configuration: configuration, selected: selected, radius: radius)
    }
}

private struct DLRowButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    let radius: CGFloat
    @State private var hovering = false
    @Environment(\.dlAccent) private var accent

    var body: some View {
        configuration.label
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(selected ? accent.soft : (hovering ? DL.well : .clear))
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .onHover { hovering = $0 }
    }
}

// MARK: - Toggle

struct DLToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        DLToggleBody(configuration: configuration)
    }
}

private struct DLToggleBody: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.dlAccent) private var accent
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 8) {
            configuration.label
            Capsule()
                .fill(configuration.isOn ? AnyShapeStyle(accent.color) : AnyShapeStyle(DL.line))
                .frame(width: 38, height: 22)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                        .padding(2.5)
                }
                .opacity(isEnabled ? 1 : 0.45)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isOn)
                .onTapGesture { if isEnabled { configuration.isOn.toggle() } }
                .accessibilityAddTraits(.isButton)
        }
    }
}

extension ToggleStyle where Self == DLToggleStyle {
    static var dl: DLToggleStyle { DLToggleStyle() }
}

/// A switch with no label, the common case in settings rows.
struct DLSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.dl)
    }
}

// MARK: - Segmented control

/// Pill segmented control: a grey well with the selected option raised on a
/// white chip.
struct DLSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    var size: ControlSize = .regular
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = option.value == selection
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.system(size: size == .small ? 11.5 : 12.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? DL.ink : DL.sub)
                        .lineLimit(1)
                        .padding(.horizontal, size == .small ? 9 : 11)
                        .frame(height: size == .small ? 22 : 26)
                        .frame(maxWidth: fullWidth ? .infinity : nil)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(DL.raised)
                                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DL.well))
        .opacity(isEnabled ? 1 : 0.5)
        .fixedSize(horizontal: !fullWidth, vertical: true)
    }
}

// MARK: - Fields

struct DLFieldStyle: ViewModifier {
    var mono = false
    var focused = false
    @Environment(\.dlAccent) private var accent

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(mono ? DL.mono(12.5, .regular) : DL.text(13))
            .foregroundStyle(DL.ink)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: DL.radiusSmall, style: .continuous).fill(DL.field))
            .overlay(
                RoundedRectangle(cornerRadius: DL.radiusSmall, style: .continuous)
                    .strokeBorder(focused ? accent.color : DL.line, lineWidth: focused ? 1.5 : 1)
            )
    }
}

extension View {
    func dlField(mono: Bool = false, focused: Bool = false) -> some View {
        modifier(DLFieldStyle(mono: mono, focused: focused))
    }
}

/// A text field that draws the accent ring while focused.
struct DLTextField: View {
    let placeholder: String
    @Binding var text: String
    var mono = false
    var secure = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .focused($focused)
        .dlField(mono: mono, focused: focused)
    }
}

/// Multi-line editor in a field frame.
struct DLTextEditor: View {
    @Binding var text: String
    var mono = false
    var minHeight: CGFloat = 70
    @FocusState private var focused: Bool
    @Environment(\.dlAccent) private var accent

    var body: some View {
        TextEditor(text: $text)
            .focused($focused)
            .font(mono ? DL.mono(12.5, .regular) : DL.text(13))
            .foregroundStyle(DL.ink)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(minHeight: minHeight)
            .background(RoundedRectangle(cornerRadius: DL.radiusControl, style: .continuous).fill(DL.field))
            .overlay(
                RoundedRectangle(cornerRadius: DL.radiusControl, style: .continuous)
                    .strokeBorder(focused ? accent.color : DL.line, lineWidth: focused ? 1.5 : 1)
            )
    }
}

// MARK: - Menu picker

/// A dropdown that looks like a Daylight field: value on the left, chevron on
/// the right. `items` may contain `nil` to draw a divider.
struct DLMenuPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let items: [(value: Value, label: String)?]
    var width: CGFloat? = 160
    var icon: String? = nil

    private var currentLabel: String {
        items.compactMap { $0 }.first(where: { $0.value == selection })?.label ?? "—"
    }

    var body: some View {
        Menu {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                if let item {
                    Button {
                        selection = item.value
                    } label: {
                        if item.value == selection {
                            Label(item.label, systemImage: "checkmark")
                        } else {
                            Text(item.label)
                        }
                    }
                } else {
                    Divider()
                }
            }
        } label: {
            DLMenuLabel(text: currentLabel, icon: icon, width: width)
        }
        .menuStyle(.button).buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// The visual of a dropdown field, reusable for custom `Menu`s.
struct DLMenuLabel: View {
    let text: String
    var icon: String? = nil
    var width: CGFloat? = 160

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon).font(.system(size: 11.5)).foregroundStyle(DL.sub)
            }
            Text(text)
                .font(DL.text(13))
                .foregroundStyle(DL.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DL.faint)
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: 30)
        .background(RoundedRectangle(cornerRadius: DL.radiusSmall, style: .continuous).fill(DL.field))
        .overlay(RoundedRectangle(cornerRadius: DL.radiusSmall, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

// MARK: - Stepper

struct DLStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 0) {
            Button { value = max(range.lowerBound, value - 1) } label: {
                Image(systemName: "minus").frame(width: 28, height: 28)
            }
            .disabled(value <= range.lowerBound)
            Rectangle().fill(DL.line).frame(width: 1, height: 16)
            Text("\(value)")
                .font(DL.mono(13, .semibold))
                .foregroundStyle(DL.ink)
                .frame(width: 34)
            Rectangle().fill(DL.line).frame(width: 1, height: 16)
            Button { value = min(range.upperBound, value + 1) } label: {
                Image(systemName: "plus").frame(width: 28, height: 28)
            }
            .disabled(value >= range.upperBound)
        }
        .buttonStyle(.plain)
        .font(.system(size: 10.5, weight: .bold))
        .foregroundStyle(DL.sub)
        .background(RoundedRectangle(cornerRadius: DL.radiusSmall).fill(DL.field))
        .overlay(RoundedRectangle(cornerRadius: DL.radiusSmall).strokeBorder(DL.line, lineWidth: 1))
    }
}

// MARK: - Slider

/// Slider with a numeric readout and min/mid/max ticks.
struct DLSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var step: Double = 0.1
    var width: CGFloat = 220

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 2) {
                Slider(value: $value, in: range, step: step)
                    .controlSize(.small)
                    .frame(width: width)
                HStack {
                    Text(String(format: "%.1f", range.lowerBound))
                    Spacer()
                    Text(String(format: "%.1f", (range.lowerBound + range.upperBound) / 2))
                    Spacer()
                    Text(String(format: "%.1f", range.upperBound))
                }
                .font(DL.mono(9.5, .regular))
                .foregroundStyle(DL.faint)
                .frame(width: width)
            }
            Text(String(format: "%.2f", value))
                .font(DL.mono(13, .semibold))
                .foregroundStyle(DL.ink)
                .frame(width: 40, alignment: .trailing)
                .padding(.top, 1)
        }
    }
}

// MARK: - Search field

struct DLSearchField: View {
    let placeholder: String
    @Binding var text: String
    var shortcutHint: String? = nil
    var width: CGFloat? = nil
    var focus: FocusState<Bool>.Binding? = nil
    @FocusState private var ownFocus: Bool
    @Environment(\.dlAccent) private var accent

    private var isFocused: Bool { focus?.wrappedValue ?? ownFocus }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DL.faint)
            field
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(DL.faint)
                }
                .buttonStyle(.plain)
            } else if let shortcutHint {
                Text(shortcutHint)
                    .font(DL.mono(10, .semibold))
                    .foregroundStyle(DL.faint)
                    .padding(.horizontal, 5)
                    .frame(height: 18)
                    .background(RoundedRectangle(cornerRadius: 5).fill(DL.well))
            }
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: 32)
        .background(RoundedRectangle(cornerRadius: DL.radiusControl, style: .continuous).fill(DL.field))
        .overlay(
            RoundedRectangle(cornerRadius: DL.radiusControl, style: .continuous)
                .strokeBorder(isFocused ? accent.color : DL.line, lineWidth: isFocused ? 1.5 : 1)
        )
    }

    @ViewBuilder
    private var field: some View {
        let base = TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(DL.text(13))
            .foregroundStyle(DL.ink)
        if let focus {
            base.focused(focus)
        } else {
            base.focused($ownFocus)
        }
    }
}

// MARK: - Checkbox

struct DLCheckbox: View {
    @Binding var isOn: Bool
    @Environment(\.dlAccent) private var accent

    var body: some View {
        Button { isOn.toggle() } label: {
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .fill(isOn ? AnyShapeStyle(accent.color) : AnyShapeStyle(DL.field))
                .overlay(
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .strokeBorder(isOn ? Color.clear : DL.line, lineWidth: 1.2)
                )
                .overlay {
                    if isOn {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
    }
}

/// Selection radio used in option lists.
struct DLRadio: View {
    let isOn: Bool
    @Environment(\.dlAccent) private var accent

    var body: some View {
        ZStack {
            Circle().strokeBorder(isOn ? accent.color : DL.line, lineWidth: 1.5)
            if isOn { Circle().fill(accent.color).padding(4) }
        }
        .frame(width: 18, height: 18)
    }
}
