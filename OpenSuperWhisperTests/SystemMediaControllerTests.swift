import CoreAudio
import XCTest
@testable import OpenSuperWhisper

final class SystemMediaControllerTests: XCTestCase {
    func testRecordingLifecycleCapturesMutesAndRestoresVolume() {
        let snapshot = OutputVolumeSnapshot(deviceID: 42, volumes: [0: 0.7], mutes: [0: 0])
        let backend = MockSystemVolumeBackend(snapshot: snapshot)
        let controller = SystemMediaController(backend: backend)

        controller.recordingDidStart(enabled: true)
        controller.recordingDidStop()

        XCTAssertEqual(backend.currentVolumeCallCount, 1)
        XCTAssertEqual(backend.mutedSnapshots, [snapshot])
        XCTAssertEqual(backend.restoredSnapshots, [snapshot])
    }

    func testNoVolumeSnapshotDoesNotMuteOrRestore() {
        let backend = MockSystemVolumeBackend(snapshot: nil)
        let controller = SystemMediaController(backend: backend)

        controller.recordingDidStart(enabled: true)
        controller.recordingDidStop()

        XCTAssertEqual(backend.currentVolumeCallCount, 1)
        XCTAssertTrue(backend.mutedSnapshots.isEmpty)
        XCTAssertTrue(backend.restoredSnapshots.isEmpty)
    }

    func testStopWithoutStartDoesNotRestore() {
        let snapshot = OutputVolumeSnapshot(deviceID: 42, volumes: [0: 0.7], mutes: [0: 0])
        let backend = MockSystemVolumeBackend(snapshot: snapshot)
        let controller = SystemMediaController(backend: backend)

        controller.recordingDidStop()

        XCTAssertEqual(backend.currentVolumeCallCount, 0)
        XCTAssertTrue(backend.mutedSnapshots.isEmpty)
        XCTAssertTrue(backend.restoredSnapshots.isEmpty)
    }

    func testRepeatedStartRestoresOnlyLatestCapturedVolume() {
        let first = OutputVolumeSnapshot(deviceID: 42, volumes: [0: 0.7], mutes: [0: 0])
        let second = OutputVolumeSnapshot(deviceID: 42, volumes: [0: 0.4], mutes: [0: 0])
        let backend = MockSystemVolumeBackend(snapshots: [first, second])
        let controller = SystemMediaController(backend: backend)

        controller.recordingDidStart(enabled: true)
        controller.recordingDidStart(enabled: true)
        controller.recordingDidStop()

        XCTAssertEqual(backend.mutedSnapshots, [first, second])
        XCTAssertEqual(backend.restoredSnapshots, [second])
    }

    func testDisabledPreferenceDoesNotChangeVolume() {
        let snapshot = OutputVolumeSnapshot(deviceID: 42, volumes: [0: 0.7], mutes: [0: 0])
        let backend = MockSystemVolumeBackend(snapshot: snapshot)
        let controller = SystemMediaController(backend: backend)

        controller.recordingDidStart(enabled: false)
        controller.recordingDidStop()

        XCTAssertEqual(backend.currentVolumeCallCount, 0)
        XCTAssertTrue(backend.mutedSnapshots.isEmpty)
        XCTAssertTrue(backend.restoredSnapshots.isEmpty)
    }
}

private final class MockSystemVolumeBackend: SystemVolumeBackend {
    private var snapshots: [OutputVolumeSnapshot?]
    private(set) var currentVolumeCallCount = 0
    private(set) var mutedSnapshots: [OutputVolumeSnapshot] = []
    private(set) var restoredSnapshots: [OutputVolumeSnapshot] = []

    init(snapshot: OutputVolumeSnapshot?) {
        self.snapshots = [snapshot]
    }

    init(snapshots: [OutputVolumeSnapshot?]) {
        self.snapshots = snapshots
    }

    func currentOutputVolume() -> OutputVolumeSnapshot? {
        currentVolumeCallCount += 1
        if snapshots.isEmpty { return nil }
        return snapshots.removeFirst()
    }

    func muteOutput(for snapshot: OutputVolumeSnapshot) {
        mutedSnapshots.append(snapshot)
    }

    func restoreOutputVolume(_ snapshot: OutputVolumeSnapshot) {
        restoredSnapshots.append(snapshot)
    }
}
