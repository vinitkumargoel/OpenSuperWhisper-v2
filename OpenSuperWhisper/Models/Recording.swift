import Foundation
import GRDB
import AVFoundation

enum RecordingStatus: String, Codable {
    case pending
    case converting
    case transcribing
    case formatting
    case completed
    case failed
}

struct Recording: Identifiable, Codable, FetchableRecord, PersistableRecord, Equatable {
    let id: UUID
    let timestamp: Date
    let fileName: String
    var transcription: String
    var rawTranscription: String?
    let duration: TimeInterval
    var status: RecordingStatus
    var progress: Float
    var sourceFileURL: String?
    /// Friendly name of the app that was focused when recording started ("Mail").
    var targetAppName: String?
    /// Bundle id of that app ("com.apple.mail"), for filtering/icons.
    var targetAppBundleID: String?
    /// User favourite flag.
    var isStarred: Bool = false

    var isRegeneration: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, timestamp, fileName, transcription, rawTranscription, duration, status, progress, sourceFileURL, targetAppName, targetAppBundleID, isStarred
    }

    static func == (lhs: Recording, rhs: Recording) -> Bool {
        return lhs.id == rhs.id &&
               lhs.status == rhs.status &&
               lhs.progress == rhs.progress &&
               lhs.transcription == rhs.transcription &&
               lhs.rawTranscription == rhs.rawTranscription &&
               lhs.isStarred == rhs.isStarred &&
               lhs.targetAppName == rhs.targetAppName &&
               lhs.isRegeneration == rhs.isRegeneration
    }

    static var recordingsDirectory: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let appDirectory = applicationSupport.appendingPathComponent(Bundle.main.bundleIdentifier!)
        return appDirectory.appendingPathComponent("recordings")
    }

    var url: URL {
        Self.recordingsDirectory.appendingPathComponent(fileName)
    }
    
    var isPending: Bool {
        status == .pending || status == .converting || status == .transcribing || status == .formatting
    }
    
    var sourceFileName: String? {
        guard let sourceFileURL = sourceFileURL else { return nil }
        return URL(fileURLWithPath: sourceFileURL).lastPathComponent
    }

    static let databaseTableName = "recordings"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let timestamp = Column(CodingKeys.timestamp)
        static let fileName = Column(CodingKeys.fileName)
        static let transcription = Column(CodingKeys.transcription)
        static let rawTranscription = Column(CodingKeys.rawTranscription)
        static let duration = Column(CodingKeys.duration)
        static let status = Column(CodingKeys.status)
        static let progress = Column(CodingKeys.progress)
        static let sourceFileURL = Column(CodingKeys.sourceFileURL)
        static let targetAppName = Column(CodingKeys.targetAppName)
        static let targetAppBundleID = Column(CodingKeys.targetAppBundleID)
        static let isStarred = Column(CodingKeys.isStarred)
    }
}

@MainActor
class RecordingStore: ObservableObject {
    static let shared = RecordingStore()

    @Published private(set) var recordings: [Recording] = []
    private let dbQueue: DatabaseQueue

    private init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let appDirectory = applicationSupport.appendingPathComponent(Bundle.main.bundleIdentifier!)
        let dbPath = appDirectory.appendingPathComponent("recordings.sqlite")

        print("Database path: \(dbPath.path)")

        do {
            try FileManager.default.createDirectory(
                at: appDirectory, withIntermediateDirectories: true)
            dbQueue = try DatabaseQueue(path: dbPath.path)
            try setupDatabase()
            Task {
                await repairStoredZeroDurations()
                await purgeRecordings(olderThanDays: AppPreferences.shared.historyRetentionDays)
            }
        } catch {
            fatalError("Failed to setup database: \(error)")
        }
    }

    private nonisolated func setupDatabase() throws {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("v1") { db in
            try db.create(table: Recording.databaseTableName, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("timestamp", .datetime).notNull().indexed()
                t.column("fileName", .text).notNull()
                t.column("transcription", .text).notNull().indexed().collate(.nocase)
                t.column("duration", .double).notNull()
            }
        }
        
        migrator.registerMigration("v2_add_status") { db in
            let columns = try db.columns(in: Recording.databaseTableName)
            let columnNames = columns.map { $0.name }
            
            if !columnNames.contains("status") {
                try db.alter(table: Recording.databaseTableName) { t in
                    t.add(column: "status", .text).notNull().defaults(to: "completed")
                }
            }
            if !columnNames.contains("progress") {
                try db.alter(table: Recording.databaseTableName) { t in
                    t.add(column: "progress", .double).notNull().defaults(to: 1.0)
                }
            }
            if !columnNames.contains("sourceFileURL") {
                try db.alter(table: Recording.databaseTableName) { t in
                    t.add(column: "sourceFileURL", .text)
                }
            }
        }

        migrator.registerMigration("v3_add_raw_transcription") { db in
            let columns = try db.columns(in: Recording.databaseTableName)
            let columnNames = columns.map { $0.name }

            if !columnNames.contains("rawTranscription") {
                try db.alter(table: Recording.databaseTableName) { t in
                    t.add(column: "rawTranscription", .text)
                }
            }
        }

        migrator.registerMigration("v4_add_target_app") { db in
            let columnNames = try db.columns(in: Recording.databaseTableName).map { $0.name }
            if !columnNames.contains("targetAppName") {
                try db.alter(table: Recording.databaseTableName) { t in
                    t.add(column: "targetAppName", .text)
                }
            }
            if !columnNames.contains("targetAppBundleID") {
                try db.alter(table: Recording.databaseTableName) { t in
                    t.add(column: "targetAppBundleID", .text)
                }
            }
        }

        migrator.registerMigration("v5_add_starred") { db in
            let columnNames = try db.columns(in: Recording.databaseTableName).map { $0.name }
            if !columnNames.contains("isStarred") {
                try db.alter(table: Recording.databaseTableName) { t in
                    t.add(column: "isStarred", .boolean).notNull().defaults(to: false)
                }
            }
        }

        try migrator.migrate(dbQueue)
    }
    
    private nonisolated func fetchAllRecordings() async throws -> [Recording] {
        try await dbQueue.read { db in
            try Recording
                .order(Recording.Columns.timestamp.desc)
                .fetchAll(db)
        }
    }
    
    /// All completed recordings, newest first, for export.
    nonisolated func fetchAllForExport() async -> [Recording] {
        do {
            return try await dbQueue.read { db in
                try Recording
                    .filter(Recording.Columns.status == RecordingStatus.completed.rawValue)
                    .order(Recording.Columns.timestamp.desc)
                    .fetchAll(db)
            }
        } catch {
            print("Failed to fetch recordings for export: \(error)")
            return []
        }
    }

    nonisolated func fetchRecordings(limit: Int, offset: Int, starredOnly: Bool = false) async throws -> [Recording] {
        try await dbQueue.read { db in
            var request = Recording.all()
            if starredOnly {
                request = request.filter(Recording.Columns.isStarred == true)
            }
            return try request
                .order(Recording.Columns.timestamp.desc)
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
    }

    nonisolated func fetchAnalyticsRecordings() async throws -> [Recording] {
        let recordings = try await dbQueue.read { db in
            try Recording
                .filter(Recording.Columns.status == RecordingStatus.completed.rawValue)
                .order(Recording.Columns.timestamp.desc)
                .fetchAll(db)
        }
        return await repairDurationsForAnalytics(recordings)
    }

    private nonisolated func repairDurationsForAnalytics(_ recordings: [Recording]) async -> [Recording] {
        await withTaskGroup(of: Recording.self) { group in
            for recording in recordings {
                group.addTask {
                    guard recording.duration <= 0 else { return recording }
                    let asset = AVURLAsset(url: recording.url)
                    let loadedDuration = (try? await asset.load(.duration))
                        .map { CMTimeGetSeconds($0) } ?? 0
                    let duration = loadedDuration.isFinite && loadedDuration > 0 ? loadedDuration : 0

                    guard duration > 0 else { return recording }
                    return Recording(
                        id: recording.id,
                        timestamp: recording.timestamp,
                        fileName: recording.fileName,
                        transcription: recording.transcription,
                        rawTranscription: recording.rawTranscription,
                        duration: duration,
                        status: recording.status,
                        progress: recording.progress,
                        sourceFileURL: recording.sourceFileURL,
                        targetAppName: recording.targetAppName,
                        targetAppBundleID: recording.targetAppBundleID,
                        isStarred: recording.isStarred
                    )
                }
            }

            var repaired: [Recording] = []
            for await recording in group {
                repaired.append(recording)
            }
            return repaired.sorted { $0.timestamp > $1.timestamp }
        }
    }

    private func repairStoredZeroDurations() async {
        do {
            let repairedCount = try await repairStoredZeroDurationsInDB()
            if repairedCount > 0 {
                await MainActor.run {
                    NotificationCenter.default.post(name: Self.recordingsDidUpdateNotification, object: nil)
                }
            }
        } catch {
            print("Failed to repair recording durations: \(error)")
        }
    }

    private nonisolated func repairStoredZeroDurationsInDB() async throws -> Int {
        let zeroDurationRecordings = try await dbQueue.read { db in
            try Recording
                .filter(Recording.Columns.duration <= 0)
                .fetchAll(db)
        }

        let repairs = await withTaskGroup(of: (UUID, TimeInterval)?.self) { group in
            for recording in zeroDurationRecordings {
                group.addTask {
                    let asset = AVURLAsset(url: recording.url)
                    let loadedDuration = (try? await asset.load(.duration))
                        .map { CMTimeGetSeconds($0) } ?? 0
                    let duration = loadedDuration.isFinite && loadedDuration > 0 ? loadedDuration : 0
                    return duration > 0 ? (recording.id, duration) : nil
                }
            }

            var repaired: [(UUID, TimeInterval)] = []
            for await repair in group {
                if let repair {
                    repaired.append(repair)
                }
            }
            return repaired
        }

        guard !repairs.isEmpty else { return 0 }

        try await dbQueue.write { db in
            for (id, duration) in repairs {
                try Recording
                    .filter(Recording.Columns.id == id)
                    .updateAll(db, [Recording.Columns.duration.set(to: duration)])
            }
        }

        return repairs.count
    }

    func getPendingRecordings() -> [Recording] {
        do {
            return try dbQueue.read { db in
                try Recording
                    .filter([RecordingStatus.pending.rawValue, RecordingStatus.converting.rawValue, RecordingStatus.transcribing.rawValue, RecordingStatus.formatting.rawValue].contains(Recording.Columns.status))
                    .order(Recording.Columns.timestamp.asc)
                    .fetchAll(db)
            }
        } catch {
            print("Failed to get pending recordings: \(error)")
            return []
        }
    }

    func getNextPendingRecording() -> Recording? {
        do {
            return try dbQueue.read { db in
                try Recording
                    .filter([RecordingStatus.pending.rawValue, RecordingStatus.converting.rawValue, RecordingStatus.transcribing.rawValue, RecordingStatus.formatting.rawValue].contains(Recording.Columns.status))
                    .order(Recording.Columns.timestamp.asc)
                    .limit(1)
                    .fetchOne(db)
            }
        } catch {
            print("Failed to get next pending recording: \(error)")
            return nil
        }
    }

    static let recordingsDidUpdateNotification = Notification.Name("RecordingStore.recordingsDidUpdate")

    func addRecording(_ recording: Recording) {
        Task {
            do {
                try await insertRecording(recording)
                await MainActor.run {
                    NotificationCenter.default.post(name: Self.recordingsDidUpdateNotification, object: nil)
                }
            } catch {
                print("Failed to add recording: \(error)")
            }
        }
    }
    
    func addRecordingSync(_ recording: Recording) async throws {
        try await insertRecording(recording)
        await MainActor.run {
            NotificationCenter.default.post(name: Self.recordingsDidUpdateNotification, object: nil)
        }
    }
    
    private nonisolated func insertRecording(_ recording: Recording) async throws {
        try await dbQueue.write { db in
            try recording.insert(db)
        }
    }
    
    func updateRecording(_ recording: Recording) {
        Task {
            do {
                try await updateRecordingInDB(recording)
                await MainActor.run {
                    NotificationCenter.default.post(name: Self.recordingsDidUpdateNotification, object: nil)
                }
            } catch {
                print("Failed to update recording: \(error)")
            }
        }
    }
    
    func updateRecordingSync(_ recording: Recording) async throws {
        try await updateRecordingInDB(recording)
        await MainActor.run {
            NotificationCenter.default.post(name: Self.recordingsDidUpdateNotification, object: nil)
        }
    }
    
    func updateRecordingProgressOnly(_ id: UUID, transcription: String, progress: Float, status: RecordingStatus, rawTranscription: String? = nil) {
        Task {
            await updateRecordingProgressOnlySync(id, transcription: transcription, progress: progress, status: status, rawTranscription: rawTranscription)
        }
    }
    
    static let recordingProgressDidUpdateNotification = Notification.Name("RecordingStore.recordingProgressDidUpdate")
    
    func updateRecordingProgressOnlySync(_ id: UUID, transcription: String, progress: Float, status: RecordingStatus, rawTranscription: String? = nil, isRegeneration: Bool? = nil) async {
        do {
            _ = try await dbQueue.write { db -> Int in
                var assignments: [ColumnAssignment] = [
                    Recording.Columns.transcription.set(to: transcription),
                    Recording.Columns.progress.set(to: progress),
                    Recording.Columns.status.set(to: status.rawValue)
                ]
                if let rawTranscription {
                    assignments.append(Recording.Columns.rawTranscription.set(to: rawTranscription))
                }
                return try Recording
                    .filter(Recording.Columns.id == id)
                    .updateAll(db, assignments)
            }
            if let index = recordings.firstIndex(where: { $0.id == id }) {
                var updated = recordings[index]
                updated.transcription = transcription
                if let rawTranscription {
                    updated.rawTranscription = rawTranscription
                }
                updated.progress = progress
                updated.status = status
                if let isRegeneration = isRegeneration {
                    updated.isRegeneration = isRegeneration
                }
                recordings[index] = updated
            }
            
            var userInfo: [String: Any] = [
                "id": id,
                "transcription": transcription,
                "progress": progress,
                "status": status
            ]
            if let isRegeneration = isRegeneration {
                userInfo["isRegeneration"] = isRegeneration
            }
            
            await MainActor.run {
                NotificationCenter.default.post(name: Self.recordingProgressDidUpdateNotification, object: nil, userInfo: userInfo)
            }
        } catch {
            print("Failed to update recording progress: \(error)")
        }
    }

    nonisolated func updateSourceFileURL(_ id: UUID, sourceURL: String) async throws {
        try await dbQueue.write { db in
            try Recording
                .filter(Recording.Columns.id == id)
                .updateAll(db, [
                    Recording.Columns.sourceFileURL.set(to: sourceURL)
                ])
        }
    }

    func updateRecordingStatusOnly(_ id: UUID, progress: Float, status: RecordingStatus, isRegeneration: Bool? = nil) async {
        do {
            _ = try await dbQueue.write { db -> Int in
                try Recording
                    .filter(Recording.Columns.id == id)
                    .updateAll(db, [
                        Recording.Columns.progress.set(to: progress),
                        Recording.Columns.status.set(to: status.rawValue)
                    ])
            }
            if let index = recordings.firstIndex(where: { $0.id == id }) {
                var updated = recordings[index]
                updated.progress = progress
                updated.status = status
                if let isRegeneration = isRegeneration {
                    updated.isRegeneration = isRegeneration
                }
                recordings[index] = updated
            }
            
            var userInfo: [String: Any] = [
                "id": id,
                "progress": progress,
                "status": status
            ]
            if let isRegeneration = isRegeneration {
                userInfo["isRegeneration"] = isRegeneration
            }
            
            await MainActor.run {
                NotificationCenter.default.post(name: Self.recordingProgressDidUpdateNotification, object: nil, userInfo: userInfo)
            }
        } catch {
            print("Failed to update recording status: \(error)")
        }
    }

    private nonisolated func updateRecordingInDB(_ recording: Recording) async throws {
        try await dbQueue.write { db in
            try recording.update(db)
        }
    }

    func deleteRecording(_ recording: Recording) {
        if recording.isPending {
            TranscriptionQueue.shared.cancelRecording(recording.id)
        }
        
        Task {
            do {
                try await deleteRecordingFromDB(recording)
                try? FileManager.default.removeItem(at: recording.url)
                await MainActor.run {
                    NotificationCenter.default.post(name: Self.recordingsDidUpdateNotification, object: nil)
                }
            } catch {
                print("Failed to delete recording: \(error)")
            }
        }
    }
    
    private nonisolated func deleteRecordingFromDB(_ recording: Recording) async throws {
        try await dbQueue.write { db in
            _ = try recording.delete(db)
        }
    }

    func deleteAllRecordings() {
        Task {
            do {
                let allRecordings = try await fetchAllRecordings()
                for recording in allRecordings {
                    try? FileManager.default.removeItem(at: recording.url)
                }
                try await deleteAllRecordingsFromDB()
                await MainActor.run {
                    NotificationCenter.default.post(name: Self.recordingsDidUpdateNotification, object: nil)
                }
            } catch {
                print("Failed to delete all recordings: \(error)")
            }
        }
    }
    
    private nonisolated func deleteAllRecordingsFromDB() async throws {
        try await dbQueue.write { db in
            _ = try Recording.deleteAll(db)
        }
    }

    func searchRecordings(query: String) -> [Recording] {
        do {
            return try dbQueue.read { db in
                try Recording
                    .filter(Recording.Columns.transcription.like("%\(query)%").collating(.nocase))
                    .order(Recording.Columns.timestamp.desc)
                    .limit(100)
                    .fetchAll(db)
            }
        } catch {
            print("Failed to search recordings: \(error)")
            return []
        }
    }
    
    nonisolated func searchRecordingsAsync(query: String, limit: Int = 100, offset: Int = 0, starredOnly: Bool = false) async -> [Recording] {
        do {
            return try await dbQueue.read { db in
                // Match either the transcription or the target-app name.
                var request = Recording.filter(
                    Recording.Columns.transcription.like("%\(query)%").collating(.nocase)
                    || Recording.Columns.targetAppName.like("%\(query)%").collating(.nocase)
                )
                if starredOnly {
                    request = request.filter(Recording.Columns.isStarred == true)
                }
                return try request
                    .order(Recording.Columns.timestamp.desc)
                    .limit(limit, offset: offset)
                    .fetchAll(db)
            }
        } catch {
            print("Failed to search recordings: \(error)")
            return []
        }
    }

    // MARK: - Favourites

    /// Toggle/set the starred flag for a recording and notify observers.
    func setStarred(_ id: UUID, _ starred: Bool) {
        Task {
            do {
                _ = try await dbQueue.write { db -> Int in
                    try Recording
                        .filter(Recording.Columns.id == id)
                        .updateAll(db, [Recording.Columns.isStarred.set(to: starred)])
                }
                if let index = recordings.firstIndex(where: { $0.id == id }) {
                    recordings[index].isStarred = starred
                }
                NotificationCenter.default.post(name: Self.recordingsDidUpdateNotification, object: nil)
            } catch {
                print("Failed to update starred flag: \(error)")
            }
        }
    }

    // MARK: - Retention

    /// Deletes completed recordings (and their audio) older than `days`.
    /// `days <= 0` means "keep forever" and is a no-op. Starred recordings are
    /// always kept. Returns the number of recordings purged.
    @discardableResult
    func purgeRecordings(olderThanDays days: Int) async -> Int {
        guard days > 0 else { return 0 }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
        do {
            let expired = try await dbQueue.read { db in
                try Recording
                    .filter(Recording.Columns.timestamp < cutoff)
                    .filter(Recording.Columns.isStarred == false)
                    .filter(Recording.Columns.status == RecordingStatus.completed.rawValue)
                    .fetchAll(db)
            }
            guard !expired.isEmpty else { return 0 }
            for recording in expired {
                try? FileManager.default.removeItem(at: recording.url)
            }
            let ids = expired.map { $0.id }
            _ = try await dbQueue.write { db -> Int in
                try Recording.filter(ids.contains(Recording.Columns.id)).deleteAll(db)
            }
            NotificationCenter.default.post(name: Self.recordingsDidUpdateNotification, object: nil)
            return expired.count
        } catch {
            print("Failed to purge old recordings: \(error)")
            return 0
        }
    }
}
