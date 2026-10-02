import AVFoundation
import Foundation

/// Reads an audio file into a small array of peak levels (0…1) for drawing a
/// waveform. Results are cached per file.
enum WaveformLoader {
    private static let cache = NSCache<NSURL, NSArray>()

    static func cached(_ url: URL) -> [Float]? {
        (cache.object(forKey: url as NSURL) as? [NSNumber])?.map(\.floatValue)
    }

    static func load(_ url: URL, buckets: Int = 120) async -> [Float] {
        if let hit = cached(url) { return hit }
        let samples = await Task.detached(priority: .utility) { () -> [Float] in
            peaks(of: url, buckets: buckets)
        }.value
        if !samples.isEmpty {
            cache.setObject(samples.map { NSNumber(value: $0) } as NSArray, forKey: url as NSURL)
        }
        return samples
    }

    private static func peaks(of url: URL, buckets: Int) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              (try? file.read(into: buffer)) != nil,
              let channel = buffer.floatChannelData?[0] else { return [] }

        let total = Int(buffer.frameLength)
        let perBucket = max(1, total / buckets)
        var result: [Float] = []
        result.reserveCapacity(buckets)
        var index = 0
        while index < total && result.count < buckets {
            let end = min(total, index + perBucket)
            var peak: Float = 0
            var i = index
            // Striding keeps long files cheap; the peak is visually the same.
            let stride = max(1, (end - index) / 400)
            while i < end {
                peak = max(peak, abs(channel[i]))
                i += stride
            }
            result.append(peak)
            index = end
        }
        // Normalise with a gentle curve so quiet speech still reads.
        let maxPeak = max(result.max() ?? 1, 0.0001)
        return result.map { pow($0 / maxPeak, 0.7) }
    }
}
