import AppKit
import SwiftUI

/// Every recording, filtered by chips and search, grouped by day, with the
/// selected one open in a reading panel on the right.
struct LibraryView: View {
    @ObservedObject var viewModel: MainViewModel
    let searchQuery: String
    let clearSearch: () -> Void
    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var reformatErrors = ReformatErrorCenter.shared

    @State private var pendingDelete: Recording?
    @State private var showDeleteAll = false

    private var selected: Recording? {
        guard let id = router.selectedRecordingID else { return nil }
        return viewModel.recordings.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LibraryHeader(viewModel: viewModel, showDeleteAll: $showDeleteAll)
                .padding(.horizontal, 24)
                .padding(.top, 20)
            FilterChips(viewModel: viewModel)
                .padding(.top, 14)
            if !searchQuery.isEmpty {
                SearchBanner(query: searchQuery, count: viewModel.recordings.count, hasMore: viewModel.canLoadMore, clear: clearSearch)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            HStack(alignment: .top, spacing: 16) {
                grid
                if let selected {
                    RecordingDetailView(
                        recording: selected,
                        searchQuery: searchQuery,
                        actions: actions(for: selected),
                        onClose: { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { router.selectedRecordingID = nil } }
                    )
                    .id(selected.id)
                    .frame(width: 480)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.top, 12)
            .padding(.trailing, selected == nil ? 0 : 16)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: router.selectedRecordingID)
        }
        .onChange(of: viewModel.recordings.map(\.id)) { _, ids in
            // A deleted selection closes the panel.
            if let id = router.selectedRecordingID, !ids.contains(id), !viewModel.isLoadingMore {
                router.selectedRecordingID = nil
            }
        }
        .sheet(item: $pendingDelete) { recording in
            ConfirmDialog(
                icon: "trash",
                tint: DL.live,
                title: recording.isPending ? "Remove from the queue?" : "Delete this recording?",
                message: deleteMessage(for: recording),
                confirmTitle: recording.isPending ? "Remove" : "Delete",
                destructive: true,
                onCancel: { pendingDelete = nil },
                onConfirm: {
                    if AudioRecorder.shared.currentlyPlayingURL == recording.url { AudioRecorder.shared.stopPlaying() }
                    viewModel.deleteRecording(recording)
                    pendingDelete = nil
                }
            )
            .daylight()
        }
        .sheet(isPresented: $showDeleteAll) {
            DeleteAllDialog(total: viewModel.counts.all, starred: viewModel.counts.starred) { keepStarred in
                AudioRecorder.shared.stopPlaying()
                viewModel.deleteAllRecordings(keepStarred: keepStarred)
                router.selectedRecordingID = nil
                showDeleteAll = false
            } onCancel: {
                showDeleteAll = false
            }
            .daylight()
        }
        .alert("Reformatting failed", isPresented: Binding(get: { reformatErrors.message != nil }, set: { if !$0 { reformatErrors.message = nil } })) {
            Button("Open Formatting") { AppRouter.shared.openSettings(.formatting) }
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(reformatErrors.message ?? "")\nThe original transcript is unchanged.")
        }
    }

    // MARK: Grid

    @ViewBuilder
    private var grid: some View {
        if viewModel.recordings.isEmpty && !viewModel.isLoadingMore {
            VStack {
                Spacer()
                if searchQuery.isEmpty {
                    DLEmptyState(icon: viewModel.filter == .starred ? "star" : "waveform",
                                 title: viewModel.filter == .all ? "No recordings here yet" : "Nothing in \(viewModel.filter.title)",
                                 message: viewModel.filter == .all
                                    ? "\(HotkeyDescription.instruction) in any app, or drop audio files onto this window."
                                    : "Recordings show up here as soon as they match this filter.")
                } else {
                    DLEmptyState(icon: "magnifyingglass", title: "No results for “\(searchQuery)”",
                                 message: "Search looks through formatted and original text and app names. Try fewer words, or search inside one app.")
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18, pinnedViews: []) {
                    ForEach(dayGroups, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(group.title).font(DL.text(13.5, .semibold)).foregroundStyle(DL.ink)
                                Text(group.subtitle).font(DL.text(12)).foregroundStyle(DL.faint)
                            }
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(group.items) { recording in
                                    RecordingCard(
                                        recording: recording,
                                        isSelected: recording.id == router.selectedRecordingID,
                                        searchQuery: searchQuery,
                                        onSelect: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                                router.selectedRecordingID = recording.id
                                            }
                                        },
                                        onToggleStar: { viewModel.toggleStar(recording) },
                                        onRetry: { regenerate(recording) }
                                    )
                                    .contextMenu {
                                        RecordingContextMenu(recording: recording, actions: actions(for: recording))
                                    }
                                    .onAppear {
                                        if recording.id == viewModel.recordings.last?.id {
                                            viewModel.loadMore()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if viewModel.isLoadingMore {
                        HStack { Spacer(); DLSpinner(size: 16); Spacer() }.padding(.vertical, 8)
                    }
                }
                .padding(.leading, 24)
                .padding(.trailing, router.selectedRecordingID == nil ? 24 : 0)
                .padding(.bottom, 24)
            }
        }
    }

    private var columns: [GridItem] {
        let count = router.selectedRecordingID == nil ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
    }

    private struct DayGroup {
        let day: Date
        let title: String
        let subtitle: String
        let items: [Recording]
    }

    private var dayGroups: [DayGroup] {
        let calendar = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [Recording]] = [:]
        for recording in viewModel.recordings {
            let day = calendar.startOfDay(for: recording.timestamp)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(recording)
        }
        return order.map { day in
            let full = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
            let title: String
            let subtitle: String
            if calendar.isDateInToday(day) {
                title = "Today"; subtitle = full
            } else if calendar.isDateInYesterday(day) {
                title = "Yesterday"; subtitle = full
            } else {
                title = day.formatted(.dateTime.weekday(.wide))
                subtitle = day.formatted(.dateTime.day().month(.wide).year())
            }
            let items = buckets[day] ?? []
            return DayGroup(day: day, title: title, subtitle: "\(subtitle) · \(items.count)", items: items)
        }
    }

    // MARK: Actions

    private func actions(for recording: Recording) -> RecordingActions {
        RecordingActions(
            toggleStar: { viewModel.toggleStar(recording) },
            regenerate: { regenerate(recording) },
            reformatWithCurrentSettings: { ReformatErrorCenter.shared.reformatWithCurrentSettings(recording) },
            requestDelete: { pendingDelete = recording }
        )
    }

    private func regenerate(_ recording: Recording) {
        Task { await TranscriptionQueue.shared.requeueRecording(recording) }
    }

    private func deleteMessage(for recording: Recording) -> String {
        if recording.isPending {
            return "Transcription stops and the audio copy is deleted. The original file is not touched."
        }
        let snippet = recording.displayTranscription.prefix(60)
        let quote = snippet.isEmpty ? "This recording" : "“\(snippet)\(recording.displayTranscription.count > 60 ? "…" : "")”"
        var parts = ["\(quote) · \(TextUtil.formatDuration(recording.duration))"]
        if let app = recording.targetAppName, !app.isEmpty { parts.append("from \(app)") }
        return parts.joined(separator: " ") + ". The audio file is removed too. Your statistics are kept."
    }
}

// MARK: - Header

private struct LibraryHeader: View {
    @ObservedObject var viewModel: MainViewModel
    @Binding var showDeleteAll: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Library").font(DL.display(28)).foregroundStyle(DL.ink)
            Text(viewModel.counts.all == 1 ? "1 recording" : "\(viewModel.counts.all.formatted()) recordings")
                .font(DL.text(13))
                .foregroundStyle(DL.faint)
            Spacer()
            Button {
                (NSApp.delegate as? AppDelegate)?.importAudioFiles()
            } label: {
                Label("Import audio", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.dlSecondary)
            .help("Transcribe audio files (⌘O)")

            Menu {
                Section("Export \(viewModel.counts.all.formatted()) transcripts as") {
                    ForEach(TranscriptExportFormat.allCases) { format in
                        Button(format.displayName) { LibraryExport.run(format) }
                    }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(DL.text(13, .semibold))
                    .foregroundStyle(DL.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: DL.radiusSmall).fill(DL.card))
                    .overlay(RoundedRectangle(cornerRadius: DL.radiusSmall).strokeBorder(DL.line, lineWidth: 1))
            }
            .menuStyle(.button).buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(viewModel.counts.all == 0)
            .help("Export all transcriptions")

            Menu {
                Button("Import Audio Files…") { (NSApp.delegate as? AppDelegate)?.importAudioFiles() }
                Button("Show Recordings in Finder") {
                    NSWorkspace.shared.open(Recording.recordingsDirectory)
                }
                Button("Open Insights") { AppRouter.shared.show(.insights) }
                Divider()
                Button("Delete All Recordings…", role: .destructive) { showDeleteAll = true }
                    .disabled(viewModel.counts.all == 0)
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(DL.sub)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: DL.radiusSmall).fill(DL.card))
                    .overlay(RoundedRectangle(cornerRadius: DL.radiusSmall).strokeBorder(DL.line, lineWidth: 1))
            }
            .menuStyle(.button).buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .labelStyle(CompactLabelStyle())
    }
}

/// Writes every completed transcript to a file the user picks.
enum LibraryExport {
    @MainActor
    static func run(_ format: TranscriptExportFormat) {
        Task {
            let recordings = await RecordingStore.shared.fetchAllForExport()
            let content = TranscriptExporter.serialize(recordings, format: format)
            await MainActor.run {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [format.contentType]
                panel.nameFieldStringValue = "transcriptions.\(format.fileExtension)"
                panel.canCreateDirectories = true
                panel.title = "Export Transcriptions"
                if panel.runModal() == .OK, let url = panel.url {
                    do {
                        try content.write(to: url, atomically: true, encoding: .utf8)
                    } catch {
                        print("Failed to export transcriptions: \(error)")
                    }
                }
            }
        }
    }
}

// MARK: - Filter chips

private struct FilterChips: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(.all, icon: "tray.full")
                chip(.recent, icon: "clock")
                chip(.starred, icon: "star")
                if !viewModel.counts.apps.isEmpty {
                    Rectangle().fill(DL.line).frame(width: 1, height: 18).padding(.horizontal, 4)
                    ForEach(viewModel.counts.apps, id: \.name) { app in
                        DLChip(title: app.name, count: app.count, dot: AppColors.color(for: app.name),
                               selected: viewModel.filter == .app(app.name)) {
                            select(.app(app.name))
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func chip(_ filter: RecordingFilter, icon: String) -> some View {
        DLChip(title: filter.title, count: viewModel.counts.count(for: filter), icon: icon,
               selected: viewModel.filter == filter) {
            select(filter)
        }
    }

    private func select(_ filter: RecordingFilter) {
        AppRouter.shared.selectedRecordingID = nil
        viewModel.setFilter(filter)
    }
}

private struct SearchBanner: View {
    let query: String
    let count: Int
    let hasMore: Bool
    let clear: () -> Void
    @Environment(\.dlAccent) private var accent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold))
            Text(count == 0 ? "No results for “\(query)”" : "\(count)\(hasMore ? "+" : "") result\(count == 1 ? "" : "s") for “\(query)”")
                .font(DL.text(12.5, .semibold))
            Spacer()
            Button("Clear search", action: clear)
                .buttonStyle(.plain)
                .font(DL.text(12.5, .semibold))
        }
        .foregroundStyle(accent.color)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10).fill(accent.softer))
    }
}
