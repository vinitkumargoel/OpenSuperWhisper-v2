import AppKit
import SwiftUI

/// The reading panel for one recording: header, transcript (or its status),
/// audio player and every action.
struct RecordingDetailView: View {
    let recording: Recording
    let searchQuery: String
    let actions: RecordingActions
    let onClose: () -> Void

    @State private var showOriginal = false
    @State private var showReformat = false
    @Environment(\.dlAccent) private var accent
    @Environment(\.dlTranscriptSize) private var transcriptSize

    private var selectedText: String {
        if showOriginal, let raw = recording.distinctRawTranscription { return raw }
        return recording.transcription
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    statusBlock
                    transcriptBlock
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 12) {
                metaChips
                if !recording.isPending {
                    WaveformPlayer(url: recording.url, duration: recording.duration)
                }
                actionRow
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .padding(.top, 4)
        }
        .background(DL.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DL.line2, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 4)
        .onChange(of: recording.id) { _, _ in showOriginal = false }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            if let app = recording.targetAppName, !app.isEmpty {
                AppBadge(name: app)
                Text("Pasted into \(app) · \(recording.relativeTimestamp)")
                    .help("Pasted into \(app)")
            } else if let file = recording.sourceFileName {
                DLTag(text: "Imported file")
                Text("\(file) · \(recording.relativeTimestamp)").lineLimit(1).truncationMode(.middle)
            } else {
                DLTag(text: "Dictated")
                Text(recording.relativeTimestamp)
            }
            Spacer(minLength: 6)
            if recording.status == .completed {
                Button(action: actions.toggleStar) {
                    Image(systemName: recording.isStarred ? "star.fill" : "star")
                        .foregroundStyle(recording.isStarred ? DL.star : DL.sub)
                }
                .buttonStyle(.dlIcon(size: 30, bordered: false))
                .background(recording.isStarred ? RoundedRectangle(cornerRadius: 8).fill(DL.star.opacity(0.14)) : nil)
                .help(recording.isStarred ? "Unstar" : "Star")
            }
            Menu {
                RecordingContextMenu(recording: recording, actions: actions)
            } label: {
                Image(systemName: "ellipsis").frame(width: 30, height: 30).contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(DL.sub)
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.dlIcon(size: 30, bordered: false))
            .help("Close")
        }
        .font(DL.text(12.5))
        .foregroundStyle(DL.sub)
    }

    // MARK: Status

    @ViewBuilder
    private var statusBlock: some View {
        if recording.isPending && !recording.isRegenerating {
            HStack(spacing: 12) {
                if recording.status == .pending {
                    IconWell(systemName: "clock", size: 38)
                } else {
                    DLProgressRing(progress: Double(recording.progress), size: 38)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(recording.status == .pending ? "Waiting in the queue" : recording.statusText)
                        .font(DL.text(14, .semibold)).foregroundStyle(DL.ink)
                    Text(recording.status == .pending
                         ? "It starts as soon as the item ahead of it finishes."
                         : "\(ModelCatalog.activeModelName) is working on it.")
                        .font(DL.text(12)).foregroundStyle(DL.sub)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(accent.softer))
        } else if recording.isFailed {
            failureCard
        } else if let warning = recording.formattingWarning, !recording.displayTranscription.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11))
                Text("AI formatting didn't run: \(warning)").lineLimit(2)
            }
            .font(DL.text(12))
            .foregroundStyle(DL.warn)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(DL.warnSoft))
        }
    }

    private var failureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconWell(systemName: "exclamationmark.triangle", tint: DL.live, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transcription failed").font(DL.text(15, .semibold)).foregroundStyle(DL.ink)
                    Text("\(TextUtil.formatDuration(recording.duration)) of audio · the recording was kept")
                        .font(DL.text(11.5)).foregroundStyle(DL.sub)
                }
            }
            Text(recording.failureReason)
                .font(DL.text(13))
                .foregroundStyle(DL.ink2)
                .textSelection(.enabled)
            // A failed run keeps whatever transcript was already there.
            if recording.errorMessage != nil, !recording.transcription.isEmpty {
                Text(recording.transcription)
                    .font(DL.text(12.5))
                    .foregroundStyle(DL.sub)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                Button {
                    actions.regenerate()
                } label: {
                    Label("Retry transcription", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.dlPrimary)
                Button {
                    AppRouter.shared.openSettings(.model)
                } label: {
                    Label("Change model", systemImage: "cpu")
                }
                .buttonStyle(.dlSecondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(DL.liveSoft.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DL.live.opacity(0.18), lineWidth: 1))
    }

    // MARK: Transcript

    @ViewBuilder
    private var transcriptBlock: some View {
        if !recording.isFailed && !recording.displayTranscription.isEmpty {
            if recording.distinctRawTranscription != nil {
                HStack(spacing: 10) {
                    DLSegmented(selection: $showOriginal, options: [(false, "Formatted"), (true, "Original")], size: .small)
                    Text(showOriginal ? "Straight from the transcription model" : "After AI formatting")
                        .font(DL.text(11.5)).foregroundStyle(DL.faint)
                }
            }
            ZStack(alignment: .topLeading) {
                HighlightedText(text: selectedText, query: searchQuery)
                    .font(.system(size: transcriptSize))
                    .lineSpacing(transcriptSize * 0.42)
                    .foregroundStyle(DL.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(recording.isRegenerating ? 0.35 : 1)
                if recording.isRegenerating {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            DLSpinner(size: 12)
                            Text("Regenerating · \(recording.statusText) \(Int(recording.progress * 100))%")
                                .font(DL.text(12, .semibold)).foregroundStyle(accent.color)
                        }
                        SkeletonLines(lines: 4)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(DL.card.opacity(0.85)))
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: recording.isRegenerating)
        } else if !recording.isPending && !recording.isFailed {
            DLEmptyState(icon: "waveform", title: "No speech detected",
                         message: "The model didn't hear any words in this recording. You can play it back or regenerate it.")
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Footer

    private var metaChips: some View {
        HStack(spacing: 6) {
            metaChip("timer", TextUtil.formatDuration(recording.duration))
            if recording.status == .completed {
                metaChip("textformat", "\(recording.wordCount) words")
            }
            if let app = recording.targetAppName, !app.isEmpty {
                metaChip("arrow.right.circle", app).help("Pasted into \(app)")
            }
            Spacer()
        }
    }

    private func metaChip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text)
        }
        .font(DL.text(11.5, .semibold))
        .foregroundStyle(DL.sub)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 6).fill(DL.well))
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            if !recording.isPending && !recording.isFailed {
                Button {
                    RecordingActions.copy(selectedText)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.dlPrimary)
                .help("Copy entire text")
                .disabled(selectedText.isEmpty)
            }
            if recording.status == .completed && !recording.transcription.isEmpty {
                Button {
                    showReformat = true
                } label: {
                    Label("Reformat", systemImage: "wand.and.stars")
                }
                .buttonStyle(.dlSecondary)
                .help("Reformat using your current formatting settings (no re-transcription)")
                .popover(isPresented: $showReformat, arrowEdge: .top) {
                    ReformatPopover(recording: recording)
                        .daylight()
                }
            }
            if recording.status == .completed {
                Button(action: actions.regenerate) {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.dlSecondary)
                .help("Regenerate transcription (full re-transcription)")
            }
            Spacer(minLength: 0)
            if !recording.isPending {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([recording.url])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.dlIcon(size: 30, bordered: false))
                .help("Reveal audio in Finder")
            }
            Button(action: actions.requestDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.dlIcon(size: 30, bordered: false, tint: DL.live))
            .help(recording.isPending ? "Remove from queue" : "Delete recording")
        }
        .labelStyle(CompactLabelStyle())
    }
}

// MARK: - Waveform player

/// Play/stop, the recording's real waveform with a playhead, and the time.
/// Clicking the waveform seeks.
struct WaveformPlayer: View {
    let url: URL
    let duration: TimeInterval
    @ObservedObject private var recorder = AudioRecorder.shared
    @State private var samples: [Float] = []
    @Environment(\.dlAccent) private var accent

    private var isPlaying: Bool { recorder.isPlaying && recorder.currentlyPlayingURL == url }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if isPlaying {
                    recorder.stopPlaying()
                } else {
                    recorder.playRecording(url: url)
                }
            } label: {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(DL.ink))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Stop" : "Play")

            TimelineView(.periodic(from: .now, by: isPlaying ? 0.1 : 3600)) { _ in
                let position = isPlaying ? recorder.playbackPosition : nil
                let total = position?.duration ?? duration
                let progress = total > 0 ? (position?.current ?? 0) / total : 0
                HStack(spacing: 12) {
                    GeometryReader { geo in
                        WaveformBars(samples: samples, progress: progress, barWidth: 2.5, spacing: 2,
                                     inactiveColor: accent.color.opacity(0.25))
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                let fraction = max(0, min(1, location.x / geo.size.width))
                                if !isPlaying { recorder.playRecording(url: url) }
                                recorder.seekPlayback(toFraction: fraction)
                            }
                    }
                    .frame(height: 30)
                    Text("\(TextUtil.formatDuration(position?.current ?? 0)) / \(TextUtil.formatDuration(total))")
                        .font(DL.mono(11, .medium))
                        .foregroundStyle(DL.sub)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DL.well.opacity(0.7)))
        .task(id: url) {
            samples = WaveformLoader.cached(url) ?? []
            samples = await WaveformLoader.load(url)
        }
    }
}
