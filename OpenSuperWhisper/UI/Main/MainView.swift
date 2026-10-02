import SwiftUI
import UniformTypeIdentifiers

/// The main window: a unified toolbar (tabs, search, Dictate, Settings) over
/// Home, Library or Insights, with the permission gate, model-loading and
/// file-drop states layered on top.
struct MainView: View {
    @StateObject private var viewModel = MainViewModel()
    @StateObject private var permissionsManager = PermissionsManager()
    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var transcriptionService = TranscriptionService.shared
    @ObservedObject private var dropHandler = FileDropHandler.shared

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    private var permissionsGranted: Bool {
        permissionsManager.isMicrophonePermissionGranted && permissionsManager.isAccessibilityPermissionGranted
    }

    var body: some View {
        VStack(spacing: 0) {
            MainToolbar(
                viewModel: viewModel,
                searchText: $searchText,
                searchFocused: $searchFocused,
                showsNavigation: permissionsGranted
            )
            Rectangle().fill(DL.line2).frame(height: 1)

            ZStack {
                if !permissionsGranted {
                    PermissionsGateView(permissionsManager: permissionsManager)
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DL.window)
        .overlay {
            if transcriptionService.isLoading && permissionsGranted {
                ModelLoadingOverlay()
                    .transition(.opacity)
            }
        }
        .overlay {
            if dropHandler.isDragging {
                DropOverlay()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: dropHandler.isDragging)
        .animation(.easeOut(duration: 0.2), value: transcriptionService.isLoading)
        .onDrop(of: [.audio], isTargeted: $dropHandler.isDragging) { providers in
            Task { await dropHandler.handleDrop(of: providers) }
            return true
        }
        .onAppear {
            viewModel.loadInitialData()
        }
        .onChange(of: searchText) { _, newValue in performSearch(newValue) }
        .onChange(of: router.focusSearchRequest) { _, _ in searchFocused = true }
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
            viewModel.reload()
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

    @ViewBuilder
    private var content: some View {
        switch router.tab {
        case .home:
            HomeView(viewModel: viewModel, searchQuery: debouncedSearchText, clearSearch: clearSearch)
        case .library:
            LibraryView(viewModel: viewModel, searchQuery: debouncedSearchText, clearSearch: clearSearch)
        case .insights:
            InsightsView()
        }
    }

    // MARK: - Search

    /// Typing searches the Library: the query is debounced, then run in the
    /// database against transcripts, raw transcripts and app names.
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
                if router.tab != .library { router.tab = .library }
            }
        }
    }

    private func clearSearch() {
        searchText = ""
        debouncedSearchText = ""
        searchTask?.cancel()
        viewModel.search(query: "")
    }
}
