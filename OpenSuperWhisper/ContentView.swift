//
//  ContentView.swift
//  OpenSuperWhisper
//
//  Created by user on 05.02.2025.
//

import AVFoundation
import Combine
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

@MainActor
class ContentViewModel: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var isBlinking = false
    @Published var recorder: AudioRecorder = .shared
    @Published var transcriptionService = TranscriptionService.shared
    @Published var transcriptionQueue = TranscriptionQueue.shared
    @Published var recordingStore = RecordingStore.shared
    @Published var recordings: [Recording] = []
    @Published var isLoadingMore = false
    @Published var canLoadMore = true
    @Published var recordingDuration: TimeInterval = 0
    @Published var microphoneService = MicrophoneService.shared
    @Published var shouldClearSearch = false
    @Published var starredOnly = false
    
    private var currentPage = 0
    private let pageSize = 100
    private var currentSearchQuery = ""
    private var blinkTimer: Timer?
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        recorder.$isConnecting
            .receive(on: RunLoop.main)
            .sink { [weak self] isConnecting in
                guard let self = self else { return }
                if isConnecting && self.state != .decoding && self.state != .formatting {
                    self.state = .connecting
                    self.stopBlinking()
                    self.stopDurationTimer()
                    self.recordingDuration = 0
                }
            }
            .store(in: &cancellables)
        
        recorder.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] isRecording in
                guard let self = self else { return }
                if isRecording && self.state != .decoding && self.state != .formatting {
                    self.state = .recording
                    self.startBlinking()
                    self.startDurationTimerIfNeeded()
                } else if !isRecording && self.state == .recording {
                    self.state = .idle
                    self.stopBlinking()
                    self.stopDurationTimer()
                    self.recordingDuration = 0
                }
            }
            .store(in: &cancellables)
    }
    
    func loadInitialData() {
        currentSearchQuery = ""
        currentPage = 0
        canLoadMore = true
        recordings = []
        loadMore()
    }

    func loadMore() {
        guard !isLoadingMore && canLoadMore else { return }
        isLoadingMore = true
        
        // Capture current state for async task
        let page = currentPage
        let limit = pageSize
        let query = currentSearchQuery
        let offset = page * limit
        
        
        Task {
            let onlyStarred = self.starredOnly
            let newRecordings: [Recording]
            if query.isEmpty {
                newRecordings = try await recordingStore.fetchRecordings(limit: limit, offset: offset, starredOnly: onlyStarred)
            } else {
                newRecordings = await recordingStore.searchRecordingsAsync(query: query, limit: limit, offset: offset, starredOnly: onlyStarred)
            }
            
            
            await MainActor.run {
                defer {
                    self.isLoadingMore = false
                }
                
                // Ensure we are still consistent with the request (basic check)
                guard self.currentSearchQuery == query, self.starredOnly == onlyStarred else {
                    return
                }
                
                if page == 0 {
                    self.recordings = newRecordings
                } else {
                    self.recordings.append(contentsOf: newRecordings)
                }
                
                if newRecordings.count < limit {
                    self.canLoadMore = false
                } else {
                    self.currentPage += 1
                }
            }
        }
    }
    
    func search(query: String) {
        currentSearchQuery = query
        currentPage = 0
        canLoadMore = true
        recordings = []
        loadMore()
    }
    
    func handleProgressUpdate(id: UUID, transcription: String?, progress: Float, status: RecordingStatus, errorMessage: String?? = nil, isRegeneration: Bool?) {
        if let index = recordings.firstIndex(where: { $0.id == id }) {
            if let transcription = transcription {
                recordings[index].transcription = transcription
            }
            if let errorMessage {
                recordings[index].errorMessage = errorMessage
            }
            recordings[index].progress = progress
            recordings[index].status = status
            if let isRegeneration = isRegeneration {
                recordings[index].isRegeneration = isRegeneration
            }
        }
    }
    
    func deleteRecording(_ recording: Recording) {
        recordingStore.deleteRecording(recording)
        if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
            recordings.remove(at: index)
        }
    }

    /// Reload the list when the Starred-only filter toggles.
    func setStarredOnly(_ value: Bool) {
        starredOnly = value
        currentPage = 0
        canLoadMore = true
        recordings = []
        loadMore()
    }

    func toggleStar(_ recording: Recording) {
        let newValue = !recording.isStarred
        recordingStore.setStarred(recording.id, newValue)
        if starredOnly && !newValue {
            recordings.removeAll { $0.id == recording.id }
        } else if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
            recordings[index].isStarred = newValue
        }
    }
    
    func deleteAllRecordings() {
        recordingStore.deleteAllRecordings()
        recordings.removeAll()
    }

    var isRecording: Bool {
        recorder.isRecording
    }
    
    func startRecording() {
        // Remember which app the user is dictating into, for per-app modes.
        FocusUtils.captureFrontmostApp()
        // Start loading the models now: the user is about to speak for several
        // seconds, which is exactly the window the load needs.
        ModelResidency.shared.recordingDidStart()
        if microphoneService.isActiveMicrophoneRequiresConnection() {
            state = .connecting
            stopBlinking()
            stopDurationTimer()
            recordingDuration = 0
        } else {
            state = .recording
            startBlinking()
            recordingStartTime = Date()
            recordingDuration = 0
            startDurationTimerIfNeeded()
        }
        
        Task.detached { [recorder] in
            recorder.startRecording()
        }
    }

    func startDecoding() {
        state = .decoding
        stopBlinking()
        stopDurationTimer()
        
        IndicatorWindowManager.shared.hide()

        if let tempURL = recorder.stopRecording() {
            Task { [weak self] in
                guard let self = self else { return }
                ModelResidency.shared.pipelineDidBegin()
                defer { ModelResidency.shared.pipelineDidFinish() }

                do {
                    print("start decoding...")
                    let rawText = try await transcriptionService.transcribeAudio(url: tempURL, settings: Settings())
                    ModelResidency.shared.transcriptionDidFinish()
                    var formattingError: Error?
                    let text = await FinalTextProcessor.formatIfNeeded(rawText) {
                        await MainActor.run {
                            self.state = .formatting
                        }
                    } onFormattingFailed: { error in
                        formattingError = error
                    }

                    // Capture the current recording duration
                    let duration = await MainActor.run { self.recordingDuration }
                    
                    // Create a new Recording instance
                    let timestamp = Date()
                    let fileName = "\(Int(timestamp.timeIntervalSince1970)).wav"
                    let recordingId = UUID()
                    let finalURL = Recording(
                        id: recordingId,
                        timestamp: timestamp,
                        fileName: fileName,
                        transcription: text,
                        rawTranscription: rawText,
                        duration: duration,
                        status: .completed,
                        progress: 1.0,
                        sourceFileURL: nil
                    ).url

                    // Move the temporary recording to final location
                    try recorder.moveTemporaryRecording(from: tempURL, to: finalURL)

                    // Save the recording to store
                    await MainActor.run {
                        let newRecording = Recording(
                            id: recordingId,
                            timestamp: timestamp,
                            fileName: fileName,
                            transcription: text,
                            rawTranscription: rawText,
                            duration: self.recordingDuration,
                            status: .completed,
                            progress: 1.0,
                            sourceFileURL: nil,
                            targetAppName: FocusUtils.lastFrontmostAppName,
                            targetAppBundleID: FocusUtils.lastFrontmostBundleID,
                            errorMessage: formattingError?.localizedDescription
                        )
                        self.recordingStore.addRecording(newRecording)
                        
                        // Clear search and show the new recording
                        if !self.currentSearchQuery.isEmpty {
                            self.shouldClearSearch = true
                            self.currentSearchQuery = ""
                        }
                        self.recordings.insert(newRecording, at: 0)
                    }

                    print("Transcription result: \(text)")
                } catch {
                    // Keep the audio and record the attempt so the user can hit
                    // Regenerate on the row instead of losing the dictation.
                    print("Error transcribing audio: \(error)")
                    let duration = await MainActor.run { self.recordingDuration }
                    await self.recordingStore.saveFailedRecording(
                        tempURL: tempURL,
                        duration: duration,
                        targetAppName: FocusUtils.lastFrontmostAppName,
                        targetAppBundleID: FocusUtils.lastFrontmostBundleID,
                        error: error
                    )
                    await MainActor.run { self.loadInitialData() }
                }

                await MainActor.run {
                    self.state = .idle
                    self.recordingDuration = 0
                }
            }
        } else {
            state = .idle
            recordingDuration = 0
            ModelResidency.shared.recordingDidCancel()
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
        recordingStartTime = nil
    }
    
    private func startDurationTimerIfNeeded() {
        guard durationTimer == nil else { return }
        if recordingStartTime == nil {
            recordingStartTime = Date()
            recordingDuration = 0
        }
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let startTime = Date()
            Task { @MainActor in
                if let recordingStartTime = self.recordingStartTime {
                    self.recordingDuration = startTime.timeIntervalSince(recordingStartTime)
                }
            }
        }
        RunLoop.main.add(durationTimer!, forMode: .common)
    }

    private func startBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.isBlinking.toggle()
            }
        }
        RunLoop.main.add(blinkTimer!, forMode: .common)
    }

    private func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        isBlinking = false
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @StateObject private var permissionsManager = PermissionsManager()
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSettingsPresented = false
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var showDeleteConfirmation = false
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var navSelection: LibraryFilter = .all
    @State private var selectedRecordingID: UUID?

    /// Left-rail library filters for the horizontal layout.
    enum LibraryFilter: Hashable {
        case all, recent, starred
        case app(String)
    }

    private var currentShortcutDescription: String {
        let modifierKey = ModifierKey(rawValue: AppPreferences.shared.modifierOnlyHotkey) ?? .none
        if modifierKey != .none {
            return modifierKey.shortSymbol
        } else if let shortcut = KeyboardShortcuts.getShortcut(for: .toggleRecord) {
            return shortcut.description
        }
        return ""
    }
    
    private func exportRecordings(format: TranscriptExportFormat) {
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

    private func performSearch(_ query: String) {
        searchTask?.cancel()
        
        if query.isEmpty {
            debouncedSearchText = ""
            viewModel.search(query: "")
            return
        }
        
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms debounce
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                self.debouncedSearchText = query
                viewModel.search(query: query)
            }
        }
    }

    // MARK: - Horizontal layout helpers

    /// Distinct target-app names present in the loaded recordings (for the "Apps" rail section).
    private var appModes: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for r in viewModel.recordings {
            if let a = r.targetAppName, !a.isEmpty, !seen.contains(a) {
                seen.insert(a)
                result.append(a)
            }
        }
        return result.sorted()
    }

    private func matches(_ r: Recording, _ f: LibraryFilter) -> Bool {
        switch f {
        case .all: return true
        case .recent: return r.timestamp > Date().addingTimeInterval(-2 * 24 * 3600)
        case .starred: return r.isStarred
        case .app(let name): return r.targetAppName == name
        }
    }

    private var displayedRecordings: [Recording] {
        viewModel.recordings.filter { matches($0, navSelection) }
    }

    private func libraryCount(_ f: LibraryFilter) -> Int {
        viewModel.recordings.filter { matches($0, f) }.count
    }

    private var navTitle: String {
        switch navSelection {
        case .all: return "All"
        case .recent: return "Recent"
        case .starred: return "Starred"
        case .app(let name): return name
        }
    }

    /// The recording shown in the detail pane: the tapped one, or the first in the current filter.
    private var effectiveSelection: Recording? {
        let list = displayedRecordings
        if let id = selectedRecordingID, let match = list.first(where: { $0.id == id }) {
            return match
        }
        return list.first
    }

    private func select(_ f: LibraryFilter) {
        navSelection = f
        selectedRecordingID = nil
    }

    @ViewBuilder
    private func railSectionLabel(_ text: String) -> some View {
        HStack {
            Text(text.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundColor(.secondary.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal, 9)
        .padding(.top, 11)
        .padding(.bottom, 4)
    }

    private var sidebarRail: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(SettingsTheme.accentGradient)
                        .frame(width: 28, height: 28)
                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                Text("SuperWhisper")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)
            .padding(.bottom, 10)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) {
                    railSectionLabel("Library")
                    RailItem(icon: "line.3.horizontal", title: "All", count: libraryCount(.all), isSelected: navSelection == .all) { select(.all) }
                    RailItem(icon: "clock", title: "Recent", count: libraryCount(.recent), isSelected: navSelection == .recent) { select(.recent) }
                    RailItem(icon: "star", title: "Starred", count: libraryCount(.starred), isSelected: navSelection == .starred) { select(.starred) }

                    if !appModes.isEmpty {
                        railSectionLabel("Apps")
                        ForEach(appModes, id: \.self) { app in
                            RailItem(icon: "macwindow", title: app, count: libraryCount(.app(app)), isSelected: navSelection == .app(app)) { select(.app(app)) }
                        }
                    }
                }
                .padding(.horizontal, 3)
            }

            Spacer(minLength: 8)

            Divider().padding(.vertical, 6)

            HStack(spacing: 8) {
                MicrophonePickerIconView(microphoneService: viewModel.microphoneService)

                if !viewModel.recordings.isEmpty {
                    Menu {
                        ForEach(TranscriptExportFormat.allCases) { format in
                            Button(format.displayName) { exportRecordings(format: format) }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14))
                            .foregroundColor(SettingsTheme.accent)
                            .frame(width: 30, height: 30)
                            .background(ThemePalette.panelSurface(colorScheme))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ThemePalette.panelBorder(colorScheme), lineWidth: 1))
                            .cornerRadius(8)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Export all transcriptions")

                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .frame(width: 30, height: 30)
                            .background(ThemePalette.panelSurface(colorScheme))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ThemePalette.panelBorder(colorScheme), lineWidth: 1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .help("Delete all recordings")
                    .confirmationDialog("Delete All Recordings", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                        Button("Delete All", role: .destructive) { viewModel.deleteAllRecordings() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Are you sure you want to delete all recordings? This action cannot be undone.")
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)

            RailItem(icon: "gearshape", title: "Settings", count: nil, isSelected: false) {
                isSettingsPresented = true
            }

            railRecordButton
                .padding(.top, 6)
        }
        .padding(10)
        .frame(width: 178)
        .background(ThemePalette.panelSurface(colorScheme))
    }

    private var railRecordButton: some View {
        Button {
            if viewModel.isRecording {
                viewModel.startDecoding()
            } else {
                viewModel.startRecording()
            }
        } label: {
            HStack(spacing: 7) {
                if viewModel.state == .decoding || viewModel.state == .formatting || viewModel.state == .connecting {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Working…")
                } else if viewModel.isRecording {
                    Image(systemName: "stop.fill")
                    Text("Stop")
                } else {
                    Image(systemName: "mic.fill")
                    Text("Record")
                }
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                Group {
                    if viewModel.isRecording {
                        LinearGradient(
                            colors: [Color(red: 1, green: 0.37, blue: 0.43), Color(red: 1, green: 0.23, blue: 0.34)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    } else {
                        SettingsTheme.accentGradient
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.transcriptionService.isLoading || viewModel.transcriptionService.isTranscribing || viewModel.transcriptionQueue.isProcessing || viewModel.state == .decoding || viewModel.state == .formatting)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isRecording)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.state)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundColor(SettingsTheme.accent)
            TextField("Search in transcriptions", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .onChange(of: searchText) { _, newValue in performSearch(newValue) }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    debouncedSearchText = ""
                    searchTask?.cancel()
                    viewModel.search(query: "")
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(ThemePalette.panelSurface(colorScheme))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ThemePalette.panelBorder(colorScheme), lineWidth: 1))
        .cornerRadius(10)
    }

    private var listEmptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: debouncedSearchText.isEmpty ? "waveform" : "magnifyingglass")
                .font(.system(size: 30))
                .foregroundColor(.secondary.opacity(0.5))
            Text(debouncedSearchText.isEmpty ? "No recordings here yet" : "No results found")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var recordingsListColumn: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(navTitle).font(.system(size: 16, weight: .bold))
                    Text("^[\(displayedRecordings.count) recording](inflect: true)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 9)

            searchField
                .padding(.horizontal, 12)
                .padding(.bottom, 9)

            if displayedRecordings.isEmpty {
                listEmptyState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 5) {
                        ForEach(displayedRecordings) { r in
                            CompactRecordingCard(
                                recording: r,
                                isSelected: effectiveSelection?.id == r.id,
                                onSelect: { selectedRecordingID = r.id },
                                onToggleStar: { viewModel.toggleStar(r) }
                            )
                            .onAppear {
                                if r.id == viewModel.recordings.last?.id {
                                    viewModel.loadMore()
                                }
                            }
                        }
                        if viewModel.isLoadingMore {
                            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.bottom, 10)
                }
            }
        }
        .frame(width: 300)
        .background(ThemePalette.cardBackground(colorScheme))
    }

    private var detailColumn: some View {
        Group {
            if let rec = effectiveSelection {
                ScrollView(showsIndicators: false) {
                    RecordingRow(
                        recording: rec,
                        searchQuery: debouncedSearchText,
                        onDelete: { viewModel.deleteRecording(rec) },
                        onRegenerate: {
                            Task { await TranscriptionQueue.shared.requeueRecording(rec) }
                        },
                        onToggleStar: { viewModel.toggleStar(rec) },
                        forceActionsVisible: true
                    )
                    .id(rec.id)
                    .padding(18)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.circle")
                        .font(.system(size: 46))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("Select a recording")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemePalette.windowBackground(colorScheme))
    }

    var body: some View {
        VStack {
            if !permissionsManager.isMicrophonePermissionGranted
                || !permissionsManager.isAccessibilityPermissionGranted
            {
                PermissionsView(permissionsManager: permissionsManager)
            } else {
                HStack(spacing: 0) {
                    sidebarRail
                    Divider()
                    recordingsListColumn
                    Divider()
                    detailColumn
                }
            }
        }
        .frame(minWidth: 400, idealWidth: 400)
        .background(ThemePalette.windowBackground(colorScheme))
        .onAppear {
            viewModel.loadInitialData()
        }
        .onReceive(NotificationCenter.default.publisher(for: RecordingStore.recordingProgressDidUpdateNotification)) { notification in
            guard let userInfo = notification.userInfo,
                  let id = userInfo["id"] as? UUID,
                  let progress = userInfo["progress"] as? Float,
                  let status = userInfo["status"] as? RecordingStatus else { return }
            
            let transcription = userInfo["transcription"] as? String
            let isRegeneration = userInfo["isRegeneration"] as? Bool
            // Absent key = unchanged; NSNull = cleared.
            let errorMessage: String?? = userInfo["errorMessage"].map { $0 as? String }
            
            viewModel.handleProgressUpdate(
                id: id,
                transcription: transcription,
                progress: progress,
                status: status,
                errorMessage: errorMessage,
                isRegeneration: isRegeneration
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: RecordingStore.recordingsDidUpdateNotification)) { _ in
            viewModel.loadInitialData()
        }
        .overlay {
            let isPermissionsGranted = permissionsManager.isMicrophonePermissionGranted
                && permissionsManager.isAccessibilityPermissionGranted

            if viewModel.transcriptionService.isLoading && isPermissionsGranted {
                ZStack {
                    Color.black.opacity(0.3)
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading Whisper Model...")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                }
                .ignoresSafeArea()
            }
        }
        .fileDropHandler()
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            isSettingsPresented = true
        }
        .onChange(of: viewModel.shouldClearSearch) { _, shouldClear in
            if shouldClear {
                searchText = ""
                debouncedSearchText = ""
                searchTask?.cancel()
                viewModel.shouldClearSearch = false
            }
        }
    }
}

struct PermissionsView: View {
    @ObservedObject var permissionsManager: PermissionsManager

    var body: some View {
        VStack(spacing: 20) {
            Text("Required Permissions")
                .font(.title)
                .padding()

            PermissionRow(
                isGranted: permissionsManager.isMicrophonePermissionGranted,
                title: "Microphone Access",
                description: "Required for audio recording",
                action: {
                    permissionsManager.requestMicrophonePermissionOrOpenSystemPreferences()
                }
            )

            PermissionRow(
                isGranted: permissionsManager.isAccessibilityPermissionGranted,
                title: "Accessibility Access",
                description: "Required for global keyboard shortcuts",
                action: { permissionsManager.openSystemPreferences(for: .accessibility) }
            )

            Spacer()
        }
        .padding()
    }
}

struct PermissionRow: View {
    let isGranted: Bool
    let title: String
    let description: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isGranted ? .green : .red)

                Text(title)
                    .font(.headline)

                Spacer()

                if !isGranted {
                    Button("Grant Access") {
                        action()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(ThemePalette.panelSurface(colorScheme))
        .cornerRadius(10)
    }
}

struct RecordingRow: View {
    let recording: Recording
    let searchQuery: String
    let onDelete: () -> Void
    let onRegenerate: () -> Void
    var onToggleStar: () -> Void = {}
    /// When true (detail pane), action buttons show without requiring hover.
    var forceActionsVisible: Bool = false
    @StateObject private var audioRecorder = AudioRecorder.shared
    @State private var showTranscription = false
    @State private var showRawTranscription = false
    @State private var isHovered = false
    @State private var showReformatPopover = false
    @State private var showReformatError = false
    @State private var reformatErrorMessage = ""
    @Environment(\.colorScheme) private var colorScheme

    private var isPlaying: Bool {
        audioRecorder.isPlaying && audioRecorder.currentlyPlayingURL == recording.url
    }

    /// Hover-gated actions are always visible when the row is used as a detail pane.
    private var actionsVisible: Bool { isHovered || forceActionsVisible }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var isPending: Bool {
        recording.status == .pending || recording.status == .converting || recording.status == .transcribing || recording.status == .formatting
    }
    
    private var isRegenerating: Bool {
        recording.isRegeneration && isPending
    }
    
    private var statusText: String {
        switch recording.status {
        case .pending:
            return "In queue..."
        case .converting:
            return "Converting..."
        case .transcribing:
            return "Transcribing..."
        case .formatting:
            return "Formatting..."
        case .completed:
            return ""
        case .failed:
            return "Failed"
        }
    }
    
    private var hasRawTranscription: Bool {
        guard let raw = recording.rawTranscription?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return false
        }
        return raw != recording.transcription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedTranscriptionText: String {
        if showRawTranscription, hasRawTranscription, let raw = recording.rawTranscription {
            return raw
        }
        return recording.transcription
    }

    private var displayText: String {
        let text = selectedTranscriptionText
        if text.isEmpty || text == "Starting transcription..." || text == "In queue..." {
            return ""
        }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isPending && !isRegenerating {
                VStack(alignment: .leading, spacing: 4) {
                    if let sourceFileName = recording.sourceFileName {
                        Text(sourceFileName)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    HStack(spacing: 6) {
                        if recording.status == .pending {
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                           
                            ZStack {
                                Circle()
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                                
                                Circle()
                                    .trim(from: 0, to: CGFloat(recording.progress))
                                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .animation(.linear(duration: 0.1), value: recording.progress)
                            }
                            .frame(width: 16, height: 16)

                            Text("\(Int(recording.progress * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                                .contentTransition(.numericText())
                                .animation(.linear(duration: 0.1), value: recording.progress)
                        }
                        
                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            
            if recording.status == .failed {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                        Text("Transcription failed")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    // Newer rows carry the reason in `errorMessage`; older ones
                    // had it written into `transcription`.
                    let reason = recording.errorMessage ?? recording.transcription
                    if !reason.isEmpty {
                        Text(reason)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // A failed run keeps whatever transcript was already there.
                    if recording.errorMessage != nil, !recording.transcription.isEmpty {
                        Text(recording.transcription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, isPending && !isRegenerating ? 4 : 8)
            } else if !displayText.isEmpty {
                if let warning = recording.errorMessage, !warning.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text("AI formatting didn't run: \(warning)")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }

                if hasRawTranscription {
                    HStack(spacing: 6) {
                        Picker("", selection: $showRawTranscription) {
                            Text("Formatted").tag(false)
                            Text("Original").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 170)

                        Text(showRawTranscription
                             ? "Straight from the transcription model"
                             : "After AI formatting")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }

                ZStack(alignment: .topLeading) {
                    TranscriptionView(
                        transcribedText: displayText,
                        searchQuery: searchQuery,
                        isExpanded: $showTranscription,
                        alwaysExpanded: forceActionsVisible
                    )
                    
                    if isRegenerating {
                        ShimmerOverlay()
                            .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, isPending && !isRegenerating ? 4 : 8)
            } else if !isPending {
                Text("No speech detected")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 14) {
              HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.timestamp, style: .date)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Text(recording.timestamp, style: .time)
                        Text("·")
                        Text(TextUtil.formatDuration(recording.duration))
                        Text("·")
                        Text("^[\(TextUtil.wordCount(recording.transcription)) word](inflect: true)")

                        if let appName = recording.targetAppName, !appName.isEmpty {
                            Text("·")
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 9))
                                Text(appName)
                                    .lineLimit(1)
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(SettingsTheme.accent)
                            .fixedSize()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(SettingsTheme.accent.opacity(0.12))
                            .clipShape(Capsule())
                            .help("Pasted into \(appName)")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                if isRegenerating {
                    Spacer()
                        .frame(width: 2)
                    HStack(spacing: 6) {
                        if recording.status == .pending {
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ZStack {
                                Circle()
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                                
                                Circle()
                                    .trim(from: 0, to: CGFloat(recording.progress))
                                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .animation(.linear(duration: 0.1), value: recording.progress)
                            }
                            .frame(width: 16, height: 16)

                            Text("\(Int(recording.progress * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                                .contentTransition(.numericText())
                                .animation(.linear(duration: 0.1), value: recording.progress)
                        }
                        
                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .transition(.opacity)

                }

                Spacer()
              }

              HStack(spacing: 20) {
                    if recording.status == .completed && (actionsVisible || recording.isStarred) {
                        Button(action: {
                            onToggleStar()
                        }) {
                            Image(systemName: recording.isStarred ? "star.fill" : "star")
                                .font(.system(size: 17))
                                .foregroundColor(recording.isStarred ? .yellow : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(recording.isStarred ? "Unstar" : "Star")
                        .transition(.opacity)
                    }

                    if !isPending && recording.status != .failed && (actionsVisible || isPlaying) {
                        Button(action: {
                            if isPlaying {
                                audioRecorder.stopPlaying()
                            } else {
                                audioRecorder.playRecording(url: recording.url)
                            }
                        }) {
                            Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(isPlaying ? .red : ThemePalette.iconAccent(colorScheme))
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)

                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(
                                selectedTranscriptionText, forType: .string
                            )
                        }) {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy entire text")
                        .transition(.opacity)
                    }

                    if recording.status == .completed && (actionsVisible || showReformatPopover) && !recording.transcription.isEmpty {
                        Button(action: {
                            showReformatPopover = true
                        }) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Reformat using your current formatting settings (no re-transcription)")
                        .transition(.opacity)
                        .popover(isPresented: $showReformatPopover, arrowEdge: .bottom) {
                            ReformatPopover { options in
                                Task {
                                    do {
                                        try await TranscriptionQueue.shared.reformatRecording(recording, options: options)
                                    } catch {
                                        reformatErrorMessage = error.localizedDescription
                                        showReformatError = true
                                    }
                                }
                            }
                        }
                    }

                    if (recording.status == .completed || recording.status == .failed) && actionsVisible {
                        Button(action: {
                            onRegenerate()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Regenerate transcription (full re-transcription)")
                        .transition(.opacity)
                    }

                    if actionsVisible || isPlaying || (isPending && !isRegenerating) || recording.status == .failed {
                        Button(action: {
                            if isPlaying {
                                audioRecorder.stopPlaying()
                            }
                            onDelete()
                        }) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isHovered)
                .animation(.easeInOut(duration: 0.2), value: isPlaying)
                .animation(.easeInOut(duration: 0.2), value: isRegenerating)
            }
            .animation(.easeInOut(duration: 0.2), value: isRegenerating)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .background(ThemePalette.cardBackground(colorScheme))
        }
        .background(ThemePalette.cardBackground(colorScheme))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ThemePalette.cardBorder(colorScheme), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            if recording.status == .completed {
                Button {
                    onToggleStar()
                } label: {
                    Label(recording.isStarred ? "Unstar" : "Star",
                          systemImage: recording.isStarred ? "star.slash" : "star")
                }
            }
            if !recording.transcription.isEmpty {
                Button {
                    copyToPasteboard(recording.transcription)
                } label: {
                    Label("Copy Text", systemImage: "doc.on.doc")
                }
            }
            if let raw = recording.rawTranscription, !raw.isEmpty, raw != recording.transcription {
                Button {
                    copyToPasteboard(raw)
                } label: {
                    Label("Copy Raw Transcript", systemImage: "doc.plaintext")
                }
            }
            if !isPending {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([recording.url])
                } label: {
                    Label("Reveal Audio in Finder", systemImage: "folder")
                }
            }
            if recording.status == .completed && !recording.transcription.isEmpty {
                Divider()
                // One-click path: reformat exactly as the live pipeline would,
                // no popover. The popover is for deviating from that.
                Button {
                    Task {
                        do {
                            try await TranscriptionQueue.shared.reformatRecording(
                                recording, options: .fromCurrentSettings()
                            )
                        } catch {
                            reformatErrorMessage = error.localizedDescription
                            showReformatError = true
                        }
                    }
                } label: {
                    Label("Reformat with Current Settings", systemImage: "wand.and.stars")
                }
            }
            if recording.status == .completed || recording.status == .failed {
                Divider()
                Button {
                    onRegenerate()
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
            }
            Divider()
            Button(role: .destructive) {
                if isPlaying { audioRecorder.stopPlaying() }
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .padding(.vertical, 4)
        .alert("Reformatting Failed", isPresented: $showReformatError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reformatErrorMessage)
        }
    }
}

struct ReformatPopover: View {
    /// Called with the settings to reformat under.
    let onReformat: (ReformatOptions) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var options = ReformatOptions.fromCurrentSettings()
    @State private var model: String = AppPreferences.shared.llmModel
    @State private var availableModels: [String] = []
    @State private var isFetching = false
    @State private var fetchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reformat")
                .font(.headline)

            Text("Re-runs formatting on the saved raw transcript. The audio is not re-transcribed, and the raw text is kept so you can compare or reformat again.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            // Pre-filled from the user's current settings — the point of the
            // button is to reproduce the live pipeline, not to re-specify it.
            Picker("", selection: $options.backend) {
                ForEach(FormattingBackend.allCases) { backend in
                    Text(backend.title).tag(backend)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if options.backend == .s1mini {
                Picker("Styling", selection: $options.styling) {
                    ForEach(S1Styling.allCases) { Text($0.title).tag($0) }
                }
                Picker("Structure", selection: $options.structure) {
                    ForEach(S1Structure.allCases) { Text($0.title).tag($0) }
                }
                Picker("Context", selection: $options.context) {
                    ForEach(S1Context.allCases) { Text($0.title).tag($0) }
                }

                Text(S1MiniModelManager.shared.isSelectedInstalled
                     ? "S1-mini by Superwhisper, on-device."
                     : "S1-mini is not downloaded — open Settings › Formatting first.")
                    .font(.caption)
                    .foregroundColor(S1MiniModelManager.shared.isSelectedInstalled ? .secondary : .orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    TextField("Model id", text: $model)
                        .textFieldStyle(.roundedBorder)

                    if !availableModels.isEmpty {
                        Picker("", selection: $model) {
                            ForEach(availableModels, id: \.self) { modelId in
                                Text(modelId).tag(modelId)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 130)
                    }

                    Button(isFetching ? "..." : "Fetch") {
                        fetchModels()
                    }
                    .disabled(isFetching)
                    .controlSize(.small)
                    .help("List models from the configured endpoint")
                }

                if let fetchError {
                    Text(fetchError)
                        .font(.caption)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Button("Reset to settings") {
                    options = ReformatOptions.fromCurrentSettings()
                    model = AppPreferences.shared.llmModel
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Spacer()

                Button("Reformat") {
                    var chosen = options
                    chosen.model = options.backend == .api ? model : nil
                    dismiss()
                    onReformat(chosen)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 340)
    }

    private func fetchModels() {
        isFetching = true
        fetchError = nil
        Task { @MainActor in
            defer { isFetching = false }
            do {
                availableModels = try await LLMTextFormatter.fetchAvailableModels(
                    baseURL: AppPreferences.shared.llmBaseURL,
                    apiKey: AppPreferences.shared.llmApiKey
                )
            } catch {
                fetchError = error.localizedDescription
            }
        }
    }
}

struct ShimmerOverlay: View {
    @State private var phase: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.clear,
                                    Color.white.opacity(0.4),
                                    Color.clear
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: -geometry.size.width + (phase * geometry.size.width * 2))
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .onAppear {
            withAnimation(
                .linear(duration: 1.2)
                .repeatForever(autoreverses: false)
            ) {
                phase = 1
            }
        }
    }
}

struct TranscriptionView: View {
    let transcribedText: String
    let searchQuery: String
    @Binding var isExpanded: Bool
    /// Detail-pane mode: render the full transcript with no truncation and no "Show more".
    var alwaysExpanded: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var highlightedAttributedString: AttributedString?
    @State private var computeTask: Task<Void, Never>?
    
    private var hasMoreLines: Bool {
        !transcribedText.isEmpty && transcribedText.count > 150
    }
    
    private var highlightedText: Text {
        guard !searchQuery.isEmpty else {
            return Text(transcribedText)
        }
        if let attributed = highlightedAttributedString {
            return Text(attributed)
        }
        return Text(transcribedText)
    }
    
    private func computeHighlighting() {
        computeTask?.cancel()
        
        guard !searchQuery.isEmpty else {
            highlightedAttributedString = nil
            return
        }
        
        let text = transcribedText
        let query = searchQuery
        
        computeTask = Task.detached(priority: .userInitiated) {
            var attributedString = AttributedString(text)
            let searchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
            
            var searchStartIndex = text.startIndex
            while let range = text.range(of: query, options: searchOptions, range: searchStartIndex..<text.endIndex) {
                guard !Task.isCancelled else { return }
                if let attributedRange = Range(range, in: attributedString) {
                    attributedString[attributedRange].backgroundColor = .yellow
                    attributedString[attributedRange].foregroundColor = .black
                }
                searchStartIndex = range.upperBound
            }
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                self.highlightedAttributedString = attributedString
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if alwaysExpanded {
                // Detail pane: show the whole transcript, no truncation, no toggle.
                highlightedText
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            } else {
                Group {
                    if isExpanded {
                        ScrollView {
                            highlightedText
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 200)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded {
                                    if hasMoreLines {
                                        isExpanded.toggle()
                                    }
                                }
                        )
                    } else {
                        if hasMoreLines {
                            Button(action: { isExpanded.toggle() }) {
                                highlightedText
                                    .font(.body)
                                    .lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .foregroundColor(.primary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            highlightedText
                                .font(.body)
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(8)

                if hasMoreLines {
                    Button(action: { isExpanded.toggle() }) {
                        HStack(spacing: 4) {
                            Text(isExpanded ? "Show less" : "Show more")
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        }
                        .foregroundColor(ThemePalette.linkText(colorScheme))
                        .font(.footnote)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
        .onAppear {
            computeHighlighting()
        }
        .onChange(of: searchQuery) { _, _ in
            computeHighlighting()
        }
        .onChange(of: transcribedText) { _, _ in
            computeHighlighting()
        }
        .onDisappear {
            computeTask?.cancel()
        }
    }
}

struct MicrophonePickerIconView: View {
    @ObservedObject var microphoneService: MicrophoneService
    @State private var showMenu = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var builtInMicrophones: [MicrophoneService.AudioDevice] {
        microphoneService.availableMicrophones.filter { $0.isBuiltIn }
    }
    
    private var externalMicrophones: [MicrophoneService.AudioDevice] {
        microphoneService.availableMicrophones.filter { !$0.isBuiltIn }
    }
    
    var body: some View {
        Button(action: {
            showMenu.toggle()
        }) {
            Image(systemName: microphoneService.availableMicrophones.isEmpty ? "mic.slash" : "mic.fill")
                .font(.title3)
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .background(ThemePalette.panelSurface(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ThemePalette.panelBorder(colorScheme), lineWidth: 1)
                )
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .help(microphoneService.currentMicrophone?.displayName ?? "Select microphone")
        .popover(isPresented: $showMenu, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                if microphoneService.availableMicrophones.isEmpty {
                    Text("No microphones available")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(builtInMicrophones) { microphone in
                        Button(action: {
                            microphoneService.selectMicrophone(microphone)
                            showMenu = false
                        }) {
                            HStack {
                                Text(microphone.displayName)
                                Spacer()
                                if let current = microphoneService.currentMicrophone,
                                   current.id == microphone.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if !builtInMicrophones.isEmpty && !externalMicrophones.isEmpty {
                        Divider()
                            .padding(.vertical, 4)
                    }
                    
                    ForEach(externalMicrophones) { microphone in
                        Button(action: {
                            microphoneService.selectMicrophone(microphone)
                            showMenu = false
                        }) {
                            HStack {
                                Text(microphone.displayName)
                                Spacer()
                                if let current = microphoneService.currentMicrophone,
                                   current.id == microphone.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minWidth: 200)
            .padding(.vertical, 8)
        }
    }
}

struct MainRecordButton: View {
    let isRecording: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var buttonColor: Color {
        ThemePalette.recordButtonBase(colorScheme)
    }

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        isRecording ? Color.red.opacity(0.8) : buttonColor.opacity(0.8),
                        isRecording ? Color.red : buttonColor.opacity(0.9)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 48, height: 48)
            .shadow(
                color: isRecording ? .red.opacity(0.5) : buttonColor.opacity(0.3),
                radius: 12,
                x: 0,
                y: 0
            )
            .overlay {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                isRecording ? .red.opacity(0.6) : buttonColor.opacity(0.6),
                                isRecording ? .red.opacity(0.3) : buttonColor.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .scaleEffect(isRecording ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isRecording)
    }
}

enum ThemePalette {
    static func windowBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(NSColor.underPageBackgroundColor)
            : .white
    }

    static func panelSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.gray.opacity(0.1)
            : Color(red: 0.95, green: 0.96, blue: 0.98)
    }

    static func panelBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.gray.opacity(0.2)
            : Color(red: 0.86, green: 0.88, blue: 0.92)
    }

    static func cardBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(NSColor.controlBackgroundColor)
            : Color.white
    }

    static func cardBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(NSColor.separatorColor)
            : Color(red: 0.86, green: 0.88, blue: 0.92)
    }

    static func recordButtonBase(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? .white
            : Color(red: 0.35, green: 0.60, blue: 0.92)
    }

    static func iconAccent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .accentColor : .primary
    }

    static func linkText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .blue : .primary
    }
}

// MARK: - Horizontal layout components

/// A left-rail navigation row: icon chip + title + optional count, highlighted when selected.
struct RailItem: View {
    let icon: String
    let title: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected
                              ? AnyShapeStyle(SettingsTheme.accentGradient)
                              : AnyShapeStyle(SettingsTheme.accent.opacity(0.12)))
                        .frame(width: 24, height: 24)
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isSelected ? .white : SettingsTheme.accent)
                }
                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? SettingsTheme.accent.opacity(0.13) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A compact recording entry for the middle list column: 2-line snippet + meta + star.
struct CompactRecordingCard: View {
    let recording: Recording
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleStar: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private var snippet: String {
        let t = recording.transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            return recording.status == .completed ? "No speech detected" : "Transcribing…"
        }
        return t
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                Text(snippet)
                    .font(.system(size: 12.5))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 5) {
                    if let app = recording.targetAppName, !app.isEmpty {
                        Text(app)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(SettingsTheme.accent)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(SettingsTheme.accent.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Text(recording.timestamp, format: .dateTime.month().day())
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("·").font(.system(size: 10)).foregroundColor(.secondary)
                    Text(TextUtil.formatDuration(recording.duration))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer(minLength: 2)
                    if recording.isStarred || isHovered {
                        Button(action: onToggleStar) {
                            Image(systemName: recording.isStarred ? "star.fill" : "star")
                                .font(.system(size: 11))
                                .foregroundColor(recording.isStarred ? .yellow : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected
                          ? SettingsTheme.accent.opacity(0.12)
                          : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? SettingsTheme.accent.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
