import CoreAudio
import Foundation

struct OutputVolumeSnapshot: Equatable {
    let deviceID: AudioDeviceID
    let channels: [UInt32: Float32]
}

protocol SystemVolumeBackend {
    func currentOutputVolume() -> OutputVolumeSnapshot?
    func setOutputVolume(_ volume: Float32, for snapshot: OutputVolumeSnapshot)
    func restoreOutputVolume(_ snapshot: OutputVolumeSnapshot)
}

final class SystemMediaController {
    static let shared = SystemMediaController()

    private let backend: SystemVolumeBackend
    private let lock = NSLock()
    private var recordingSessionID: UUID?
    private var capturedVolume: OutputVolumeSnapshot?

    init(backend: SystemVolumeBackend = CoreAudioVolumeBackend()) {
        self.backend = backend
    }

    func recordingDidStart(enabled: Bool) {
        let sessionID = UUID()

        lock.lock()
        recordingSessionID = sessionID
        capturedVolume = nil
        lock.unlock()

        guard enabled, let snapshot = backend.currentOutputVolume() else { return }

        lock.lock()
        let shouldMute = recordingSessionID == sessionID && capturedVolume == nil
        if shouldMute {
            capturedVolume = snapshot
        }
        lock.unlock()

        if shouldMute {
            backend.setOutputVolume(0, for: snapshot)
        }
    }

    func recordingDidStop() {
        lock.lock()
        let snapshot = capturedVolume
        recordingSessionID = nil
        capturedVolume = nil
        lock.unlock()

        if let snapshot {
            backend.restoreOutputVolume(snapshot)
        }
    }
}

final class CoreAudioVolumeBackend: SystemVolumeBackend {
    private let fallbackChannels: [UInt32] = [
        kAudioObjectPropertyElementMain,
        1,
        2
    ]

    func currentOutputVolume() -> OutputVolumeSnapshot? {
        guard let deviceID = defaultOutputDeviceID() else { return nil }

        var channels: [UInt32: Float32] = [:]
        for channel in fallbackChannels {
            if let volume = outputVolume(deviceID: deviceID, channel: channel) {
                channels[channel] = volume
            }
        }

        guard !channels.isEmpty else { return nil }
        return OutputVolumeSnapshot(deviceID: deviceID, channels: channels)
    }

    func setOutputVolume(_ volume: Float32, for snapshot: OutputVolumeSnapshot) {
        for channel in snapshot.channels.keys {
            setOutputVolume(deviceID: snapshot.deviceID, channel: channel, volume: volume)
        }
    }

    func restoreOutputVolume(_ snapshot: OutputVolumeSnapshot) {
        for (channel, volume) in snapshot.channels {
            setOutputVolume(deviceID: snapshot.deviceID, channel: channel, volume: volume)
        }
    }

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private func outputVolume(deviceID: AudioDeviceID, channel: UInt32) -> Float32? {
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = volumeAddress(channel: channel)

        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &volume
        )

        guard status == noErr else { return nil }
        return volume
    }

    private func setOutputVolume(deviceID: AudioDeviceID, channel: UInt32, volume: Float32) {
        var address = volumeAddress(channel: channel)
        var isSettable = DarwinBoolean(false)
        guard AudioObjectHasProperty(deviceID, &address),
              AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr,
              isSettable.boolValue else {
            return
        }

        var clampedVolume = min(max(volume, 0), 1)
        let size = UInt32(MemoryLayout<Float32>.size)

        AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            size,
            &clampedVolume
        )
    }

    private func volumeAddress(channel: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )
    }
}
