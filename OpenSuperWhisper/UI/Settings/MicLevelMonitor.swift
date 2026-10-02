import AVFoundation
import AudioToolbox
import Combine
import CoreAudio

/// Listens to the chosen microphone while Settings › Audio is open, so the user
/// can see their level without recording anything. Never writes audio.
@MainActor
final class MicLevelMonitor: ObservableObject {
    enum State: Equatable {
        case idle
        case running
        case noPermission
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// Recent levels (0…1), oldest first.
    @Published private(set) var history: [Float] = Array(repeating: 0, count: 48)

    private var engine: AVAudioEngine?

    var recentPeak: Float { history.suffix(16).max() ?? 0 }

    func start() {
        guard engine == nil else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    if granted { self.start() } else { self.state = .noPermission }
                }
            }
            return
        default:
            state = .noPermission
            return
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        selectDevice(on: input)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            state = .failed("No input available")
            return
        }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            let level = Self.level(of: buffer)
            Task { @MainActor [weak self] in self?.push(level) }
        }
        do {
            try engine.start()
            self.engine = engine
            state = .running
        } catch {
            input.removeTap(onBus: 0)
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        state = .idle
        history = Array(repeating: 0, count: history.count)
    }

    func restart() {
        stop()
        start()
    }

    private func push(_ level: Float) {
        guard engine != nil else { return }
        history = Array((history + [level]).suffix(48))
    }

    /// Points the engine's input at the microphone the app records with.
    private func selectDevice(on input: AVAudioInputNode) {
        guard let device = MicrophoneService.shared.currentMicrophone,
              var deviceID = MicrophoneService.shared.getCoreAudioDeviceID(for: device),
              let unit = input.audioUnit else { return }
        AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    /// RMS mapped from -55…0 dBFS to 0…1.
    nonisolated private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += channel[i] * channel[i] }
        let rms = sqrt(sum / Float(count))
        let db = 20 * log10(max(rms, 0.000_001))
        return max(0, min(1, (db + 55) / 55))
    }
}
