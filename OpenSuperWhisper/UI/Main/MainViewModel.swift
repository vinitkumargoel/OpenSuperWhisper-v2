import AVFoundation
import Combine
import KeyboardShortcuts
import SwiftUI

@MainActor
final class MainViewModel: ObservableObject {
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
    /// The library slice being shown. Applied in the database.
    @Published private(set) var filter: RecordingFilter = .all
    /// True totals per filter chip.
    @Published private(set) var counts: LibraryCounts = .empty
    /// Files and re-runs waiting for or going through transcription, oldest first.
    @Published private(set) var queue: [Recording] = []
    
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
        refreshCounts()
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
            let activeFilter = self.filter
            let newRecordings: [Recording]
            if query.isEmpty {
                newRecordings = (try? await recordingStore.fetchRecordings(limit: limit, offset: offset, filter: activeFilter)) ?? []
            } else {
                newRecordings = await recordingStore.searchRecordingsAsync(query: query, limit: limit, offset: offset, filter: activeFilter)
            }
            
            
            await MainActor.run {
                defer {
                    self.isLoadingMore = false
                }
                
                // Ensure we are still consistent with the request (basic check)
                guard self.currentSearchQuery == query, self.filter == activeFilter else {
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
    
    /// Re-reads the current page set after the store changed, keeping the
    /// active search and filter.
    func reload() {
        refreshCounts()
        currentPage = 0
        canLoadMore = true
        isLoadingMore = false
        loadMore()
    }

    func search(query: String) {
        currentSearchQuery = query
        currentPage = 0
        canLoadMore = true
        recordings = []
        loadMore()
    }
    
    func handleProgressUpdate(id: UUID, transcription: String?, progress: Float, status: RecordingStatus, errorMessage: String?? = nil, isRegeneration: Bool?) {
        if let index = queue.firstIndex(where: { $0.id == id }) {
            if status == .completed || status == .failed {
                queue.remove(at: index)
            } else {
                queue[index].progress = progress
                queue[index].status = status
            }
        } else if status != .completed && status != .failed {
            refreshQueue()
        }
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

    /// Reload the list for a different library slice.
    func setFilter(_ value: RecordingFilter) {
        guard value != filter else { return }
        filter = value
        currentPage = 0
        canLoadMore = true
        recordings = []
        loadMore()
    }

    func refreshCounts() {
        Task {
            let counts = await recordingStore.fetchLibraryCounts()
            self.counts = counts
        }
        refreshQueue()
    }

    func refreshQueue() {
        queue = recordingStore.getPendingRecordings()
    }

    func toggleStar(_ recording: Recording) {
        let newValue = !recording.isStarred
        recordingStore.setStarred(recording.id, newValue)
        if filter == .starred && !newValue {
            recordings.removeAll { $0.id == recording.id }
        } else if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
            recordings[index].isStarred = newValue
        }
    }
    
    func deleteAllRecordings(keepStarred: Bool) {
        recordingStore.deleteAllRecordings(keepStarred: keepStarred)
        if keepStarred {
            recordings.removeAll { !$0.isStarred }
        } else {
            recordings.removeAll()
        }
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

    /// Abandons the recording in progress: nothing is transcribed or saved.
    func cancelRecording() {
        guard state == .recording || state == .connecting else { return }
        recorder.cancelRecording()
        ModelResidency.shared.recordingDidCancel()
        state = .idle
        stopBlinking()
        stopDurationTimer()
        recordingDuration = 0
    }

    var isBusy: Bool {
        transcriptionService.isLoading || transcriptionService.isTranscribing || transcriptionQueue.isProcessing
            || state == .decoding || state == .formatting
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
