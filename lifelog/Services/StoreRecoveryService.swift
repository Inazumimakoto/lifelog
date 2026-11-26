import Foundation
import SQLite3
import SwiftData

nonisolated struct StoreRecoveryCandidate: Identifiable, Hashable, Sendable {
    /// The URL of the expected archived main file, even when only sidecars survived.
    let id: URL
    let date: Date
    fileprivate let storeURL: URL
    fileprivate let suffix: String
}

nonisolated struct StoreRecoverySummary: Sendable {
    let diaryEntries: Int
    let events: Int
    let tasks: Int
    let otherRecords: Int

    var total: Int { diaryEntries + events + tasks + otherRecords }
}

nonisolated enum StoreRecoveryError: Error {
    case missingDatabase
    case invalidDatabase
    case unreadableArchive
}

/// Opens only disposable copies of the files quarantined by the 1.18.0 startup recovery.
/// See docs/requirements.md §4.9 and §6.
nonisolated struct StoreRecoveryService: Sendable {
    private let storeURLs: [URL]
    private let temporaryDirectory: URL
    private let schema: Schema

    @MainActor
    init() {
        var urls: [URL] = []
        if !PersistenceController.isRunningTests {
            let group = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: PersistenceController.appGroupIdentifier
            )
            if PersistenceController.isSimulatorDemoMode {
                if let group { urls.append(group.appendingPathComponent("simulator-demo.store")) }
            } else {
                if let group { urls.append(group.appendingPathComponent("default.store")) }
                urls.append(URL.applicationSupportDirectory.appendingPathComponent("default.store"))
            }
        }
        self.init(storeURLs: urls, temporaryDirectory: FileManager.default.temporaryDirectory)
    }

    @MainActor
    init(storeURLs: [URL], temporaryDirectory: URL) {
        self.storeURLs = storeURLs
        self.temporaryDirectory = temporaryDirectory
        self.schema = PersistenceController.localSchema
    }

    func candidates() throws -> [StoreRecoveryCandidate] {
        // PersistenceController formats the UTC timestamp as 2026-11-19T06-31-35Z.
        let timestamp = DateFormatter()
        timestamp.locale = Locale(identifier: "en_US_POSIX")
        timestamp.calendar = Calendar(identifier: .gregorian)
        timestamp.timeZone = TimeZone(secondsFromGMT: 0)
        timestamp.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"

        var found = Set<StoreRecoveryCandidate>()
        for storeURL in storeURLs {
            let directory = storeURL.deletingLastPathComponent()
            let files: [URL]
            do {
                files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                continue
            } catch {
                throw StoreRecoveryError.unreadableArchive
            }
            let name = storeURL.lastPathComponent
            let prefixes = ["", "-wal", "-shm"].map { name + $0 + ".corrupt-" }
            for file in files {
                let filename = file.lastPathComponent
                guard let prefix = prefixes.first(where: { filename.hasPrefix($0) }) else { continue }
                let stamp = String(filename.dropFirst(prefix.count))
                guard stamp.utf8.count == 20, let date = timestamp.date(from: stamp),
                      timestamp.string(from: date) == stamp else { continue }
                let suffix = ".corrupt-" + stamp
                found.insert(StoreRecoveryCandidate(id: directory.appendingPathComponent(name + suffix), date: date,
                                                     storeURL: storeURL, suffix: suffix))
            }
        }
        return found.sorted { $0.date == $1.date ? $0.id.path < $1.id.path : $0.date > $1.date }
    }

    func inspect(_ candidate: StoreRecoveryCandidate) throws -> StoreRecoverySummary {
        try withRecoveredStore(candidate) { context in
            func count<M: PersistentModel>(_ model: M.Type) throws -> Int {
                try context.fetchCount(FetchDescriptor<M>())
            }
            return try StoreRecoverySummary(
                diaryEntries: count(SDDiaryEntry.self), events: count(SDCalendarEvent.self), tasks: count(SDTask.self),
                otherRecords: count(SDHabit.self) + count(SDHabitRecord.self) + count(SDAnniversary.self)
                    + count(SDHealthSummary.self) + count(SDCalendarEventException.self) + count(SDMemoPad.self)
                    + count(SDAppState.self) + count(SDLetter.self) + count(SDSharedLetter.self)
                    + count(SDShoppingItem.self) + count(SDShoppingPlace.self)
            )
        }
    }

    /// Use the context only inside `perform`. Migration and WAL replay are allowed on the copy.
    func withRecoveredStore<Result>(_ candidate: StoreRecoveryCandidate,
                                    perform: (ModelContext) throws -> Result) throws -> Result {
        let directory = temporaryDirectory.appendingPathComponent("lifelify-recovery-" + UUID().uuidString, isDirectory: true)
        let copy = directory.appendingPathComponent(candidate.storeURL.lastPathComponent)
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: false,
                               attributes: [.protectionKey: FileProtectionType.complete])
        defer { try? fm.removeItem(at: directory) }

        do {
            try copyArchivedFile(candidate.id, to: copy)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            throw StoreRecoveryError.missingDatabase
        } catch {
            throw StoreRecoveryError.unreadableArchive
        }

        // Never pair a partial archive with files from the active store or a different date.
        // The SHM is a disposable index: SQLite rebuilds it from the matching WAL on our writable copy.
        let archivedWAL = URL(fileURLWithPath: candidate.storeURL.path + "-wal" + candidate.suffix)
        let walCopy = URL(fileURLWithPath: copy.path + "-wal")
        do {
            try copyArchivedFile(archivedWAL, to: walCopy)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            // A cleanly checkpointed store can consist solely of the main file.
        } catch {
            throw StoreRecoveryError.unreadableArchive
        }

        // The shipped models keep media paths and have no .externalStorage attributes.
        // The old quarantine never archived a Core Data support directory. An undated
        // support directory would belong to the live store and must not be mixed in.
        try checkDatabase(at: copy)
        return try autoreleasepool {
            let configuration = ModelConfiguration(schema: schema, url: copy, cloudKitDatabase: .none)
            let container: ModelContainer
            do {
                container = try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                throw StoreRecoveryError.invalidDatabase
            }
            let context = ModelContext(container)
            context.autosaveEnabled = false
            return try perform(context)
        }
    }

    private func copyArchivedFile(_ source: URL, to destination: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw StoreRecoveryError.invalidDatabase }
        try FileManager.default.copyItem(at: source, to: destination)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete, .posixPermissions: 0o600],
                                              ofItemAtPath: destination.path)
    }

    private func checkDatabase(at copy: URL) throws {
        var db: OpaquePointer?
        let result = sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(db) }
        guard result == SQLITE_OK, let db else { throw StoreRecoveryError.invalidDatabase }

        func firstValue(_ sql: String) -> String? {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW,
                  let text = sqlite3_column_text(statement, 0) else { return nil }
            return String(cString: text)
        }

        // An empty SQLite file also passes an integrity check. Require Core Data store
        // metadata before letting ModelContainer open (and potentially initialize) the copy.
        guard firstValue("PRAGMA integrity_check(1)") == "ok",
              firstValue("SELECT 1 FROM Z_METADATA WHERE length(Z_PLIST) > 0 LIMIT 1") == "1" else {
            throw StoreRecoveryError.invalidDatabase
        }
    }
}
