import Foundation

struct AnalyticsDay: Identifiable {
    let id: Date
    let date: Date
    let recordings: Int
    let duration: TimeInterval
    let words: Int
    let estimatedTimeSaved: TimeInterval
}

struct AnalyticsSnapshot {
    static let typingWordsPerMinute: Double = 40

    let generatedAt: Date
    let totalRecordings: Int
    let totalDuration: TimeInterval
    let totalWords: Int
    let estimatedTypingDuration: TimeInterval
    let estimatedTimeSaved: TimeInterval
    let todayRecordings: Int
    let todayDuration: TimeInterval
    let todayWords: Int
    let todayEstimatedTimeSaved: TimeInterval
    let averageWordsPerRecording: Double
    let averageWordsPerMinute: Double
    let lastSevenDays: [AnalyticsDay]

    static let empty = AnalyticsSnapshot(recordings: [])

    init(recordings: [Recording], calendar: Calendar = .current, now: Date = Date()) {
        let completed = recordings.filter { recording in
            recording.status == .completed && !recording.transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let todayStart = calendar.startOfDay(for: now)
        let today = completed.filter { calendar.isDate($0.timestamp, inSameDayAs: now) }

        self.generatedAt = now
        self.totalRecordings = completed.count
        self.totalDuration = completed.reduce(0) { $0 + $1.duration }
        self.totalWords = completed.reduce(0) { $0 + TextUtil.wordCount($1.transcription) }
        self.estimatedTypingDuration = Self.estimatedTypingDuration(forWords: totalWords)
        self.estimatedTimeSaved = max(0, estimatedTypingDuration - totalDuration)
        self.todayRecordings = today.count
        self.todayDuration = today.reduce(0) { $0 + $1.duration }
        self.todayWords = today.reduce(0) { $0 + TextUtil.wordCount($1.transcription) }
        self.todayEstimatedTimeSaved = max(0, Self.estimatedTypingDuration(forWords: todayWords) - todayDuration)
        self.averageWordsPerRecording = completed.isEmpty ? 0 : Double(totalWords) / Double(completed.count)
        self.averageWordsPerMinute = totalDuration > 0 ? Double(totalWords) / (totalDuration / 60) : 0

        self.lastSevenDays = (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else {
                return nil
            }
            let dayRecordings = completed.filter { calendar.isDate($0.timestamp, inSameDayAs: day) }
            let words = dayRecordings.reduce(0) { $0 + TextUtil.wordCount($1.transcription) }
            let duration = dayRecordings.reduce(0) { $0 + $1.duration }
            return AnalyticsDay(
                id: day,
                date: day,
                recordings: dayRecordings.count,
                duration: duration,
                words: words,
                estimatedTimeSaved: max(0, Self.estimatedTypingDuration(forWords: words) - duration)
            )
        }
        .reversed()
    }

    static func estimatedTypingDuration(forWords words: Int) -> TimeInterval {
        guard words > 0 else { return 0 }
        return Double(words) / typingWordsPerMinute * 60
    }
}
