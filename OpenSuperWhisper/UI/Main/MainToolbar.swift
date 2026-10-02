import SwiftUI

/// Unified toolbar: brand, Home · Library · Insights, search, Dictate, Settings.
/// Leaves room on the left for the traffic lights of the hidden title bar.
struct MainToolbar: View {
    @ObservedObject var viewModel: MainViewModel
    @Binding var searchText: String
    var searchFocused: FocusState<Bool>.Binding
    var showsNavigation: Bool
    @ObservedObject private var router = AppRouter.shared

    var body: some View {
        HStack(spacing: 14) {
            BrandMark(size: 28)
            if showsNavigation {
                tabs
            } else {
                Text("OpenSuperWhisper").font(DL.text(14, .semibold)).foregroundStyle(DL.ink)
            }
            Spacer(minLength: 12)
            if showsNavigation {
                DLSearchField(placeholder: "Search transcripts", text: $searchText, shortcutHint: "⌘K", width: 230, focus: searchFocused)
                DictateButton(viewModel: viewModel)
            }
            Button {
                router.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.dlIcon(size: 32))
            .help("Settings (⌘,)")
        }
        .padding(.leading, 86)
        .padding(.trailing, 16)
        .frame(height: 58)
        .background(DL.card.opacity(0.92))
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(MainTab.allCases) { tab in
                let selected = router.tab == tab
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { router.tab = tab }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon).font(.system(size: 11.5, weight: .medium))
                        Text(tab.title).font(DL.text(13, .semibold))
                    }
                    .foregroundStyle(selected ? DL.ink : DL.sub)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(DL.raised)
                                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DL.well))
    }
}

/// Record from inside the app. Idle: accent "Dictate" with the hotkey; live:
/// red "Stop" with esc to cancel; busy: a spinner.
struct DictateButton: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject private var transcriptionService = TranscriptionService.shared
    @ObservedObject private var queue = TranscriptionQueue.shared
    @Environment(\.dlAccent) private var accent

    private var isWorking: Bool {
        viewModel.state == .decoding || viewModel.state == .formatting || viewModel.state == .connecting
    }

    private var isDisabled: Bool {
        transcriptionService.isLoading || transcriptionService.isTranscribing || queue.isProcessing
            || viewModel.state == .decoding || viewModel.state == .formatting
    }

    var body: some View {
        Button {
            if viewModel.isRecording {
                viewModel.startDecoding()
            } else {
                viewModel.startRecording()
            }
        } label: {
            HStack(spacing: 8) {
                if isWorking {
                    DLSpinner(size: 12, color: .white)
                    Text(viewModel.state == .connecting ? "Connecting…" : "Working…")
                } else if viewModel.isRecording {
                    Image(systemName: "stop.fill").font(.system(size: 10))
                    Text("Stop")
                    Text(TextUtil.formatDuration(viewModel.recordingDuration))
                        .font(DL.mono(11.5, .semibold))
                        .opacity(0.85)
                } else {
                    Image(systemName: "mic.fill").font(.system(size: 11))
                    Text("Dictate")
                    InlineKeyHint(text: HotkeyDescription.current)
                }
            }
            .font(DL.text(13, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(viewModel.isRecording ? AnyShapeStyle(DL.live) : AnyShapeStyle(accent.gradient))
            )
            .shadow(color: (viewModel.isRecording ? DL.live : accent.color).opacity(0.3), radius: 8, y: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled && !viewModel.isRecording)
        .opacity(isDisabled && !viewModel.isRecording ? 0.55 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isRecording)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.state)
        .help(viewModel.isRecording ? "Stop and transcribe" : "Dictate into OpenSuperWhisper (\(HotkeyDescription.current) works in any app)")
        .background {
            // Esc abandons an in-app recording.
            if viewModel.isRecording || viewModel.state == .connecting {
                Button("") { viewModel.cancelRecording() }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .allowsHitTesting(false)
            }
        }
    }
}
