import AppKit
import SwiftUI

/// The menu-bar panel: start/stop dictation, the last transcript, quick
/// switches (Format with AI, mode, language, microphone) and the app commands.
struct StatusPanelView: View {
    @ObservedObject private var settings = SettingsViewModel.shared
    @ObservedObject private var microphones = MicrophoneService.shared
    @ObservedObject private var recorder = AudioRecorder.shared
    @ObservedObject private var transcription = TranscriptionService.shared
    @ObservedObject private var downloads = ModelDownloadCenter.shared
    @Environment(\.dlAccent) private var accent

    @State private var expanded: PanelSection?
    @State private var lastRecording: Recording?
    @State private var copied = false

    enum PanelSection { case mode, language, microphone }

    var body: some View {
        VStack(spacing: 10) {
            header
            dictateButton
            if let lastRecording {
                PanelLastTranscript(recording: lastRecording, copied: $copied)
            }
            quickRows
            DLDivider().padding(.horizontal, 6)
            commands
        }
        .padding(12)
        .frame(width: 340)
        .background(DL.window)
        .animation(.easeInOut(duration: 0.2), value: expanded)
        .task { await loadLastRecording() }
        .onReceive(NotificationCenter.default.publisher(for: RecordingStore.recordingsDidUpdateNotification)) { _ in
            Task { await loadLastRecording() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            BrandMark(size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("OpenSuperWhisper").font(DL.text(13.5, .semibold)).foregroundStyle(DL.ink)
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(statusText).font(DL.text(11.5)).foregroundStyle(DL.sub).lineLimit(1)
                }
            }
            Spacer()
            Button {
                close()
                AppRouter.shared.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.dlIcon(size: 28, bordered: false))
            .help("Settings")
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var statusText: String {
        if recorder.isRecording { return "Listening…" }
        if transcription.isTranscribing { return "Transcribing…" }
        if transcription.isLoading { return "\(ModelCatalog.activeModelName) · loading" }
        if !downloads.hasUsableModel { return "No model downloaded" }
        return "\(ModelCatalog.activeModelName) · ready"
    }

    private var statusColor: Color {
        if recorder.isRecording { return DL.live }
        if transcription.isLoading || transcription.isTranscribing { return DL.warn }
        return downloads.hasUsableModel ? DL.ok : DL.faint
    }

    // MARK: - Dictate

    private var isLive: Bool { recorder.isRecording || recorder.isConnecting }

    private var dictateButton: some View {
        Button(action: toggleDictation) {
            HStack(spacing: 10) {
                Image(systemName: isLive ? "stop.fill" : "mic.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(isLive ? "Stop dictation" : "Start dictation")
                    .font(DL.text(14, .semibold))
                Spacer()
                InlineKeyHint(text: isLive ? "esc to cancel" : HotkeyDescription.instruction)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isLive ? AnyShapeStyle(DL.live) : AnyShapeStyle(accent.gradient))
            )
            .shadow(color: (isLive ? DL.live : accent.color).opacity(0.3), radius: 10, y: 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isLive && (transcription.isTranscribing || !downloads.hasUsableModel))
    }

    /// Starts or stops dictation through the same indicator flow the hotkey
    /// uses, so recording, pasting and History behave identically.
    private func toggleDictation() {
        if isLive {
            ShortcutManager.shared.toggleRecordingFromUI()
            return
        }
        // Close first so focus returns to the app the text should land in.
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            ShortcutManager.shared.toggleRecordingFromUI()
        }
    }

    // MARK: - Quick rows

    private var quickRows: some View {
        VStack(spacing: 2) {
            PanelRow(icon: "wand.and.stars", title: "Format with AI") {
                DLSwitch(isOn: $settings.formattingEnabled)
            }

            PanelDisclosureRow(icon: "square.3.layers.3d", title: "Mode", value: activeModeName,
                               isOpen: expanded == .mode) { toggle(.mode) }
            if expanded == .mode {
                PanelOptionList {
                    ForEach(settings.formattingModes) { mode in
                        PanelOption(title: mode.name.isEmpty ? "Untitled" : mode.name,
                                    detail: mode.appBundleIDs.isEmpty ? nil : "\(mode.appBundleIDs.count) app\(mode.appBundleIDs.count == 1 ? "" : "s")",
                                    selected: mode.id.uuidString == settings.activeFormattingModeID) {
                            settings.activeFormattingModeID = mode.id.uuidString
                        }
                    }
                }
            }

            PanelDisclosureRow(icon: "globe", title: "Language",
                               value: LanguageUtil.languageNames[settings.selectedLanguage] ?? settings.selectedLanguage,
                               isOpen: expanded == .language) { toggle(.language) }
            if expanded == .language {
                PanelOptionList(maxHeight: 250) {
                    ForEach(LanguageUtil.availableLanguages, id: \.self) { code in
                        PanelOption(title: LanguageUtil.languageNames[code] ?? code, detail: nil,
                                    selected: code == settings.selectedLanguage) {
                            settings.selectedLanguage = code
                        }
                        if code == "auto" { DLDivider().padding(.vertical, 3) }
                    }
                }
            }

            PanelDisclosureRow(icon: "mic", title: "Microphone",
                               value: microphones.currentMicrophone?.displayName ?? "None",
                               isOpen: expanded == .microphone) { toggle(.microphone) }
            if expanded == .microphone {
                PanelOptionList {
                    microphoneOptions
                }
            }
        }
    }

    @ViewBuilder
    private var microphoneOptions: some View {
        let builtIn = microphones.availableMicrophones.filter { $0.isBuiltIn }
        let external = microphones.availableMicrophones.filter { !$0.isBuiltIn }
        if microphones.availableMicrophones.isEmpty {
            Text("No microphones available")
                .font(DL.text(12.5))
                .foregroundStyle(DL.faint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        } else {
            ForEach(builtIn) { mic in micOption(mic) }
            if !builtIn.isEmpty && !external.isEmpty {
                DLDivider().padding(.vertical, 3)
            }
            ForEach(external) { mic in micOption(mic) }
        }
    }

    private func micOption(_ mic: MicrophoneService.AudioDevice) -> some View {
        PanelOption(title: mic.displayName, detail: mic.isBuiltIn ? "Built-in" : nil,
                    selected: microphones.currentMicrophone?.id == mic.id) {
            microphones.selectMicrophone(mic)
        }
    }

    private var activeModeName: String {
        let mode = settings.formattingModes.first { $0.id.uuidString == settings.activeFormattingModeID }
            ?? settings.formattingModes.first
        guard let mode else { return "—" }
        return mode.name.isEmpty ? "Untitled" : mode.name
    }

    private func toggle(_ section: PanelSection) {
        expanded = expanded == section ? nil : section
    }

    // MARK: - Commands

    private var commands: some View {
        VStack(spacing: 0) {
            PanelCommand(icon: "macwindow", title: "Open OpenSuperWhisper", shortcut: "⌘O") {
                close()
                (NSApp.delegate as? AppDelegate)?.showMainWindow()
            }
            .keyboardShortcut("o", modifiers: .command)
            PanelCommand(icon: "gearshape", title: "Settings…", shortcut: "⌘,") {
                close()
                AppRouter.shared.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            PanelCommand(icon: "power", title: "Quit", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private func close() {
        (NSApp.delegate as? AppDelegate)?.closeStatusPanel()
    }

    private func loadLastRecording() async {
        let recent = (try? await RecordingStore.shared.fetchRecordings(limit: 10, offset: 0, filter: .all)) ?? []
        lastRecording = recent.first {
            $0.status == .completed && !$0.transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

// MARK: - Pieces

private struct PanelLastTranscript: View {
    let recording: Recording
    @Binding var copied: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let app = recording.targetAppName, !app.isEmpty {
                    AppBadge(name: app)
                }
                Text("\(recording.timestamp.formatted(date: .omitted, time: .shortened)) · \(TextUtil.wordCount(recording.transcription)) words")
                    .font(DL.text(11.5))
                    .foregroundStyle(DL.faint)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(recording.transcription, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10.5, weight: .semibold))
                        Text(copied ? "Copied" : "Copy")
                    }
                }
                .buttonStyle(.dl(.secondary, size: .small))
            }
            Text(recording.transcription)
                .font(DL.text(12.5))
                .foregroundStyle(DL.ink2)
                .lineLimit(3)
                .lineSpacing(1.5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .dlCard(radius: 12)
        .contentShape(Rectangle())
        .onTapGesture {
            (NSApp.delegate as? AppDelegate)?.closeStatusPanel()
            AppRouter.shared.reveal(recording.id)
        }
        .help("Show in Library")
    }
}

private struct PanelRow<Accessory: View>: View {
    let icon: String
    let title: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(DL.sub).frame(width: 18)
            Text(title).font(DL.text(13, .medium)).foregroundStyle(DL.ink)
            Spacer()
            accessory()
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
    }
}

private struct PanelDisclosureRow: View {
    let icon: String
    let title: String
    let value: String
    let isOpen: Bool
    let action: () -> Void
    @Environment(\.dlAccent) private var accent

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(isOpen ? accent.color : DL.sub).frame(width: 18)
                Text(title).font(DL.text(13, .medium)).foregroundStyle(DL.ink)
                Spacer()
                Text(value)
                    .font(DL.text(12.5, isOpen ? .semibold : .regular))
                    .foregroundStyle(isOpen ? accent.color : DL.sub)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DL.faint)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
        }
        .buttonStyle(DLRowButtonStyle(selected: isOpen))
    }
}

private struct PanelOptionList<Content: View>: View {
    var maxHeight: CGFloat? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if let maxHeight {
                ScrollView(showsIndicators: true) {
                    VStack(spacing: 1) { content() }.padding(4)
                }
                .frame(height: maxHeight)
            } else {
                VStack(spacing: 1) { content() }.padding(4)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DL.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DL.line2, lineWidth: 1))
        .padding(.leading, 28)
        .padding(.bottom, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

private struct PanelOption: View {
    let title: String
    let detail: String?
    let selected: Bool
    let action: () -> Void
    @Environment(\.dlAccent) private var accent

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(selected ? 1 : 0)
                    .frame(width: 12)
                Text(title).font(DL.text(12.5, selected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 6)
                if let detail {
                    Text(detail).font(DL.text(11)).foregroundStyle(selected ? Color.white.opacity(0.75) : DL.faint)
                }
            }
            .foregroundStyle(selected ? Color.white : DL.ink)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? accent.color : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(DLRowButtonStyle(radius: 6))
    }
}

private struct PanelCommand: View {
    let icon: String
    let title: String
    let shortcut: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 12.5)).foregroundStyle(DL.sub).frame(width: 18)
                Text(title).font(DL.text(13)).foregroundStyle(DL.ink)
                Spacer()
                Text(shortcut).font(DL.text(11.5)).foregroundStyle(DL.faint)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
        }
        .buttonStyle(DLRowButtonStyle())
    }
}
