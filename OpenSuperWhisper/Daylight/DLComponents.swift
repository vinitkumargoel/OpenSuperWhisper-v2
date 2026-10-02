import SwiftUI

// MARK: - Cards & groups

struct DLCardModifier: ViewModifier {
    var radius: CGFloat = DL.radiusCard
    var padding: CGFloat? = nil
    var selected = false
    @Environment(\.dlAccent) private var accent

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding ?? 0)
            .background(shape.fill(DL.card))
            .overlay(shape.strokeBorder(selected ? accent.color : DL.line2, lineWidth: selected ? 2 : 1))
            .shadow(color: selected ? accent.color.opacity(0.14) : DL.shadow, radius: selected ? 10 : 6, y: 2)
    }
}

extension View {
    func dlCard(radius: CGFloat = DL.radiusCard, padding: CGFloat? = nil, selected: Bool = false) -> some View {
        modifier(DLCardModifier(radius: radius, padding: padding, selected: selected))
    }
}

/// A titled settings section: a bold heading, optional trailing accessory, and
/// a white card holding rows separated by `DLDivider()`.
struct DLSection<Content: View, Trailing: View>: View {
    let title: String
    var note: String? = nil
    var badge: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(DL.text(13.5, .semibold))
                    .foregroundStyle(DL.ink)
                if let badge {
                    DLTag(text: badge)
                }
                if let note {
                    Text("— \(note)").font(DL.text(12.5)).foregroundStyle(DL.faint)
                }
                Spacer(minLength: 0)
                trailing()
            }
            .padding(.horizontal, 3)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .dlCard(radius: 14)
        }
    }
}

extension DLSection where Trailing == EmptyView {
    init(_ title: String, note: String? = nil, badge: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.note = note
        self.badge = badge
        self.trailing = { EmptyView() }
        self.content = content
    }
}

extension DLSection {
    init(_ title: String, note: String? = nil, badge: String? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.note = note
        self.badge = badge
        self.trailing = trailing
        self.content = content
    }
}

struct DLDivider: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle().fill(DL.line2).frame(height: 1).padding(.leading, inset)
    }
}

/// Label + caption on the left, a control on the right.
struct DLRow<Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    var dimmed = false
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(DL.text(13, .semibold))
                    .foregroundStyle(dimmed ? DL.faint : DL.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(DL.text(11.5))
                        .foregroundStyle(dimmed ? DL.faint : DL.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// A row whose trailing control is a switch.
struct DLToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var dimmed = false

    var body: some View {
        DLRow(title: title, subtitle: subtitle, dimmed: dimmed) {
            DLSwitch(isOn: $isOn)
        }
    }
}

// MARK: - Tags, chips, badges

/// Small grey capsule, e.g. "600 MB", "Whisper only".
struct DLTag: View {
    let text: String
    var mono = false
    var tint: Color? = nil
    var fill: Color? = nil

    var body: some View {
        Text(text)
            .font(mono ? DL.mono(10, .semibold) : DL.text(10.5, .semibold))
            .foregroundStyle(tint ?? DL.sub)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(fill ?? DL.well))
            .fixedSize()
    }
}

/// Accent-tinted capsule, e.g. "Recommended".
struct DLAccentTag: View {
    let text: String
    @Environment(\.dlAccent) private var accent

    var body: some View {
        DLTag(text: text, tint: accent.color, fill: accent.soft)
    }
}

enum DLStatusKind { case ok, warn, live, accent, neutral }

/// Rounded status capsule with an optional icon: "In use", "Granted", "Needed".
struct DLStatusPill: View {
    let text: String
    var kind: DLStatusKind = .ok
    var icon: String? = nil
    @Environment(\.dlAccent) private var accent

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 10.5, weight: .semibold)) }
            Text(text).font(DL.text(11.5, .semibold))
        }
        .foregroundStyle(colors.fg)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(colors.bg))
        .fixedSize()
    }

    private var colors: (fg: Color, bg: Color) {
        switch kind {
        case .ok: return (DL.ok, DL.okSoft)
        case .warn: return (DL.warn, DL.warnSoft)
        case .live: return (DL.live, DL.liveSoft)
        case .accent: return (accent.color, accent.soft)
        case .neutral: return (DL.sub, DL.well)
        }
    }
}

/// Filter chip: capsule with optional leading icon or colour dot and a count.
struct DLChip: View {
    let title: String
    var count: Int? = nil
    var icon: String? = nil
    var dot: Color? = nil
    var selected = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let dot {
                    Circle().fill(dot).frame(width: 7, height: 7)
                }
                if let icon {
                    Image(systemName: icon).font(.system(size: 11, weight: .medium))
                }
                Text(title).font(DL.text(12.5, .semibold))
                if let count {
                    Text(count.formatted())
                        .font(DL.mono(10.5, .medium))
                        .foregroundStyle(selected ? Color.white.opacity(0.65) : DL.faint)
                }
            }
            .foregroundStyle(selected ? Color.white : DL.ink)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(selected ? DL.ink : (hovering ? DL.well : DL.card)))
            .overlay(Capsule().strokeBorder(selected ? Color.clear : DL.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Coloured square with the app's initial, used next to the app name.
struct AppMark: View {
    let name: String
    var size: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(AppColors.color(for: name))
            .frame(width: size, height: size)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.56, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

/// App name with its mark, in a soft capsule.
struct AppBadge: View {
    let name: String

    var body: some View {
        HStack(spacing: 6) {
            AppMark(name: name, size: 15)
            Text(name).font(DL.text(11.5, .semibold)).foregroundStyle(DL.ink2).lineLimit(1)
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(DL.well))
        .fixedSize()
    }
}

/// Stable per-app colours: well-known apps get their brand-ish colour, the rest
/// a colour picked from a palette by name.
enum AppColors {
    private static let known: [String: UInt32] = [
        "slack": 0x4A154B, "cursor": 0x1F2937, "mail": 0x1A82FB, "notes": 0xE5B400,
        "linear": 0x5E6AD2, "chrome": 0x1A73E8, "google chrome": 0x1A73E8, "safari": 0x0A84FF,
        "messages": 0x34C759, "xcode": 0x147EFB, "visual studio code": 0x007ACC, "code": 0x007ACC,
        "notion": 0x2F2F2F, "terminal": 0x2B2B2B, "iterm2": 0x2B2B2B, "ghostty": 0x3B3B5B,
        "arc": 0xFB4D6D, "discord": 0x5865F2, "whatsapp": 0x25D366, "telegram": 0x2AABEE,
        "obsidian": 0x7C3AED, "figma": 0xF24E1E, "zed": 0x0E7AE6, "claude": 0xD97757,
        "chatgpt": 0x10A37F, "pages": 0xF79A1B, "outlook": 0x0F6CBD, "teams": 0x5B5FC7,
    ]
    private static let fallback: [UInt32] = [0x6366F1, 0x0EA5A4, 0xF97316, 0xEC4899, 0x8B5CF6, 0x10B981, 0x3B82F6, 0xEAB308]

    static func color(for name: String) -> Color {
        if let hex = known[name.lowercased()] { return Color(hex: hex) }
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Color(hex: fallback[abs(sum) % fallback.count])
    }
}

// MARK: - Keycaps

struct Keycap: View {
    let text: String
    var highlighted = false
    var minWidth: CGFloat = 22
    var height: CGFloat = 22
    @Environment(\.dlAccent) private var accent

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(highlighted ? Color.white : DL.ink2)
            .padding(.horizontal, 6)
            .frame(minWidth: minWidth, minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .fill(highlighted ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(DL.card))
                    .shadow(color: .black.opacity(highlighted ? 0 : 0.12), radius: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .strokeBorder(highlighted ? Color.clear : DL.line, lineWidth: 1)
            )
            .fixedSize()
    }
}

/// Inline shortcut hint on a coloured button, e.g. "Right ⌥" inside Dictate.
struct InlineKeyHint: View {
    let text: String
    var onAccent = true

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(onAccent ? Color.white : DL.sub)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 5).fill(onAccent ? Color.white.opacity(0.22) : DL.well))
            .fixedSize()
    }
}

// MARK: - Icon wells

/// Settings-sidebar style icon: white glyph on a coloured rounded square.
struct IconSquare: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.9), color], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

/// Tinted rounded well with a coloured glyph — feature cards, dialog heads.
struct IconWell: View {
    let systemName: String
    var tint: Color? = nil
    var fill: Color? = nil
    var size: CGFloat = 34
    @Environment(\.dlAccent) private var accent

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(fill ?? (tint ?? accent.color).opacity(0.12))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(tint ?? accent.color)
            )
    }
}

/// The app's mark: a gradient rounded square with a waveform.
struct BrandMark: View {
    var size: CGFloat = 28
    @Environment(\.dlAccent) private var accent

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(accent.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "waveform")
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundStyle(.white)
            )
            .shadow(color: accent.color.opacity(0.3), radius: 4, y: 2)
    }
}

// MARK: - Meters & progress

/// Five dashes, `value` of them filled. Speed / accuracy on model rows.
struct DotMeter: View {
    let value: Int
    var total = 5
    @Environment(\.dlAccent) private var accent

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i < value ? accent.color : DL.line)
                    .frame(width: 11, height: 4)
            }
        }
    }
}

struct DLProgressRing: View {
    let progress: Double
    var size: CGFloat = 34
    var lineWidth: CGFloat = 3
    var showsLabel = true
    @Environment(\.dlAccent) private var accent

    var body: some View {
        ZStack {
            Circle().stroke(DL.line, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(accent.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)
            if showsLabel {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: size * 0.26, weight: .bold))
                    .foregroundStyle(accent.color)
                    .monospacedDigit()
            }
        }
        .frame(width: size, height: size)
    }
}

/// An accent arc that spins — for work without a known percentage.
struct DLSpinner: View {
    var size: CGFloat = 14
    var lineWidth: CGFloat = 2
    var color: Color? = nil
    @Environment(\.dlAccent) private var accent
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(color ?? accent.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

struct DLLinearProgress: View {
    let progress: Double
    var height: CGFloat = 5
    @Environment(\.dlAccent) private var accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DL.line)
                Capsule()
                    .fill(accent.gradient)
                    .frame(width: max(height, geo.size.width * min(1, max(0, progress))))
                    .animation(.linear(duration: 0.2), value: progress)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Shimmer

/// A sweeping highlight over placeholder content.
struct DLShimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Color.white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: phase * geo.size.width * 1.5)
                        .blendMode(.plusLighter)
                }
                .clipped()
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func dlShimmer() -> some View { modifier(DLShimmer()) }
}

/// Grey bars standing in for text that is being rewritten.
struct SkeletonLines: View {
    var lines = 3
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<lines, id: \.self) { i in
                Capsule()
                    .fill(DL.well)
                    .frame(height: 9)
                    .frame(maxWidth: i == lines - 1 ? 140 : .infinity)
            }
        }
        .dlShimmer()
    }
}

// MARK: - Waveform

/// Vertical bars from normalised `samples` (0…1). Bars before `progress` are
/// drawn in the accent, the rest in a muted tone.
struct WaveformBars: View {
    let samples: [Float]
    var progress: Double = 0
    var barWidth: CGFloat = 2.5
    var spacing: CGFloat = 2
    var activeColor: Color? = nil
    var inactiveColor: Color? = nil
    var minHeight: CGFloat = 3
    @Environment(\.dlAccent) private var accent

    var body: some View {
        GeometryReader { geo in
            let count = max(1, Int((geo.size.width + spacing) / (barWidth + spacing)))
            let values = WaveformBars.resample(samples, to: count)
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<count, id: \.self) { i in
                    let played = Double(i) / Double(count) < progress
                    Capsule()
                        .fill(played ? (activeColor ?? accent.color) : (inactiveColor ?? DL.line))
                        .frame(width: barWidth, height: max(minHeight, CGFloat(values[i]) * geo.size.height))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
    }

    static func resample(_ samples: [Float], to count: Int) -> [Float] {
        guard !samples.isEmpty else { return Array(repeating: 0.12, count: count) }
        return (0..<count).map { i in
            let start = i * samples.count / count
            let end = max(start + 1, (i + 1) * samples.count / count)
            let slice = samples[start..<min(end, samples.count)]
            return slice.max() ?? 0
        }
    }
}

// MARK: - Empty state

struct DLEmptyState: View {
    let icon: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            IconWell(systemName: icon, size: 44)
            Text(title).font(DL.display(16)).foregroundStyle(DL.ink)
            if let message {
                Text(message)
                    .font(DL.text(12.5))
                    .foregroundStyle(DL.sub)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .padding(24)
    }
}

// MARK: - Section heading

struct DLHeading: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(DL.text(14, .semibold)).foregroundStyle(DL.ink)
            if let subtitle {
                Text(subtitle).font(DL.text(12)).foregroundStyle(DL.faint)
            }
        }
    }
}
