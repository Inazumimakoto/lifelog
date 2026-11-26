import Foundation
import SQLite3
import SwiftData
import XCTest
@testable import lifelify

@MainActor
final class StoreRecoveryServiceTests: XCTestCase {
    private let firstStamp = ".corrupt-2026-11-19T06-31-35Z"
    private let secondStamp = ".corrupt-2026-11-19T08-10-00Z"

    func testDiscoveryIncludesPartialSetsAndKeepsDifferentDirectoriesAndDatesSeparate() throws {
        try withFixture { directory, work in
            let group = directory.appendingPathComponent("default.store")
            let fallbackDirectory = directory.appendingPathComponent("fallback")
            try FileManager.default.createDirectory(at: fallbackDirectory, withIntermediateDirectories: false)
            let fallback = fallbackDirectory.appendingPathComponent("default.store")
            for path in [group.path + firstStamp, group.path + "-wal" + firstStamp,
                         group.path + "-shm" + secondStamp, fallback.path + firstStamp,
                         group.path, group.path + "-wal", group.path + ".corrupt-not-a-date",
                         group.path + firstStamp + ".old"] {
                try Data().write(to: URL(fileURLWithPath: path))
            }
            let service = StoreRecoveryService(storeURLs: [group, fallback], temporaryDirectory: work)
            let candidates = try service.candidates()

            XCTAssertEqual(candidates.count, 3)
            XCTAssertEqual(candidates.first?.id.path, group.path + secondStamp)
            XCTAssertEqual(Set(candidates.map(\.id.path)), Set([group.path + firstStamp, group.path + secondStamp,
                                                               fallback.path + firstStamp]))
            XCTAssertThrowsError(try service.inspect(try XCTUnwrap(candidates.first))) {
                XCTAssertEqual($0 as? StoreRecoveryError, .missingDatabase)
            }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.path).isEmpty)
        }
    }

    func testOpenCopyReplaysUncheckpointedWALAndDoesNotChangeArchivedOrCurrentFiles() throws {
        try withFixture { directory, work in
            let source = directory.appendingPathComponent("fixture.store")
            let live = directory.appendingPathComponent("default.store")
            try makeStore(at: source, text: "Checkpointed entry")
            try makeStore(at: live, text: "Entry created after reset")

            // Modify an already persisted fixture while the SQLite WAL is open so its last
            // committed text can only be recovered using the correct generation's WAL.
            let paths = ["", "-wal", "-shm"]
            try withDatabase(at: source) { db in
                XCTAssertEqual(sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil), SQLITE_OK)
                XCTAssertEqual(sqlite3_exec(db, "UPDATE ZSDDIARYENTRY SET ZTEXT = 'Only in the WAL';", nil, nil, nil), SQLITE_OK)
                let wal = URL(fileURLWithPath: source.path + "-wal")
                XCTAssertGreaterThan(try Data(contentsOf: wal).count, 32)
                for suffix in paths {
                    try FileManager.default.copyItem(at: URL(fileURLWithPath: source.path + suffix),
                                                     to: URL(fileURLWithPath: live.path + suffix + firstStamp))
                }
            }
            // An unmatched sidecar must never be supplied to the older candidate.
            try Data("other generation".utf8).write(to: URL(fileURLWithPath: live.path + "-wal" + secondStamp))
            let snapshotURLs = paths.map { URL(fileURLWithPath: live.path + $0 + firstStamp) } + [live]
            let originals = try snapshotURLs.map { try Data(contentsOf: $0) }
            let service = StoreRecoveryService(storeURLs: [live], temporaryDirectory: work)
            let candidate = try XCTUnwrap(service.candidates().last)
            let summary = try service.inspect(candidate)
            XCTAssertEqual(summary.diaryEntries, 1)
            XCTAssertEqual(summary.total, 1)
            try service.withRecoveredStore(candidate) { sourceContext in
                let diary = try XCTUnwrap(sourceContext.fetch(FetchDescriptor<SDDiaryEntry>()).first)
                XCTAssertEqual(diary.text, "Only in the WAL")
                XCTAssertTrue(try sourceContext.fetch(FetchDescriptor<SDTask>()).isEmpty)
            }
            XCTAssertEqual(try snapshotURLs.map { try Data(contentsOf: $0) }, originals)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.path).isEmpty)
        }
    }

    func testInvalidArchiveIsNotOpenedAsAnEmptyNewStore() throws {
        try withFixture { directory, work in
            let live = directory.appendingPathComponent("default.store")
            let empty = URL(fileURLWithPath: live.path + firstStamp)
            try Data().write(to: empty)
            let bad = URL(fileURLWithPath: live.path + secondStamp)
            try Data("not a SQLite store".utf8).write(to: bad)
            let service = StoreRecoveryService(storeURLs: [live], temporaryDirectory: work)
            let candidates = try service.candidates()
            XCTAssertEqual(candidates.count, 2)
            for candidate in candidates {
                XCTAssertThrowsError(try service.inspect(candidate)) {
                    XCTAssertEqual($0 as? StoreRecoveryError, .invalidDatabase)
                }
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: live.path))
            XCTAssertEqual(try Data(contentsOf: empty), Data())
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: work.path).isEmpty)
        }
    }

    private func withFixture(_ use: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let work = root.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try use(root, work)
    }

    private func makeStore(at url: URL, text: String) throws {
        try autoreleasepool {
            let schema = PersistenceController.localSchema
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)
            context.insert(SDDiaryEntry(date: Date(), text: text))
            try context.save()
        }
    }

    private func withDatabase(at url: URL, use: (OpaquePointer) throws -> Void) throws {
        var db: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil)
        defer { sqlite3_close(db) }
        XCTAssertEqual(result, SQLITE_OK)
        try use(XCTUnwrap(db))
    }
}
