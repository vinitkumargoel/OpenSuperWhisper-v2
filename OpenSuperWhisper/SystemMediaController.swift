import Darwin
import Foundation

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
    private typealias SendCommandFunction = @convention(c) (Int32, CFDictionary?) -> Void
    private typealias IsPlayingHandler = @convention(block) (Bool) -> Void
    private typealias GetIsPlayingFunction = @convention(c) (DispatchQueue, IsPlayingHandler) -> Void

    private enum Command {
        static let play: Int32 = 0
        static let pause: Int32 = 1
    }

    private let sendCommand: SendCommandFunction?
    private let getIsPlaying: GetIsPlayingFunction?
    private let callbackQueue = DispatchQueue(label: "app.opensuperwhisper.media-remote")

    init() {
        let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(frameworkPath, RTLD_LAZY) else {
            sendCommand = nil
            getIsPlaying = nil
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
    }

    func isMediaPlaying(timeout: TimeInterval) -> Bool {
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

    func pause() {
        sendCommand?(Command.pause, nil)
    }

    func play() {
        sendCommand?(Command.play, nil)
    }
}
