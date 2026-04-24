import CoreAudio
import Foundation

struct OutputVolumeSnapshot: Equatable {
    let deviceID: AudioDeviceID
    let volumes: [UInt32: Float32]
    let mutes: [UInt32: UInt32]
}

protocol SystemVolumeBackend {
    func currentOutputVolume() -> OutputVolumeSnapshot?
    func muteOutput(for snapshot: OutputVolumeSnapshot)
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
            backend.muteOutput(for: snapshot)
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

        var volumes: [UInt32: Float32] = [:]
        var mutes: [UInt32: UInt32] = [:]
        for channel in fallbackChannels {
            if let volume = outputVolume(deviceID: deviceID, channel: channel) {
                volumes[channel] = volume
            }
            if let mute = outputMute(deviceID: deviceID, channel: channel) {
                mutes[channel] = mute
            }
        }

        guard !volumes.isEmpty || !mutes.isEmpty else { return nil }
        return OutputVolumeSnapshot(deviceID: deviceID, volumes: volumes, mutes: mutes)
    }

    func muteOutput(for snapshot: OutputVolumeSnapshot) {
        for channel in snapshot.mutes.keys {
            setOutputMute(deviceID: snapshot.deviceID, channel: channel, muted: 1)
        }
        for channel in snapshot.volumes.keys {
            setOutputVolume(deviceID: snapshot.deviceID, channel: channel, volume: 0)
        }
    }

    func restoreOutputVolume(_ snapshot: OutputVolumeSnapshot) {
        for (channel, volume) in snapshot.volumes {
            setOutputVolume(deviceID: snapshot.deviceID, channel: channel, volume: volume)
        }
        for (channel, muted) in snapshot.mutes {
            setOutputMute(deviceID: snapshot.deviceID, channel: channel, muted: muted)
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

    private func outputMute(deviceID: AudioDeviceID, channel: UInt32) -> UInt32? {
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = muteAddress(channel: channel)

        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &muted
        )

        guard status == noErr else { return nil }
        return muted
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

    private func setOutputMute(deviceID: AudioDeviceID, channel: UInt32, muted: UInt32) {
        var address = muteAddress(channel: channel)
        var isSettable = DarwinBoolean(false)
        guard AudioObjectHasProperty(deviceID, &address),
              AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr,
              isSettable.boolValue else {
            return
        }

        var muteValue = muted
        let size = UInt32(MemoryLayout<UInt32>.size)

        AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            size,
            &muteValue
        )
    }

    private func volumeAddress(channel: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )
    }

    private func muteAddress(channel: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )
    }
}
