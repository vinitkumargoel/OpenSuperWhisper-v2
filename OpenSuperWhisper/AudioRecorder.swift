import AVFoundation
import Foundation
import SwiftUI
import AppKit
import CoreAudio

class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var currentlyPlayingURL: URL?
    @Published var canRecord = false
    @Published var isConnecting = false
    /// Normalized microphone input level (0…1) while recording, for the UI meter.
    @Published var level: Float = 0

    private var audioRecorder: AVAudioRecorder?
    private var meteringTimer: DispatchSourceTimer?
    private var audioPlayer: AVAudioPlayer?
    private var notificationSound: NSSound?
    private let temporaryDirectory: URL
    private var currentRecordingURL: URL?
    private var notificationObserver: Any?
    private var microphoneChangeObserver: Any?
    private var connectionCheckTimer: DispatchSourceTimer?
    private var recordingDeviceID: AudioDeviceID?
    private let mediaController: SystemMediaController
    // Guards audioRecorder/currentRecordingURL/connectionCheckTimer/recordingDeviceID,
    // which are touched from the main thread, detached start tasks, and the
    // connection-monitoring timer on a global queue.
    private let stateLock = NSRecursiveLock()

    // MARK: - Singleton Instance

    static let shared = AudioRecorder()
    
    override private init() {
        let tempDir = FileManager.default.temporaryDirectory
        temporaryDirectory = tempDir.appendingPathComponent("temp_recordings")
        mediaController = .shared
        
        super.init()
        createTemporaryDirectoryIfNeeded()
        setup()
    }
    
    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = microphoneChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func setup() {
        updateCanRecordStatus()
        
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasConnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateCanRecordStatus()
        }
        
        NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateCanRecordStatus()
        }
        
        microphoneChangeObserver = NotificationCenter.default.addObserver(
            forName: .microphoneDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateCanRecordStatus()
        }
    }
    
    private func updateCanRecordStatus() {
        canRecord = MicrophoneService.shared.getActiveMicrophone() != nil
    }
    
    private func createTemporaryDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create temporary recordings directory: \(error)")
        }
    }
    
    private func playNotificationSound() {
        // Try to play using NSSound first
        guard let soundURL = Bundle.main.url(forResource: "notification", withExtension: "mp3") else {
            print("Failed to find notification sound file")
            // Fall back to system sound if notification.mp3 is not found
            NSSound.beep()
            return
        }
        
        if let sound = NSSound(contentsOf: soundURL, byReference: false) {
            // Set maximum volume to ensure it's audible
            sound.volume = 0.3
            sound.play()
            notificationSound = sound
        } else {
            print("Failed to create NSSound from URL, falling back to system beep")
            // Fall back to system beep if NSSound creation fails
            NSSound.beep()
        }
    }
    
    func startRecording() {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard canRecord else {
            print("Cannot start recording - no audio input available")
            return
        }

        if isRecording || isConnecting {
            print("stop recording while recording")
            _ = stopRecording()
        }

        mediaController.recordingDidStart(enabled: AppPreferences.shared.pauseMediaDuringRecording)
        
        if AppPreferences.shared.playSoundOnRecordStart {
            playNotificationSound()
        }
        
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "\(timestamp).wav"
        let fileURL = temporaryDirectory.appendingPathComponent(filename)
        currentRecordingURL = fileURL
        
        print("start record file to \(fileURL)")
        
        #if os(macOS)
        if let activeMic = MicrophoneService.shared.getActiveMicrophone() {
            _ = MicrophoneService.shared.setAsSystemDefaultInput(activeMic)
            print("Set system default input to: \(activeMic.displayName)")
            
            if let deviceID = MicrophoneService.shared.getCoreAudioDeviceID(for: activeMic) {
                recordingDeviceID = deviceID
            }
        }
        #endif
        
        let requiresConnection = MicrophoneService.shared.isActiveMicrophoneRequiresConnection()
        updateRecordingState(isRecording: false, isConnecting: requiresConnection)
        startRecordingWithRecorder(fileURL: fileURL, monitorConnection: requiresConnection)
    }
    
    private func startRecordingWithRecorder(fileURL: URL, monitorConnection: Bool) {
        stateLock.lock()
        defer { stateLock.unlock() }

        var channelCount = 1
        if let activeMic = MicrophoneService.shared.getActiveMicrophone() {
            channelCount = MicrophoneService.shared.getInputChannelCount(for: activeMic)
            print("Recording with \(channelCount) input channel(s) from \(activeMic.displayName)")
        }
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            startMetering()
            if monitorConnection {
                startConnectionMonitoring()
            } else {
                updateRecordingState(isRecording: true, isConnecting: false)
            }
            print("Recording started successfully")
        } catch {
            print("Failed to start recording: \(error)")
            currentRecordingURL = nil
            mediaController.recordingDidStop()
            updateRecordingState(isRecording: false, isConnecting: false)
        }
    }
    
    func stopRecording() -> URL? {
        stateLock.lock()
        defer { stateLock.unlock() }

        audioRecorder?.stop()
        mediaController.recordingDidStop()
        updateRecordingState(isRecording: false, isConnecting: false)
        stopConnectionMonitoring()
        stopMetering()

        if let url = currentRecordingURL,
           let duration = try? AVAudioPlayer(contentsOf: url).duration,
           duration < 1.0
        {
            try? FileManager.default.removeItem(at: url)
            currentRecordingURL = nil
            return nil
        }
        
        let url = currentRecordingURL
        currentRecordingURL = nil
        return url
    }
    
    func cancelRecording() {
        stateLock.lock()
        defer { stateLock.unlock() }

        audioRecorder?.stop()
        mediaController.recordingDidStop()
        updateRecordingState(isRecording: false, isConnecting: false)
        stopConnectionMonitoring()
        stopMetering()

        if let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentRecordingURL = nil
    }

    // MARK: - Input Level Metering

    private func startMetering() {
        stopMetering()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }

            self.stateLock.lock()
            let recorder = self.audioRecorder
            self.stateLock.unlock()

            guard let recorder = recorder, recorder.isRecording else { return }
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            self.level = Self.normalizedPower(power)
        }
        meteringTimer = timer
        timer.resume()
    }

    private func stopMetering() {
        meteringTimer?.cancel()
        meteringTimer = nil
        DispatchQueue.main.async { [weak self] in
            self?.level = 0
        }
    }

    /// Maps an average-power reading in dBFS to a 0…1 meter value.
    private static func normalizedPower(_ db: Float) -> Float {
        let floorDb: Float = -55
        if db < floorDb { return 0 }
        if db >= 0 { return 1 }
        return (db - floorDb) / (0 - floorDb)
    }
    
    
    func moveTemporaryRecording(from tempURL: URL, to finalURL: URL) throws {

        let directory = finalURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: finalURL)
    }
    
    func playRecording(url: URL) {
        // Stop current playback if any
        stopPlaying()
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
            currentlyPlayingURL = url
        } catch {
            print("Failed to play recording: \(error), url: \(url)")
            isPlaying = false
            currentlyPlayingURL = nil
        }
    }
    
    func stopPlaying() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentlyPlayingURL = nil
    }
    
    private func updateRecordingState(isRecording: Bool, isConnecting: Bool) {
        DispatchQueue.main.async {
            self.isRecording = isRecording
            self.isConnecting = isConnecting
        }
    }
    
    private func startConnectionMonitoring() {
        stateLock.lock()
        defer { stateLock.unlock() }

        stopConnectionMonitoring()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        let initialFileSize: Int64 = 4096
        var growthCount = 0

        timer.setEventHandler { [weak self] in
            guard let self = self else { return }

            self.stateLock.lock()
            guard self.audioRecorder != nil, let url = self.currentRecordingURL else {
                self.stateLock.unlock()
                return
            }
            self.stateLock.unlock()

            let currentFileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            let totalGrowth = currentFileSize - initialFileSize

            if totalGrowth > 8000 {
                growthCount += 1
            }

            if growthCount >= 2 {
                self.stopConnectionMonitoring()
                self.updateRecordingState(isRecording: true, isConnecting: false)
            }
        }
        connectionCheckTimer = timer
        timer.resume()
    }

    private func stopConnectionMonitoring() {
        stateLock.lock()
        defer { stateLock.unlock() }

        connectionCheckTimer?.cancel()
        connectionCheckTimer = nil
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            stateLock.lock()
            currentRecordingURL = nil
            stateLock.unlock()
        }
    }
}

extension AudioRecorder: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentlyPlayingURL = nil
    }
}
