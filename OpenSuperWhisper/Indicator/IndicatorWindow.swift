import AppKit
import SwiftUI

/// The floating recording pill. One-line states are a capsule; once content
/// wraps (live transcript, notices) it becomes a 340-wide rounded card that
/// grows to about six lines and then scrolls, pinned to the newest words.
struct IndicatorWindow: View {
    @ObservedObject var viewModel: IndicatorViewModel
    @ObservedObject private var appearance = AppearanceManager.shared
    @Environment(\.dlAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme

    /// Measured height of the live transcript block, used to grow the pill.
    @State private var liveTextHeight: CGFloat = 0

    /// Roughly six lines at 12.5pt; past this the block scrolls instead of growing.
    private let liveTextMaxHeight: CGFloat = 112

    private var hasPartialText: Bool {
        viewModel.state == .decoding && !viewModel.partialText.isEmpty
    }

    /// States whose content wraps onto more than one line.
    private var isWideContent: Bool {
        hasPartialText || viewModel.state == .notice
    }

    private var isErrorNotice: Bool {
        viewModel.state == .notice && viewModel.noticeIsError
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: isWideContent ? 18 : 22, style: .continuous)

        content
            .foregroundStyle(DL.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, isWideContent ? 12 : 0)
            .frame(minHeight: 44)
            .frame(width: isWideContent ? 340 : nil)
            .frame(minWidth: isWideContent ? nil : 180, maxWidth: 340)
            .fixedSize(horizontal: !isWideContent, vertical: false)
            .background { PillBackground(style: appearance.indicatorStyle, shape: shape) }
            .overlay {
                shape.strokeBorder(isErrorNotice ? DL.live.opacity(0.55) : Color.white.opacity(colorScheme == .dark ? 0.08 : 0.7),
                                   lineWidth: isErrorNotice ? 1.2 : 1)
            }
            .overlay { shape.strokeBorder(Color.black.opacity(colorScheme == .dark ? 0.35 : 0.06), lineWidth: 0.5) }
            .clipShape(shape)
            .shadow(color: (isErrorNotice ? DL.live : Color.black).opacity(colorScheme == .dark ? 0.4 : 0.16), radius: 14, y: 6)
            // Room for the shadow inside the 360-wide transparent panel.
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
            .scaleEffect(viewModel.isVisible ? 1 : 0.5)
            .offset(y: viewModel.isVisible ? 0 : 20)
            .opacity(viewModel.isVisible ? 1 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isVisible)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isWideContent)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.state)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: viewModel.contentAlignment)
            .onAppear {
                viewModel.isVisible = true
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .connecting:
            HStack(spacing: 10) {
                DLSpinner(size: 14)
                (Text("Connecting to ").foregroundColor(DL.sub)
                    + Text(MicrophoneService.shared.currentMicrophone?.displayName ?? "microphone").fontWeight(.semibold))
                    .font(DL.text(13, .medium))
                    .lineLimit(1)
                PillEscHint()
            }

        case .recording:
            HStack(spacing: 10) {
                PillLiveDot()
                Text(viewModel.elapsedString)
                    .font(DL.mono(13.5, .bold))
                    .monospacedDigit()
                    .fixedSize()
                PillLevelWave(recorder: viewModel.recorder)
                    .frame(width: 92, height: 20)
                PillEscHint()
            }

        case .decoding:
            if hasPartialText {
                HStack(alignment: .top, spacing: 10) {
                    DLSpinner(size: 13)
                        .padding(.top, 2)
                    ScrollView(.vertical) {
                        Text(viewModel.partialText)
                            .font(DL.text(12.5))
                            .foregroundStyle(DL.ink2)
                            .lineSpacing(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                proxy.size.height
                            } action: { height in
                                liveTextHeight = height
                            }
                    }
                    .frame(height: min(max(liveTextHeight, 16), liveTextMaxHeight))
                    // partialText is a full growing snapshot rebuilt on every
                    // segment, so anchor to the bottom to follow it.
                    .defaultScrollAnchor(.bottom)
                    .scrollIndicators(.never)
                    .scrollDisabled(liveTextHeight <= liveTextMaxHeight)
                }
            } else {
                HStack(spacing: 10) {
                    DLSpinner(size: 14)
                    Text("Transcribing").font(DL.text(13, .semibold))
                    Text("· \(ModelCatalog.activeModelName)").font(DL.text(12.5)).foregroundStyle(DL.faint)
                }
                .lineLimit(1)
            }

        case .formatting:
            HStack(spacing: 9) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent.gradient)
                Text("Formatting").font(DL.text(13, .semibold))
                if let mode = PillModeName.current {
                    Text("· \(mode) mode").font(DL.text(12.5)).foregroundStyle(DL.faint)
                }
            }
            .lineLimit(1)

        case .busy:
            HStack(spacing: 9) {
                Image(systemName: "hourglass").font(.system(size: 13, weight: .semibold)).foregroundStyle(DL.sub)
                Text("Still processing the last one…").font(DL.text(13, .semibold))
            }
            .lineLimit(1)

        case .notice:
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: viewModel.noticeIsError ? "exclamationmark.triangle" : "info.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(viewModel.noticeIsError ? DL.live : accent.color)
                Text(viewModel.noticeMessage)
                    .font(DL.text(13, .semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .idle:
            EmptyView()
        }
    }
}

// MARK: - Pieces

/// Frosted glass that blurs whatever is behind the panel, or a solid card.
private struct PillBackground: View {
    let style: IndicatorStyle
    let shape: RoundedRectangle
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch style {
        case .frosted:
            ZStack {
                PillVisualEffect()
                shape.fill(DL.card.opacity(colorScheme == .dark ? 0.55 : 0.62))
            }
        case .solid:
            shape.fill(DL.card)
        }
    }
}

private struct PillVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Coral dot with a soft halo that breathes while the mic is live.
private struct PillLiveDot: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle().fill(DL.live.opacity(0.25)).frame(width: 16, height: 16)
                .scaleEffect(pulsing ? 1.0 : 0.6)
                .opacity(pulsing ? 0.2 : 0.8)
            Circle().fill(DL.live).frame(width: 9, height: 9)
        }
        .frame(width: 16, height: 16)
        .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: pulsing)
        .onAppear { pulsing = true }
    }
}

/// Scrolling level history from the live microphone level, in the accent
/// gradient.
private struct PillLevelWave: View {
    @ObservedObject var recorder: AudioRecorder
    @State private var history: [Float] = Array(repeating: 0.05, count: 22)
    @Environment(\.dlAccent) private var accent

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(history.enumerated()), id: \.offset) { _, value in
                Capsule()
                    .frame(width: 2.5, height: 3 + CGFloat(value) * 17)
            }
        }
        .foregroundStyle(accent.gradient)
        .frame(maxHeight: .infinity)
        .animation(.easeOut(duration: 0.08), value: history)
        .onChange(of: recorder.level) { _, level in
            var next = history
            next.removeFirst()
            next.append(max(0.04, min(1, level)))
            history = next
        }
    }
}

private struct PillEscHint: View {
    var body: some View {
        Text("esc")
            .font(DL.mono(10, .semibold))
            .foregroundStyle(DL.faint)
            .padding(.horizontal, 5)
            .frame(height: 17)
            .background(RoundedRectangle(cornerRadius: 4.5).strokeBorder(DL.line, lineWidth: 1))
    }
}

/// Name of the formatting mode the pipeline will use, resolved the same way
/// `resolveFormattingPrompt` does: an app match when auto-switch is on, then
/// the active mode, then the first.
@MainActor
private enum PillModeName {
    static var current: String? {
        let prefs = AppPreferences.shared
        let modes = prefs.formattingModes
        guard !modes.isEmpty else { return nil }
        if prefs.autoSwitchFormattingMode,
           let bundleID = FocusUtils.lastFrontmostBundleID,
           let matched = modes.first(where: { $0.appBundleIDs.contains(bundleID) }) {
            return displayName(matched)
        }
        if let active = modes.first(where: { $0.id.uuidString == prefs.activeFormattingModeID }) {
            return displayName(active)
        }
        return modes.first.map(displayName)
    }

    private static func displayName(_ mode: FormattingMode) -> String {
        mode.name.isEmpty ? "Untitled" : mode.name
    }
}
