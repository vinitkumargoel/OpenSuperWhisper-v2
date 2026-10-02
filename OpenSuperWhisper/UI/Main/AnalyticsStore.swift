import Combine
import Foundation

/// Usage statistics for Insights and Home's "Today" tiles. Shared so a reset
/// or a new recording shows up everywhere at once.
@MainActor
final class AnalyticsStore: ObservableObject {
    static let shared = AnalyticsStore()

    @Published private(set) var snapshot: AnalyticsSnapshot = .empty
    @Published private(set) var isLoading = false
    @Published var range: AnalyticsRange = .month
    /// Share of recordings per target app, most used first.
    @Published private(set) var appShares: [(name: String, share: Double)] = []

    private var cancellables = Set<AnyCancellable>()

    private init() {
        NotificationCenter.default.publisher(for: RecordingStore.recordingsDidUpdateNotification)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        refresh()
    }

    func refresh() {
        isLoading = true
        Task {
            let snapshot: AnalyticsSnapshot
            do {
                snapshot = AnalyticsSnapshot(entries: try await RecordingStore.shared.fetchStatsEntries())
            } catch {
                print("Failed to load analytics: \(error)")
                snapshot = .empty
            }
            let counts = await RecordingStore.shared.fetchLibraryCounts()
            self.snapshot = snapshot
            self.appShares = Self.shares(from: counts)
            self.isLoading = false
        }
    }

    /// Clears the stats ledger. Recordings are untouched — this is the opposite
    /// half of the split: deleting history keeps the statistics, and this
    /// clears the statistics while keeping the history.
    func resetStatistics() {
        Task {
            do {
                try await RecordingStore.shared.resetStatistics()
            } catch {
                print("Failed to reset statistics: \(error)")
            }
            refresh()
        }
    }

    // MARK: - Derived

    var summary: AnalyticsRangeSummary { snapshot.summary(for: range) }
    var series: [AnalyticsDay] { snapshot.series(for: range) }

    /// Consecutive active days ending today (or yesterday, if today is still empty).
    var currentStreak: Int {
        var days = Array(snapshot.dailyActivity.reversed())
        if days.first?.recordings == 0 { days.removeFirst() }
        return days.prefix { $0.recordings > 0 }.count
    }

    /// Longest run of active days in the tracked window.
    var bestStreak: Int {
        var best = 0, run = 0
        for day in snapshot.dailyActivity {
            run = day.recordings > 0 ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }

    /// How many times faster than typing, from words per minute spoken.
    var speedupOverTyping: Double {
        guard snapshot.averageWordsPerMinute > 0 else { return 0 }
        return snapshot.averageWordsPerMinute / AnalyticsSnapshot.typingWordsPerMinute
    }

    private static func shares(from counts: LibraryCounts) -> [(name: String, share: Double)] {
        let total = counts.apps.reduce(0) { $0 + $1.count }
        guard total > 0 else { return [] }
        let top = counts.apps.prefix(5).map { (name: $0.name, share: Double($0.count) / Double(total)) }
        let rest = counts.apps.dropFirst(5).reduce(0) { $0 + $1.count }
        return rest > 0 ? top + [(name: "Other", share: Double(rest) / Double(total))] : top
    }
}

enum DurationText {
    /// "52 h 40 min", "23 min", "40 s".
    static func long(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) s" }
        let hours = total / 3600, minutes = (total % 3600) / 60
        if hours > 0 { return minutes > 0 ? "\(hours) h \(minutes) min" : "\(hours) h" }
        return "\(minutes) min"
    }

    /// Minutes with one decimal under ten: "6.2", "811".
    static func minutes(_ seconds: TimeInterval) -> String {
        let minutes = seconds / 60
        return minutes < 10 ? String(format: "%.1f", minutes) : String(Int(minutes.rounded()))
    }
}
