import AppKit
import SwiftUI

// MARK: - Shared recording helpers

extension Recording {
    var isFailed: Bool { status == .failed }
    var isRegenerating: Bool { isRegeneration && isPending }

    /// Raw transcript that differs from the formatted one.
    var distinctRawTranscription: String? {
        guard let raw = rawTranscription?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              raw != transcription.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return rawTranscription
    }

    /// Transcript text worth showing; placeholders written by older builds count as empty.
    var displayTranscription: String {
        let text = transcription
        if text.isEmpty || text == "Starting transcription..." || text == "In queue..." { return "" }
        return text
    }

    /// Completed recording whose AI formatting failed and raw text was kept.
    var formattingWarning: String? {
        guard status == .completed, let message = errorMessage, !message.isEmpty else { return nil }
        return message
    }

    var failureReason: String {
        // Newer rows carry the reason in `errorMessage`; older ones wrote it into `transcription`.
        errorMessage ?? (transcription.isEmpty ? "The transcription could not be completed." : transcription)
    }

    var wordCount: Int { TextUtil.wordCount(transcription) }

    var statusText: String {
        switch status {
        case .pending: return "In queue"
        case .converting: return "Converting…"
        case .transcribing: return "Transcribing…"
        case .formatting: return "Formatting…"
        case .completed: return ""
        case .failed: return "Failed"
        }
    }

    /// "Today at 10:42", "Yesterday at 16:47", "Mon 29 Sep at 20:13".
    var relativeTimestamp: String {
        let time = timestamp.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(timestamp) { return "Today at \(time)" }
        if calendar.isDateInYesterday(timestamp) { return "Yesterday at \(time)" }
        return "\(timestamp.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) at \(time)"
    }
}

/// What can be done to a recording, shared by the card's context menu and the
/// detail panel so the two never disagree.
struct RecordingActions {
    var toggleStar: () -> Void
    var regenerate: () -> Void
    var reformatWithCurrentSettings: () -> Void
    var requestDelete: () -> Void

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Right-click menu for a recording.
struct RecordingContextMenu: View {
    let recording: Recording
    let actions: RecordingActions

    var body: some View {
        if recording.status == .completed {
            Button {
                actions.toggleStar()
            } label: {
                Label(recording.isStarred ? "Unstar" : "Star", systemImage: recording.isStarred ? "star.slash" : "star")
            }
        }
        if !recording.transcription.isEmpty {
            Button {
                RecordingActions.copy(recording.transcription)
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }
        }
        if let raw = recording.distinctRawTranscription {
            Button {
                RecordingActions.copy(raw)
            } label: {
                Label("Copy Original Transcript", systemImage: "doc.plaintext")
            }
        }
        if !recording.isPending {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([recording.url])
            } label: {
                Label("Reveal Audio in Finder", systemImage: "folder")
            }
        }
        if recording.status == .completed && !recording.transcription.isEmpty {
            Divider()
            // One-click path: reformat exactly as the live pipeline would.
            Button {
                actions.reformatWithCurrentSettings()
            } label: {
                Label("Reformat with Current Settings", systemImage: "wand.and.stars")
            }
        }
        if recording.status == .completed || recording.status == .failed {
            Divider()
            Button {
                actions.regenerate()
            } label: {
                Label("Regenerate Transcript", systemImage: "arrow.clockwise")
            }
        }
        Divider()
        Button(role: .destructive) {
            actions.requestDelete()
        } label: {
            Label("Delete…", systemImage: "trash")
        }
    }
}

// MARK: - Card

/// One recording in the Library grid.
struct RecordingCard: View {
    let recording: Recording
    let isSelected: Bool
    let searchQuery: String
    let onSelect: () -> Void
    let onToggleStar: () -> Void
    var onRetry: () -> Void = {}
    @State private var hovering = false
    @Environment(\.dlAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            content
            Spacer(minLength: 0)
            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(recording.isFailed ? DL.liveSoft.opacity(0.35) : DL.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? accent.color : (hovering ? DL.line : DL.line2), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: isSelected ? accent.color.opacity(0.15) : DL.shadow, radius: isSelected ? 10 : 5, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            if let app = recording.targetAppName, !app.isEmpty {
                AppBadge(name: app)
            } else if let file = recording.sourceFileName {
                HStack(spacing: 5) {
                    Image(systemName: "waveform").font(.system(size: 10, weight: .semibold))
                    Text(file).lineLimit(1).truncationMode(.middle)
                }
                .font(DL.text(11.5, .semibold))
                .foregroundStyle(accent.color)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(accent.soft))
            } else {
                DLTag(text: "Dictated")
            }
            Spacer(minLength: 4)
            Text(recording.timestamp.formatted(date: .omitted, time: .shortened))
                .font(DL.mono(11, .medium))
                .foregroundStyle(DL.faint)
        }
    }

    @ViewBuilder
    private var content: some View {
        if recording.isRegenerating {
            SkeletonLines(lines: 3)
                .padding(.vertical, 3)
        } else if recording.isPending {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if recording.status == .pending {
                        Image(systemName: "clock").font(.system(size: 11))
                    } else {
                        DLSpinner(size: 11, lineWidth: 1.8)
                    }
                    Text(recording.statusText).font(DL.text(13, .semibold))
                    Spacer()
                    if recording.status != .pending {
                        Text("\(Int(recording.progress * 100))%").font(DL.mono(11.5, .semibold)).foregroundStyle(accent.color)
                    }
                }
                .foregroundStyle(DL.ink)
                if recording.status != .pending {
                    DLLinearProgress(progress: Double(recording.progress), height: 6)
                }
            }
        } else if recording.isFailed {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 11.5, weight: .semibold))
                    Text("Transcription failed").font(DL.text(13, .semibold))
                }
                .foregroundStyle(DL.live)
                Text(recording.failureReason)
                    .font(DL.text(12.5))
                    .foregroundStyle(DL.ink2)
                    .lineLimit(2)
            }
        } else if recording.displayTranscription.isEmpty {
            Text("No speech detected").font(DL.text(13).italic()).foregroundStyle(DL.faint)
        } else {
            HighlightedText(text: recording.displayTranscription, query: searchQuery)
                .font(DL.text(13))
                .foregroundStyle(DL.ink2)
                .lineSpacing(2.5)
                .lineLimit(3)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Label(TextUtil.formatDuration(recording.duration), systemImage: "timer")
            if recording.status == .completed {
                Text("\(recording.wordCount) words")
            }
            if recording.isRegenerating {
                HStack(spacing: 4) {
                    DLSpinner(size: 10, lineWidth: 1.6)
                    Text("Regenerating · \(Int(recording.progress * 100))%")
                }
                .foregroundStyle(accent.color)
            }
            if recording.isFailed {
                Text("Audio saved")
            }
            if recording.formattingWarning != nil {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Raw text")
                }
                .font(DL.text(10.5, .semibold))
                .foregroundStyle(DL.warn)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(RoundedRectangle(cornerRadius: 5).fill(DL.warnSoft))
                .help("AI formatting didn't run — this is the raw transcript")
            }
            Spacer(minLength: 0)
            if recording.isFailed {
                Button {
                    onRetry()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .font(DL.text(12, .semibold))
                .foregroundStyle(accent.color)
            } else if recording.status == .completed && (hovering || recording.isStarred || isSelected) {
                Button(action: onToggleStar) {
                    Image(systemName: recording.isStarred ? "star.fill" : "star")
                        .foregroundStyle(recording.isStarred ? DL.star : DL.faint)
                }
                .buttonStyle(.plain)
                .help(recording.isStarred ? "Unstar" : "Star")
            }
        }
        .font(DL.text(11.5))
        .foregroundStyle(DL.faint)
        .labelStyle(CompactLabelStyle())
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 10.5))
            configuration.title
        }
    }
}

// MARK: - Search highlighting

/// Text with every case- and diacritic-insensitive match of `query` washed in
/// the accent colour.
struct HighlightedText: View {
    let text: String
    let query: String
    @Environment(\.dlAccent) private var accent

    var body: some View {
        if query.isEmpty {
            Text(text)
        } else {
            Text(Self.highlight(text, query: query, background: accent.color.opacity(0.22)))
        }
    }

    static func highlight(_ text: String, query: String, background: Color) -> AttributedString {
        var attributed = AttributedString(text)
        var searchStart = text.startIndex
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        while let range = text.range(of: query, options: options, range: searchStart..<text.endIndex) {
            if let attributedRange = Range(range, in: attributed) {
                attributed[attributedRange].backgroundColor = background
            }
            searchStart = range.upperBound
        }
        return attributed
    }
}
