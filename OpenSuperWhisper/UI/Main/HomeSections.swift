import SwiftUI

// MARK: - Queue

/// Files waiting for, or going through, transcription.
struct QueueSection: View {
    let queue: [Recording]
    let onRemove: (Recording) -> Void
    @State private var pendingRemoval: Recording?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                DLHeading(title: "Queue", subtitle: queue.count == 1 ? "1 item" : "\(queue.count) items")
                Spacer()
            }
            VStack(spacing: 0) {
                ForEach(Array(queue.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { DLDivider() }
                    QueueRow(recording: item, position: index) { pendingRemoval = item }
                }
            }
            .dlCard(radius: 14)
        }
        .confirmationDialog(
            "Remove this item from the queue?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let item = pendingRemoval { onRemove(item) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Transcription stops and the audio copy is deleted. The original file is not touched.")
        }
    }
}

private struct QueueRow: View {
    let recording: Recording
    let position: Int
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconWell(systemName: recording.sourceFileName == nil ? "mic" : "waveform", size: 34)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(recording.sourceFileName ?? (recording.isRegeneration ? "Re-transcribing a recording" : "Recording"))
                        .font(DL.text(13, .semibold))
                        .foregroundStyle(DL.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(TextUtil.formatDuration(recording.duration)) · \(statusText)")
                        .font(DL.text(11.5))
                        .foregroundStyle(DL.sub)
                        .lineLimit(1)
                }
                if recording.status != .pending {
                    DLLinearProgress(progress: Double(recording.progress), height: 5)
                }
            }
            Spacer(minLength: 8)
            if recording.status != .pending {
                Text("\(Int(recording.progress * 100))%")
                    .font(DL.mono(11.5, .semibold))
                    .foregroundStyle(DL.sub)
                    .monospacedDigit()
            }
            Button("Remove", action: onRemove)
                .buttonStyle(.dl(.ghost, size: .small))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var statusText: String {
        switch recording.status {
        case .pending: return position == 0 ? "In queue — starts next" : "In queue"
        case .converting: return "Converting…"
        case .transcribing: return "Transcribing with \(ModelCatalog.activeModelName)"
        case .formatting: return "Formatting…"
        case .completed: return "Done"
        case .failed: return "Failed"
        }
    }
}

// MARK: - Latest

struct LatestSection: View {
    @ObservedObject var viewModel: MainViewModel

    private var latest: [Recording] {
        Array(viewModel.recordings.filter { !$0.isPending }.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DLHeading(title: "Latest")
                Spacer()
                Button("Open Library →") { AppRouter.shared.show(.library) }
                    .buttonStyle(.plain)
                    .font(DL.text(12.5, .semibold))
                    .foregroundStyle(DL.sub)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(latest) { recording in
                    RecordingCard(
                        recording: recording,
                        isSelected: false,
                        searchQuery: "",
                        onSelect: { AppRouter.shared.reveal(recording.id) },
                        onToggleStar: { viewModel.toggleStar(recording) },
                        onRetry: { Task { await TranscriptionQueue.shared.requeueRecording(recording) } }
                    )
                }
            }
        }
    }
}

// MARK: - First run

struct EmptyLibraryTips: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DLHeading(title: "Your library is empty", subtitle: "Everything you dictate will appear here")
            HStack(alignment: .top, spacing: 12) {
                tip("character.cursor.ibeam", Color(hex: 0x5B5BF6), "Dictate anywhere",
                    "Click into any text field — Slack, Mail, Cursor — and \(HotkeyDescription.instruction.lowercased()).")
                tip("square.and.arrow.down", Color(hex: 0x0E9F9A), "Drop audio files",
                    "Drag .m4a, .mp3 or .wav onto this window. Several at once are queued.")
                tip("text.bubble", Color(hex: 0xEC4899), "Speak punctuation",
                    "Say “new paragraph” or “question mark”. Turn it on in Settings › Transcription.")
            }
        }
    }

    private func tip(_ icon: String, _ color: Color, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            IconWell(systemName: icon, tint: color, size: 34)
            Text(title).font(DL.text(13.5, .semibold)).foregroundStyle(DL.ink)
            Text(text).font(DL.text(12)).foregroundStyle(DL.sub).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .dlCard(radius: 14)
    }
}

// MARK: - Today

struct TodayTiles: View {
    let snapshot: AnalyticsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DLHeading(title: "Today")
                Spacer()
                Button("Insights →") { AppRouter.shared.show(.insights) }
                    .buttonStyle(.plain)
                    .font(DL.text(12.5, .semibold))
                    .foregroundStyle(DL.sub)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                StatTile(icon: "mic", label: "Recordings", value: snapshot.todayRecordings.formatted(), unit: nil, detail: "dictations")
                StatTile(icon: "textformat", label: "Words", value: snapshot.todayWords.formatted(), unit: nil, detail: "transcribed")
                StatTile(icon: "timer", label: "Recorded", value: DurationText.minutes(snapshot.todayDuration), unit: "min", detail: "of audio")
                StatTile(icon: "bolt", label: "Time saved", value: DurationText.minutes(snapshot.todayEstimatedTimeSaved), unit: "min", detail: "vs. typing")
            }
        }
    }
}

struct StatTile: View {
    let icon: String
    let label: String
    let value: String
    let unit: String?
    let detail: String
    @Environment(\.dlAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium)).foregroundStyle(accent.color)
                Text(label).font(DL.text(11.5, .semibold)).foregroundStyle(DL.sub)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(DL.display(24, .bold)).foregroundStyle(DL.ink).lineLimit(1).minimumScaleFactor(0.6)
                if let unit { Text(unit).font(DL.text(12, .medium)).foregroundStyle(DL.faint) }
            }
            Text(detail).font(DL.text(11)).foregroundStyle(DL.faint)
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dlCard(radius: 14)
    }
}

// MARK: - Set-up checklist

struct SetupChecklist: View {
    let hasRecordings: Bool
    @ObservedObject private var models = ModelDownloadCenter.shared
    @ObservedObject private var settings = SettingsViewModel.shared

    static func isComplete(hasRecordings: Bool) -> Bool {
        hasRecordings && ModelDownloadCenter.shared.hasUsableModel
    }

    private var items: [(done: Bool, title: String, detail: String, action: (() -> Void)?)] {
        [
            (models.hasUsableModel, "Download a model",
             models.isDownloading ? "Downloading \(models.downloadingModel?.name ?? "")…" : ModelCatalog.activeModelName,
             { AppRouter.shared.openSettings(.model) }),
            (true, "Allow microphone & accessibility", "Both granted", nil),
            (hasRecordings, "Try your first dictation", "\(HotkeyDescription.instruction) for a second or two", nil),
            (settings.formattingEnabled, "Turn on Format with AI", "Cleans up “um”s and false starts",
             { AppRouter.shared.openSettings(.formatting) }),
        ]
    }

    var body: some View {
        let list = items
        VStack(alignment: .leading, spacing: 10) {
            DLHeading(title: "Get set up", subtitle: "\(list.filter(\.done).count) of \(list.count)")
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.offset) { index, item in
                    if index > 0 { DLDivider() }
                    Button {
                        item.action?()
                    } label: {
                        HStack(alignment: .top, spacing: 11) {
                            ZStack {
                                if item.done {
                                    Circle().fill(DL.ok)
                                    Image(systemName: "checkmark").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white)
                                } else {
                                    Circle().strokeBorder(DL.line, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                                }
                            }
                            .frame(width: 20, height: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(DL.text(13, .semibold))
                                    .strikethrough(item.done, color: DL.faint)
                                    .foregroundStyle(item.done ? DL.faint : DL.ink)
                                Text(item.detail).font(DL.text(11.5)).foregroundStyle(DL.sub)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(item.action == nil || item.done)
                }
            }
            .dlCard(radius: 14)
        }
    }
}

// MARK: - Quick settings

struct QuickSettingsCard: View {
    @ObservedObject private var settings = SettingsViewModel.shared
    @ObservedObject private var microphones = MicrophoneService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DLHeading(title: "Quick settings")
                Spacer()
                Button("All settings →") { AppRouter.shared.openSettings() }
                    .buttonStyle(.plain)
                    .font(DL.text(12.5, .semibold))
                    .foregroundStyle(DL.sub)
            }
            VStack(spacing: 0) {
                row("wand.and.stars", "Format with AI", settings.formattingBackend == .s1mini ? "On-device · S1-mini" : "API endpoint") {
                    DLSwitch(isOn: $settings.formattingEnabled)
                }
                DLDivider(inset: 14)
                row("square.stack.3d.up", "Mode", settings.autoSwitchFormattingMode ? "Switches by app" : "Used for every app") {
                    ModeMenu { DLMenuLabel(text: activeModeName, width: 104) }
                }
                DLDivider(inset: 14)
                row("globe", "Language", nil) {
                    LanguageMenu { DLMenuLabel(text: LanguageUtil.languageNames[settings.selectedLanguage] ?? settings.selectedLanguage, width: 104) }
                }
                DLDivider(inset: 14)
                row("mic", "Microphone", nil) {
                    MicrophoneMenu { DLMenuLabel(text: microphones.currentMicrophone?.displayName ?? "None", width: 120) }
                }
            }
            .dlCard(radius: 14)
        }
    }

    private var activeModeName: String {
        settings.formattingModes.first { $0.id.uuidString == settings.activeFormattingModeID }?.name ?? "General"
    }

    private func row<Accessory: View>(_ icon: String, _ title: String, _ detail: String?, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(spacing: 10) {
            IconWell(systemName: icon, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(DL.text(13, .semibold)).foregroundStyle(DL.ink).lineLimit(1)
                if let detail { Text(detail).font(DL.text(11)).foregroundStyle(DL.faint).lineLimit(1) }
            }
            .layoutPriority(1)
            Spacer(minLength: 6)
            accessory()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
