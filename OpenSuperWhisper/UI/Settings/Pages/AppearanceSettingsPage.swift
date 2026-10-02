import SwiftUI

struct AppearanceSettingsPage: View {
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        SettingsPageScroll {
            DLSection("Appearance") {
                HStack(spacing: 12) {
                    ForEach(AppearanceMode.allCases) { mode in
                        SettingsAppearanceCard(mode: mode, selected: appearance.mode == mode) {
                            appearance.mode = mode
                        }
                    }
                }
                .padding(12)
            }

            DLSection("Accent colour") {
                HStack(alignment: .center, spacing: 16) {
                    HStack(spacing: 14) {
                        ForEach(DLAccent.allCases) { accent in
                            SettingsAccentSwatch(accent: accent, selected: appearance.accent == accent) {
                                appearance.accent = accent
                            }
                        }
                    }
                    Spacer(minLength: 12)
                    Text("Coral-red is reserved for the live microphone and stays that way whatever accent you pick.")
                        .font(DL.text(11.5))
                        .foregroundStyle(DL.faint)
                        .frame(maxWidth: 240, alignment: .leading)
                }
                .padding(16)
            }

            DLSection("Floating indicator") {
                DLRow(title: "Style", subtitle: "Frosted blends with any wallpaper; Solid is easier to spot on busy screens.") {
                    DLSegmented(
                        selection: $appearance.indicatorStyle,
                        options: IndicatorStyle.allCases.map { (value: $0, label: $0.title) }
                    )
                }
                SettingsIndicatorPreview(style: appearance.indicatorStyle)
                    .frame(height: 90)
            }

            DLSection("Reading") {
                DLRow(title: "Transcript text size", subtitle: "Used in the Library reading panel") {
                    DLSegmented(
                        selection: $appearance.transcriptSize,
                        options: TranscriptTextSize.allCases.map { (value: $0, label: $0.title) }
                    )
                }
                Text("The quick brown fox jumps over the lazy dog — a sample of how transcripts will read.")
                    .font(.system(size: appearance.transcriptSize.pointSize))
                    .foregroundStyle(DL.ink2)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }

            SettingsFootnote(text: "Your previous theme carried over: Graphite → Auto with the Graphite accent, Signal → the Amber accent. Obsidian users start in Light.")
        }
    }
}

private struct SettingsAppearanceCard: View {
    let mode: AppearanceMode
    let selected: Bool
    let action: () -> Void
    @Environment(\.dlAccent) private var accent

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    preview
                        .frame(height: 104)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    SettingsCheckMark(selected: selected).padding(7)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title).font(DL.text(13, .semibold)).foregroundStyle(DL.ink)
                    Text(mode.subtitle).font(DL.text(11.5)).foregroundStyle(DL.sub)
                }
                .padding(.horizontal, 4)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? accent.softer : DL.card))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? accent.color : DL.line, lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var preview: some View {
        switch mode {
        case .light: SettingsMiniWindow(dark: false)
        case .dark: SettingsMiniWindow(dark: true)
        case .auto:
            ZStack {
                SettingsMiniWindow(dark: false)
                SettingsMiniWindow(dark: true).mask(SettingsDiagonalHalf())
            }
        }
    }
}

private struct SettingsDiagonalHalf: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.62, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.42, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A tiny drawing of the main window in light or dark.
private struct SettingsMiniWindow: View {
    let dark: Bool
    @Environment(\.dlAccent) private var accent

    private var bg: Color { dark ? Color(hex: 0x15161C) : Color(hex: 0xF3F5F9) }
    private var card: Color { dark ? Color(hex: 0x262732) : .white }
    private var line: Color { dark ? Color(hex: 0x3A3C48) : Color(hex: 0xE3E6EE) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach([0xFF5F57, 0xFEBC2E, 0x28C840], id: \.self) { Circle().fill(Color(hex: UInt32($0))).frame(width: 4, height: 4) }
                Capsule().fill(line).frame(width: 30, height: 4).padding(.leading, 8)
                Spacer()
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 5).fill(card)
                    .overlay(Circle().fill(accent.gradient).frame(width: 22, height: 22))
                VStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 4).fill(card)
                            .overlay(alignment: .leading) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Capsule().fill(line).frame(width: 34, height: 3)
                                    Capsule().fill(line).frame(width: 22, height: 3)
                                }
                                .padding(.leading, 6)
                            }
                    }
                }
                .frame(width: 60)
            }
        }
        .padding(8)
        .background(bg)
    }
}

private struct SettingsAccentSwatch: View {
    let accent: DLAccent
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(accent.gradient)
                    .frame(width: 28, height: 28)
                    .padding(3)
                    .overlay(Circle().strokeBorder(selected ? accent.color : .clear, lineWidth: 2))
                Text(accent.title)
                    .font(DL.text(11, selected ? .semibold : .regular))
                    .foregroundStyle(selected ? DL.ink : DL.sub)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The recording pill over a wallpaper, in the chosen style.
private struct SettingsIndicatorPreview: View {
    let style: IndicatorStyle
    @Environment(\.dlAccent) private var accent

    private static let samples: [Float] = (0..<26).map { i in
        Float(0.35 + 0.65 * abs(sin(Double(i) * 0.9) * cos(Double(i) * 0.37)))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0xF8D9C4), Color(hex: 0xE4E1EC), Color(hex: 0xC9D8F2)],
                startPoint: .leading, endPoint: .trailing
            )
            HStack(spacing: 10) {
                Circle().fill(DL.live).frame(width: 9, height: 9)
                    .overlay(Circle().stroke(DL.live.opacity(0.25), lineWidth: 4))
                Text("0:07").font(DL.mono(13, .semibold)).foregroundStyle(DL.ink)
                WaveformBars(samples: Self.samples, progress: 1, barWidth: 2.5, spacing: 2, activeColor: accent.color)
                    .frame(width: 88, height: 18)
                Keycap(text: "esc", minWidth: 24, height: 18)
            }
            .padding(.horizontal, 16)
            .frame(height: 42)
            .background {
                if style == .frosted {
                    Capsule().fill(.ultraThinMaterial)
                } else {
                    Capsule().fill(DL.card)
                }
            }
            .overlay(Capsule().strokeBorder(Color.white.opacity(style == .frosted ? 0.6 : 0), lineWidth: 1))
            .overlay(Capsule().strokeBorder(DL.line.opacity(style == .solid ? 1 : 0), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14))
    }
}
