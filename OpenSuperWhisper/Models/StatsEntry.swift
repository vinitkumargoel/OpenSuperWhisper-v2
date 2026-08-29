import Foundation
import GRDB

/// One completed transcription's contribution to lifetime statistics.
///
/// This exists so that clearing history does not clear the stats. Analytics used
/// to be computed by scanning the `recordings` table, which meant "Delete All"
/// silently reset every total and emptied the activity graph — the recordings
/// were the statistics. The ledger separates the two: deleting a recording
/// removes the audio and the transcript, and leaves the fact that it happened.
///
/// Deliberately holds no content. A row is a timestamp, a duration and a word
/// count — enough to rebuild every number the analytics view shows, and nothing
/// that could reconstruct what was said. `recordingID` is kept only as a
/// primary key so re-writes of the same recording (a regenerate, a reformat)
/// update their row instead of double-counting; it outlives the recording it
/// names, and nothing resolves it back.
struct StatsEntry: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "stats_ledger"

    let recordingID: String
    let timestamp: Date
    let duration: TimeInterval
    let words: Int

    enum Columns {
        static let recordingID = Column("recordingID")
        static let timestamp = Column("timestamp")
        static let duration = Column("duration")
        static let words = Column("words")
    }

    /// The analytics-relevant projection of a recording, or `nil` when the
    /// recording should not count — anything unfinished, and anything whose
    /// transcript came back empty.
    init?(recording: Recording) {
        guard recording.status == .completed,
              !recording.transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        self.recordingID = recording.id.uuidString
        self.timestamp = recording.timestamp
        self.duration = recording.duration
        self.words = TextUtil.wordCount(recording.transcription)
    }

    init(recordingID: String, timestamp: Date, duration: TimeInterval, words: Int) {
        self.recordingID = recordingID
        self.timestamp = timestamp
        self.duration = duration
        self.words = words
    }
}
