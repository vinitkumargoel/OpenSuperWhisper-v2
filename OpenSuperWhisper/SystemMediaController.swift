import Darwin
import Foundation
import AppKit

protocol MediaCommandBackend {
    func isMediaPlaying(timeout: TimeInterval) -> Bool
    func pause()
    func play()
}

final class SystemMediaController {
    static let shared = SystemMediaController()

    private let backend: MediaCommandBackend
    private let lock = NSLock()
    private var recordingSessionID: UUID?
    private var pausedForCurrentRecording = false

    init(backend: MediaCommandBackend = MediaRemoteCommandBackend()) {
        self.backend = backend
    }

    func recordingDidStart(enabled: Bool) {
        let sessionID = UUID()

        lock.lock()
        recordingSessionID = sessionID
        pausedForCurrentRecording = false
        lock.unlock()

        guard enabled else { return }

        guard backend.isMediaPlaying(timeout: 0.25) else { return }

        lock.lock()
        let shouldPause = recordingSessionID == sessionID && !pausedForCurrentRecording
        if shouldPause {
            pausedForCurrentRecording = true
        }
        lock.unlock()

        if shouldPause {
            backend.pause()
        }
    }

    func recordingDidStop() {
        lock.lock()
        let shouldResume = pausedForCurrentRecording
        recordingSessionID = nil
        pausedForCurrentRecording = false
        lock.unlock()

        if shouldResume {
            backend.play()
        }
    }
}

final class MediaRemoteCommandBackend: MediaCommandBackend {
    private typealias SendCommandFunction = @convention(c) (Int32, CFDictionary?) -> Bool
    private typealias IsPlayingHandler = @convention(block) (Bool) -> Void
    private typealias GetIsPlayingFunction = @convention(c) (DispatchQueue, IsPlayingHandler) -> Void
    private typealias NowPlayingInfoHandler = @convention(block) (CFDictionary?) -> Void
    private typealias GetNowPlayingInfoFunction = @convention(c) (DispatchQueue, NowPlayingInfoHandler) -> Void

    private enum Command {
        static let play: Int32 = 0
        static let pause: Int32 = 1
    }

    private let sendCommand: SendCommandFunction?
    private let getIsPlaying: GetIsPlayingFunction?
    private let getNowPlayingInfo: GetNowPlayingInfoFunction?
    private let callbackQueue = DispatchQueue(label: "app.opensuperwhisper.media-remote")

    init() {
        let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(frameworkPath, RTLD_LAZY) else {
            sendCommand = nil
            getIsPlaying = nil
            getNowPlayingInfo = nil
            return
        }

        if let symbol = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendCommand = unsafeBitCast(symbol, to: SendCommandFunction.self)
        } else {
            sendCommand = nil
        }

        if let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            getIsPlaying = unsafeBitCast(symbol, to: GetIsPlayingFunction.self)
        } else {
            getIsPlaying = nil
        }

        if let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            getNowPlayingInfo = unsafeBitCast(symbol, to: GetNowPlayingInfoFunction.self)
        } else {
            getNowPlayingInfo = nil
        }
    }

    func isMediaPlaying(timeout: TimeInterval) -> Bool {
        if isNowPlayingApplicationPlaying(timeout: timeout) {
            return true
        }
        return nowPlayingInfoIndicatesPlayback(timeout: timeout)
    }

    func pause() {
        if sendCommand?(Command.pause, nil) != true {
            postPlayPauseMediaKey()
        }
    }

    func play() {
        if sendCommand?(Command.play, nil) != true {
            postPlayPauseMediaKey()
        }
    }

    private func isNowPlayingApplicationPlaying(timeout: TimeInterval) -> Bool {
        guard let getIsPlaying = getIsPlaying else { return false }

        let semaphore = DispatchSemaphore(value: 0)
        let resultLock = NSLock()
        var result = false

        let handler: IsPlayingHandler = { isPlaying in
            resultLock.lock()
            result = isPlaying
            resultLock.unlock()
            semaphore.signal()
        }

        getIsPlaying(callbackQueue, handler)

        let deadline = DispatchTime.now() + timeout
        guard semaphore.wait(timeout: deadline) == .success else { return false }

        resultLock.lock()
        let isPlaying = result
        resultLock.unlock()
        return isPlaying
    }

    private func nowPlayingInfoIndicatesPlayback(timeout: TimeInterval) -> Bool {
        guard let getNowPlayingInfo = getNowPlayingInfo else { return false }

        let semaphore = DispatchSemaphore(value: 0)
        let resultLock = NSLock()
        var result = false

        let handler: NowPlayingInfoHandler = { info in
            resultLock.lock()
            result = Self.isPlaying(info: info)
            resultLock.unlock()
            semaphore.signal()
        }

        getNowPlayingInfo(callbackQueue, handler)

        let deadline = DispatchTime.now() + timeout
        guard semaphore.wait(timeout: deadline) == .success else { return false }

        resultLock.lock()
        let isPlaying = result
        resultLock.unlock()
        return isPlaying
    }

    private static func isPlaying(info: CFDictionary?) -> Bool {
        guard let info = info as? [String: Any] else { return false }

        let playbackRateKeys = [
            "kMRMediaRemoteNowPlayingInfoPlaybackRate",
            "MRMediaRemoteNowPlayingInfoPlaybackRate",
            "PlaybackRate"
        ]

        for key in playbackRateKeys {
            if let rate = info[key] as? NSNumber {
                return rate.doubleValue > 0
            }
        }

        let playbackStateKeys = [
            "kMRMediaRemoteNowPlayingInfoPlaybackState",
            "MRMediaRemoteNowPlayingInfoPlaybackState",
            "PlaybackState"
        ]

        for key in playbackStateKeys {
            if let state = info[key] as? NSNumber {
                return state.intValue == 1
            }
        }

        return false
    }

    private func postPlayPauseMediaKey() {
        let playPauseKeyCode = 16
        postMediaKey(playPauseKeyCode, keyState: 0xA)
        postMediaKey(playPauseKeyCode, keyState: 0xB)
    }

    private func postMediaKey(_ keyCode: Int, keyState: Int) {
        let data1 = (keyCode << 16) | (keyState << 8)

        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )?.cgEvent else { return }

        event.post(tap: .cghidEventTap)
    }
}
