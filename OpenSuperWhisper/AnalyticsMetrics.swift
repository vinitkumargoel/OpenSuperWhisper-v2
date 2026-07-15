import Foundation

struct AnalyticsDay: Identifiable {
    let id: Date
    let date: Date
    let recordings: Int
    let duration: TimeInterval
    let words: Int
    let estimatedTimeSaved: TimeInterval
}

/// Selectable window for the activity graph.
enum AnalyticsRange: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case quarter = 90

    var id: Int { rawValue }

    var days: Int { rawValue }

    var label: String {
        switch self {
        case .week: return "7 days"
        case .month: return "30 days"
        case .quarter: return "90 days"
        }
    }
}

/// Aggregate stats over an arbitrary window of days.
struct AnalyticsRangeSummary {
    let recordings: Int
    let words: Int
    let duration: TimeInterval
    let estimatedTimeSaved: TimeInterval
    let activeDays: Int
    let bestDayWords: Int
}

struct AnalyticsSnapshot {
    static let typingWordsPerMinute: Double = 40
    /// Longest window we pre-compute so the UI can switch ranges without re-querying.
    static let maxTrackedDays = 90

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
    /// Oldest → newest, `maxTrackedDays` entries (zero-filled for days with no activity).
    let dailyActivity: [AnalyticsDay]

    static let empty = AnalyticsSnapshot(recordings: [])

    /// Backwards-compatible convenience for the previous 7-day view.
    var lastSevenDays: [AnalyticsDay] { series(for: .week) }

    /// Trailing slice of `dailyActivity` for the requested range (oldest → newest).
    func series(for range: AnalyticsRange) -> [AnalyticsDay] {
        Array(dailyActivity.suffix(range.days))
    }

    /// Aggregate totals over the requested range.
    func summary(for range: AnalyticsRange) -> AnalyticsRangeSummary {
        let days = series(for: range)
        let words = days.reduce(0) { $0 + $1.words }
        let recordings = days.reduce(0) { $0 + $1.recordings }
        let duration = days.reduce(0) { $0 + $1.duration }
        let saved = days.reduce(0) { $0 + $1.estimatedTimeSaved }
        let activeDays = days.filter { $0.recordings > 0 }.count
        let bestDay = days.map(\.words).max() ?? 0
        return AnalyticsRangeSummary(
            recordings: recordings,
            words: words,
            duration: duration,
            estimatedTimeSaved: saved,
            activeDays: activeDays,
            bestDayWords: bestDay
        )
    }

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

        // Bucket completed recordings by start-of-day once, then walk the window.
        var wordsByDay: [Date: Int] = [:]
        var durationByDay: [Date: TimeInterval] = [:]
        var countByDay: [Date: Int] = [:]
        for recording in completed {
            let dayKey = calendar.startOfDay(for: recording.timestamp)
            wordsByDay[dayKey, default: 0] += TextUtil.wordCount(recording.transcription)
            durationByDay[dayKey, default: 0] += recording.duration
            countByDay[dayKey, default: 0] += 1
        }

        self.dailyActivity = (0..<Self.maxTrackedDays).compactMap { offset -> AnalyticsDay? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else {
                return nil
            }
            let words = wordsByDay[day] ?? 0
            let duration = durationByDay[day] ?? 0
            return AnalyticsDay(
                id: day,
                date: day,
                recordings: countByDay[day] ?? 0,
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
