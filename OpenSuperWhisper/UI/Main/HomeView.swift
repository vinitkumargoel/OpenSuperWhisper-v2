import SwiftUI

/// Home: the big record orb with today's context, the transcription queue, the
/// latest transcripts (or first-run tips), today's numbers and quick settings.
struct HomeView: View {
    @ObservedObject var viewModel: MainViewModel
    let searchQuery: String
    let clearSearch: () -> Void
    @ObservedObject private var analytics = AnalyticsStore.shared
    @ObservedObject private var router = AppRouter.shared

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 22) {
                    HomeHero(viewModel: viewModel)
                    if !viewModel.queue.isEmpty {
                        QueueSection(queue: viewModel.queue) { viewModel.deleteRecording($0) }
                    }
                    if viewModel.counts.all == 0 && viewModel.queue.isEmpty {
                        EmptyLibraryTips()
                    } else {
                        LatestSection(viewModel: viewModel)
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 22) {
                    TodayTiles(snapshot: analytics.snapshot)
                    if SetupChecklist.isComplete(hasRecordings: viewModel.counts.all > 0) {
                        QuickSettingsCard()
                    } else {
                        SetupChecklist(hasRecordings: viewModel.counts.all > 0)
                    }
                }
                .frame(width: 300)
            }
            .padding(24)
        }
        .scrollIndicators(.automatic)
    }
}

// MARK: - Hero

private struct HomeHero: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject private var transcriptionService = TranscriptionService.shared
    @ObservedObject private var queue = TranscriptionQueue.shared
    @ObservedObject private var recorder = AudioRecorder.shared
    @Environment(\.dlAccent) private var accent
    @State private var levels: [Float] = Array(repeating: 0, count: 22)

    private var isLive: Bool { viewModel.isRecording }

    private var isDisabled: Bool {
        !isLive && (transcriptionService.isLoading || transcriptionService.isTranscribing || queue.isProcessing
            || viewModel.state == .decoding || viewModel.state == .formatting)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 22) {
                if isLive { LiveBars(levels: levels, mirrored: true) }
                RecordOrb(state: orbState) {
                    if viewModel.isRecording {
                        viewModel.startDecoding()
                    } else {
                        viewModel.startRecording()
                    }
                }
                .disabled(isDisabled)
                if isLive { LiveBars(levels: levels, mirrored: false) }
            }
            .frame(height: 230)

            VStack(spacing: 8) {
                headline
                Text(subtitle)
                    .font(DL.text(13.5))
                    .foregroundStyle(DL.sub)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 4)

            HeroChips()
                .padding(.top, 18)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: DL.radiusHero, style: .continuous).fill(DL.card)
                RoundedRectangle(cornerRadius: DL.radiusHero, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [(isLive ? DL.live : accent.color).opacity(0.10), .clear],
                            center: .topLeading, startRadius: 10, endRadius: 420
                        )
                    )
                RoundedRectangle(cornerRadius: DL.radiusHero, style: .continuous)
                    .fill(
                        RadialGradient(colors: [accent.color2.opacity(0.08), .clear], center: .bottomTrailing, startRadius: 10, endRadius: 380)
                    )
            }
        )
        .overlay(RoundedRectangle(cornerRadius: DL.radiusHero, style: .continuous).strokeBorder(DL.line2, lineWidth: 1))
        .shadow(color: DL.shadow, radius: 8, y: 2)
        .onReceive(recorder.$level) { level in
            guard isLive else { return }
            levels = Array((levels + [level]).suffix(22))
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isLive)
    }

    private var orbState: RecordOrb.OrbState {
        switch viewModel.state {
        case .recording: return .live
        case .connecting, .decoding, .formatting: return .working
        default: return transcriptionService.isLoading ? .working : .idle
        }
    }

    @ViewBuilder
    private var headline: some View {
        switch viewModel.state {
        case .recording:
            HStack(spacing: 10) {
                Circle().fill(DL.live).frame(width: 10, height: 10)
                    .opacity(viewModel.isBlinking ? 0.35 : 1)
                Text(TextUtil.formatDuration(viewModel.recordingDuration))
                    .font(DL.mono(30, .bold))
                    .foregroundStyle(DL.ink)
                    .contentTransition(.numericText())
            }
        case .connecting:
            Text("Connecting to your microphone…").font(DL.display(24)).foregroundStyle(DL.ink)
        case .decoding:
            Text("Transcribing…").font(DL.display(24)).foregroundStyle(DL.ink)
        case .formatting:
            Text("Formatting…").font(DL.display(24)).foregroundStyle(DL.ink)
        default:
            HStack(spacing: 0) {
                Text(AppPreferences.shared.holdToRecord ? "Hold " : "Press ")
                Text(HotkeyDescription.current).foregroundStyle(accent.color)
                Text(" to dictate")
            }
            .font(DL.display(24))
            .foregroundStyle(DL.ink)
        }
    }

    private var subtitle: String {
        switch viewModel.state {
        case .recording: return "Listening… click the orb to finish · esc to cancel"
        case .connecting: return "Bluetooth microphones take a moment to wake up."
        case .decoding: return "Turning your words into text with \(ModelCatalog.activeModelName)."
        case .formatting: return "Cleaning up grammar and punctuation."
        default:
            if transcriptionService.isLoading { return "Loading \(ModelCatalog.activeModelName)…" }
            return "Or click the orb. Text lands wherever your cursor is — and a copy stays in your Library."
        }
    }
}

/// The record button: an accent sphere at rest, coral while live.
struct RecordOrb: View {
    enum OrbState { case idle, live, working }
    let state: OrbState
    let action: () -> Void
    @Environment(\.dlAccent) private var accent
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill((state == .live ? DL.live : accent.color).opacity(0.05))
                    .frame(width: 220, height: 220)
                    .scaleEffect(state == .live && pulse ? 1.06 : 1)
                Circle()
                    .strokeBorder((state == .live ? DL.live : accent.color).opacity(0.14), lineWidth: 1)
                    .frame(width: 176, height: 176)
                Circle()
                    .fill(orbFill)
                    .overlay(
                        Circle().fill(
                            RadialGradient(colors: [.white.opacity(0.45), .clear], center: UnitPoint(x: 0.32, y: 0.25), startRadius: 2, endRadius: 70)
                        )
                    )
                    .frame(width: 128, height: 128)
                    .shadow(color: (state == .live ? DL.live : accent.color).opacity(0.35), radius: 18, y: 8)
                    .scaleEffect(hovering && isEnabled ? 1.04 : 1)
                icon
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.55)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
        .help(state == .live ? "Stop and transcribe" : "Start dictating")
    }

    private var orbFill: AnyShapeStyle {
        state == .live
            ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFF6B78), DL.live], startPoint: .top, endPoint: .bottom))
            : AnyShapeStyle(LinearGradient(colors: [accent.color2, accent.color], startPoint: .top, endPoint: .bottom))
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .live:
            RoundedRectangle(cornerRadius: 5).fill(.white).frame(width: 26, height: 26)
        case .working:
            DLSpinner(size: 34, lineWidth: 3.5, color: .white)
        case .idle:
            Image(systemName: "mic.fill").font(.system(size: 38, weight: .medium)).foregroundStyle(.white)
        }
    }
}

/// Live input level as bars beside the orb.
private struct LiveBars: View {
    let levels: [Float]
    let mirrored: Bool
    @Environment(\.dlAccent) private var accent

    var body: some View {
        let values = mirrored ? levels : levels.reversed()
        HStack(spacing: 4) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, level in
                Capsule()
                    .fill(LinearGradient(colors: [DL.live.opacity(0.75), accent.color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 4, height: 8 + CGFloat(min(1, level * 1.6)) * 56)
            }
        }
        .frame(height: 70)
        .animation(.easeOut(duration: 0.08), value: levels)
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }
}

// MARK: - Chips under the orb

private struct HeroChips: View {
    @ObservedObject private var settings = SettingsViewModel.shared
    @ObservedObject private var microphones = MicrophoneService.shared
    @ObservedObject private var transcriptionService = TranscriptionService.shared
    @ObservedObject private var models = ModelDownloadCenter.shared

    var body: some View {
        // One centred line when it fits; wraps at narrow window widths.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips }
            SettingsFlowLayout(spacing: 8, lineSpacing: 8) { chips }
        }
        .font(DL.text(12.5, .semibold))
        .foregroundStyle(DL.ink2)
    }

    @ViewBuilder
    private var chips: some View {
            Button {
                AppRouter.shared.openSettings(.model)
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(engineReady ? DL.ok : DL.warn).frame(width: 7, height: 7)
                    Text(ModelCatalog.activeModelName)
                    if transcriptionService.isLoading { Text("· loading").foregroundStyle(DL.faint) }
                }
                .heroChip()
            }
            .buttonStyle(.plain)
            .help("Speech model — change in Settings › Model")

            MicrophoneMenu {
                HStack(spacing: 6) {
                    Image(systemName: "mic").font(.system(size: 11))
                    Text(microphones.currentMicrophone?.displayName ?? "No microphone").lineLimit(1).frame(maxWidth: 200)
                    Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .bold)).foregroundStyle(DL.faint)
                }
                .heroChip()
            }

            LanguageMenu {
                HStack(spacing: 6) {
                    Image(systemName: "globe").font(.system(size: 11))
                    Text(LanguageUtil.languageNames[settings.selectedLanguage] ?? settings.selectedLanguage)
                    Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .bold)).foregroundStyle(DL.faint)
                }
                .heroChip()
            }

            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars").font(.system(size: 11))
                Text("Format with AI").lineLimit(1).fixedSize()
                Toggle("", isOn: $settings.formattingEnabled).labelsHidden().toggleStyle(.dl).scaleEffect(0.8)
                    .frame(width: 32, height: 18)
            }
            .heroChip()

            if settings.formattingEnabled {
                ModeMenu {
                    HStack(spacing: 6) {
                        Image(systemName: "square.stack.3d.up").font(.system(size: 11))
                        Text(activeModeName).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .bold)).foregroundStyle(DL.faint)
                    }
                    .heroChip()
                }
            }
    }

    private var engineReady: Bool {
        _ = models.revision
        return models.hasUsableModel && !transcriptionService.isLoading
    }

    private var activeModeName: String {
        settings.formattingModes.first { $0.id.uuidString == settings.activeFormattingModeID }?.name ?? "General"
    }
}

private extension View {
    func heroChip() -> some View {
        self
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Capsule().fill(DL.card))
            .overlay(Capsule().strokeBorder(DL.line, lineWidth: 1))
            .contentShape(Capsule())
    }
}

// MARK: - Shared pickers

/// Menu of microphones: built-in, then external, current one checked.
struct MicrophoneMenu<MenuLabel: View>: View {
    @ObservedObject private var microphones = MicrophoneService.shared
    @ViewBuilder var label: () -> MenuLabel

    var body: some View {
        Menu {
            let builtIn = microphones.availableMicrophones.filter { $0.isBuiltIn }
            let external = microphones.availableMicrophones.filter { !$0.isBuiltIn }
            if microphones.availableMicrophones.isEmpty {
                Text("No microphones available")
            }
            ForEach(builtIn) { mic in micButton(mic) }
            if !builtIn.isEmpty && !external.isEmpty { Divider() }
            ForEach(external) { mic in micButton(mic) }
        } label: {
            label()
        }
        .menuStyle(.button).buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func micButton(_ mic: MicrophoneService.AudioDevice) -> some View {
        Button {
            microphones.selectMicrophone(mic)
        } label: {
            if microphones.currentMicrophone?.id == mic.id {
                Label(mic.displayName, systemImage: "checkmark")
            } else {
                Text(mic.displayName)
            }
        }
    }
}

struct LanguageMenu<MenuLabel: View>: View {
    @ObservedObject private var settings = SettingsViewModel.shared
    @ViewBuilder var label: () -> MenuLabel

    var body: some View {
        Menu {
            ForEach(LanguageUtil.availableLanguages, id: \.self) { code in
                Button {
                    settings.selectedLanguage = code
                } label: {
                    let name = LanguageUtil.languageNames[code] ?? code
                    if settings.selectedLanguage == code {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
        } label: {
            label()
        }
        .menuStyle(.button).buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct ModeMenu<MenuLabel: View>: View {
    @ObservedObject private var settings = SettingsViewModel.shared
    @ViewBuilder var label: () -> MenuLabel

    var body: some View {
        Menu {
            ForEach(settings.formattingModes) { mode in
                Button {
                    settings.activeFormattingModeID = mode.id.uuidString
                } label: {
                    let name = mode.name.isEmpty ? "Untitled" : mode.name
                    if settings.activeFormattingModeID == mode.id.uuidString {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
            Divider()
            Button("Edit Modes…") { AppRouter.shared.openSettings(.modes) }
        } label: {
            label()
        }
        .menuStyle(.button).buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
