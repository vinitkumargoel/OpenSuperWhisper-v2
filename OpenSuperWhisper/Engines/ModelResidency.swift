import Foundation
import AppKit

/// Decides when the transcription model and the on-device formatter are in
/// memory.
///
/// The timing matters more than it looks. Loading a model costs one to two
/// seconds, and the obvious place to pay that — when you need the model — is
/// the worst one, because the user is sitting there waiting for their text.
/// Dictation gives us a much better window: the moment recording starts, we
/// know both models will be wanted, and we have as long as the user keeps
/// talking to get them ready. A ten-second dictation hides the load entirely.
///
/// The other half is giving the memory back. Neither model is loaded at app
/// launch, and both are released once the pipeline goes quiet, so idle
/// OpenSuperWhisper holds no model weights at all.
@MainActor
final class ModelResidency: ObservableObject {
    static let shared = ModelResidency()

    /// Number of transcribe-and-format pipelines in flight, so a release timer
    /// that fires late can't unload a model that is about to be used.
    ///
    /// Only `pipelineDidBegin`/`pipelineDidFinish` move this, and every caller
    /// pairs them with `defer` in one scope. Recording start deliberately does
    /// not increment: a recording can end in several ways, and a count that
    /// leaks once would wedge the app into never unloading again.
    private var pipelineDepth = 0

    private var transcriptionReleaseTimer: Timer?
    private var formatterReleaseTimer: Timer?
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    @Published private(set) var lastPrewarmStarted: Date?

    private init() {
        startMemoryPressureMonitor()
    }

    // MARK: - Policy

    /// `0` releases as soon as the work finishes; negative keeps models
    /// resident until the app quits.
    private var idleUnloadSeconds: TimeInterval {
        TimeInterval(AppPreferences.shared.modelIdleUnloadSeconds)
    }

    private var keepsModelsResident: Bool {
        AppPreferences.shared.modelIdleUnloadSeconds < 0
    }

    /// Only prewarm the formatter when it is actually going to run: AI
    /// formatting on, and the on-device backend selected.
    private var willUseLocalFormatter: Bool {
        AppPreferences.shared.formattingEnabled
            && AppPreferences.shared.formattingBackendValue == .s1mini
    }

    // MARK: - Pipeline events

    /// Called the instant recording begins. Both loads run concurrently and
    /// neither blocks the recorder.
    func recordingDidStart() {
        cancelReleaseTimers()

        guard AppPreferences.shared.prewarmModelsOnRecord else { return }
        lastPrewarmStarted = Date()

        TranscriptionService.shared.prewarm()

        if willUseLocalFormatter {
            Task { await S1MiniFormatter.shared.prewarm() }
        }
    }

    /// Recording was cancelled, or was too short to transcribe. Nothing else is
    /// coming, so start giving the memory back.
    func recordingDidCancel() {
        scheduleTranscriptionRelease()
        scheduleFormatterRelease()
    }

    /// A transcribe-and-format pipeline is starting. Always paired with
    /// `pipelineDidFinish` via `defer`.
    func pipelineDidBegin() {
        pipelineDepth += 1
        cancelReleaseTimers()
    }

    /// Transcription is done. When the idle timeout is zero this releases the
    /// ASR model before formatting begins, so the two models' memory peaks
    /// never overlap.
    func transcriptionDidFinish() {
        scheduleTranscriptionRelease()
    }

    /// The whole pipeline — transcribe, format, paste — has finished.
    func pipelineDidFinish() {
        pipelineDepth = max(0, pipelineDepth - 1)
        scheduleTranscriptionRelease()
        scheduleFormatterRelease()
    }

    // MARK: - Release

    private func scheduleTranscriptionRelease() {
        guard !keepsModelsResident else { return }
        transcriptionReleaseTimer?.invalidate()

        let delay = idleUnloadSeconds
        guard delay > 0 else {
            releaseTranscriptionIfIdle()
            return
        }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.releaseTranscriptionIfIdle() }
        }
        // .common so the timer still fires while a menu or drag tracking loop
        // is up — this is a menu-bar app, that happens constantly.
        RunLoop.main.add(timer, forMode: .common)
        transcriptionReleaseTimer = timer
    }

    private func scheduleFormatterRelease() {
        guard !keepsModelsResident else { return }
        formatterReleaseTimer?.invalidate()

        let delay = idleUnloadSeconds
        guard delay > 0 else {
            releaseFormatterIfIdle()
            return
        }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.releaseFormatterIfIdle() }
        }
        RunLoop.main.add(timer, forMode: .common)
        formatterReleaseTimer = timer
    }

    /// Gated on transcription specifically, not on the whole pipeline: the
    /// point of the zero-second setting is to hand the ASR weights back while
    /// formatting is still running, which a `pipelineDepth` check would block.
    private func releaseTranscriptionIfIdle() {
        transcriptionReleaseTimer?.invalidate()
        transcriptionReleaseTimer = nil
        guard !TranscriptionService.shared.isTranscribing else {
            print("[ModelResidency] transcription release skipped — still transcribing")
            return
        }
        TranscriptionService.shared.releaseEngine()
    }

    private func releaseFormatterIfIdle() {
        formatterReleaseTimer?.invalidate()
        formatterReleaseTimer = nil
        guard pipelineDepth == 0 else {
            print("[ModelResidency] formatter release skipped — \(pipelineDepth) in flight")
            return
        }
        Task {
            await S1MiniFormatter.shared.unload()
            print("[ModelResidency] S1-mini released")
        }
    }

    private func cancelReleaseTimers() {
        transcriptionReleaseTimer?.invalidate()
        transcriptionReleaseTimer = nil
        formatterReleaseTimer?.invalidate()
        formatterReleaseTimer = nil
    }

    // MARK: - Memory pressure

    /// When macOS says memory is tight, weights we are not mid-way through
    /// using are the cheapest thing in this app to give up — they reload in a
    /// second or two.
    private func startMemoryPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical], queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self, self.pipelineDepth == 0 else { return }
                print("[ModelResidency] memory pressure — releasing models")
                TranscriptionService.shared.releaseEngine()
                await S1MiniFormatter.shared.unload()
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    // MARK: - Diagnostics

    func residencySummary() async -> String {
        let asrLoaded = TranscriptionService.shared.isEngineLoaded
        let formatterLoaded = await S1MiniFormatter.shared.isLoaded
        switch (asrLoaded, formatterLoaded) {
        case (false, false): return "No models in memory"
        case (true, false): return "Transcription model in memory"
        case (false, true): return "S1-mini in memory"
        case (true, true): return "Transcription model and S1-mini in memory"
        }
    }
}
