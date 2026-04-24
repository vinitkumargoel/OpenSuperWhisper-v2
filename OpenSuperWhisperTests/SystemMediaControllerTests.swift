import XCTest
@testable import OpenSuperWhisper

final class SystemMediaControllerTests: XCTestCase {
    func testRecordingLifecycleWithPlayingMediaPausesAndResumes() {
        let backend = MockMediaCommandBackend(isPlaying: true)
        let controller = SystemMediaController(backend: backend)

        controller.recordingDidStart(enabled: true)
        controller.recordingDidStop()

        XCTAssertEqual(backend.pauseCallCount, 1)
        XCTAssertEqual(backend.playCallCount, 1)
    }

    func testRecordingLifecycleWithNoPlayingMediaDoesNotResumePlayback() {
        let backend = MockMediaCommandBackend(isPlaying: false)
        let controller = SystemMediaController(backend: backend)

        controller.recordingDidStart(enabled: true)
        controller.recordingDidStop()

        XCTAssertEqual(backend.pauseCallCount, 0)
        XCTAssertEqual(backend.playCallCount, 0)
    }

    func testCancelAfterPauseResumesPlayback() {
        let backend = MockMediaCommandBackend(isPlaying: true)
        let controller = SystemMediaController(backend: backend)

        controller.recordingDidStart(enabled: true)
        controller.recordingDidStop()

        XCTAssertEqual(backend.pauseCallCount, 1)
        XCTAssertEqual(backend.playCallCount, 1)
    }

    func testRepeatedStartDoesNotDoubleResume() {
        let backend = MockMediaCommandBackend(isPlaying: true)
        let controller = SystemMediaController(backend: backend)

        controller.recordingDidStart(enabled: true)
        controller.recordingDidStart(enabled: true)
        controller.recordingDidStop()

        XCTAssertEqual(backend.pauseCallCount, 2)
        XCTAssertEqual(backend.playCallCount, 1)
    }

    func testDisabledPreferenceDoesNotIssueMediaCommands() {
        let backend = MockMediaCommandBackend(isPlaying: true)
        let controller = SystemMediaController(backend: backend)

        controller.recordingDidStart(enabled: false)
        controller.recordingDidStop()

        XCTAssertEqual(backend.pauseCallCount, 0)
        XCTAssertEqual(backend.playCallCount, 0)
    }
}

private final class MockMediaCommandBackend: MediaCommandBackend {
    var isPlaying: Bool
    private(set) var pauseCallCount = 0
    private(set) var playCallCount = 0
    private(set) var isMediaPlayingCallCount = 0

    init(isPlaying: Bool) {
        self.isPlaying = isPlaying
    }

    func isMediaPlaying(timeout: TimeInterval) -> Bool {
        isMediaPlayingCallCount += 1
        return isPlaying
    }

    func pause() {
        pauseCallCount += 1
    }

    func play() {
        playCallCount += 1
    }
}
