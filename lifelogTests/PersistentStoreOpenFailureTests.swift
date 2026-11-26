import Foundation
import SQLite3
import SwiftData
import XCTest
@testable import lifelify

@MainActor
final class PersistentStoreOpenFailureTests: XCTestCase {
    func testTemporaryReadFailurePreservesDatabaseAndRetryLoadsSameDiary() throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: directory) }
        let url = directory.appendingPathComponent("default.store")
        let diaryID = UUID()
        try autoreleasepool {
            let container = try PersistenceController.openStore(at: url)
            let context = ModelContext(container)
            context.insert(SDDiaryEntry(id: diaryID, date: Date(), text: "Read after unlocking"))
            try context.save()
        }
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }

        XCTAssertThrowsError(try PersistenceController.openStore(at: url))
        XCTAssertTrue(fm.fileExists(atPath: url.path))
        XCTAssertFalse(try fm.contentsOfDirectory(atPath: directory.path).contains { $0.contains(".corrupt-") })
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        let container = try PersistenceController.openStore(at: url)
        let restored = try ModelContext(container).fetch(FetchDescriptor<SDDiaryEntry>())
        XCTAssertEqual(restored.map(\.id), [diaryID])
        XCTAssertEqual(restored.first?.text, "Read after unlocking")
    }

    func testTruncatedOrMissingMainFilePreservesItsJournals() throws {
        try withStoreURLs { group, _ in
            let wal = URL(fileURLWithPath: group.path + "-wal")
            let shm = URL(fileURLWithPath: group.path + "-shm")
            let walBytes = Data("surviving journal".utf8)
            let shmBytes = Data("surviving index".utf8)
            try walBytes.write(to: wal)
            try shmBytes.write(to: shm)
            XCTAssertThrowsError(try PersistenceController.openStore(at: group))
            XCTAssertFalse(FileManager.default.fileExists(atPath: group.path))
            for main in [Data(), Data([0]), Data(repeating: 0, count: 512)] {
                try main.write(to: group)
                XCTAssertThrowsError(try PersistenceController.openStore(at: group))
                XCTAssertEqual(try Data(contentsOf: group), main)
                XCTAssertEqual(try Data(contentsOf: wal), walBytes)
                XCTAssertEqual(try Data(contentsOf: shm), shmBytes)
            }
        }
    }

    func testLegacyMigrationRecoversCommittedWALAndPreservesOrphanedGroupJournals() throws {
        try withStoreURLs { group, legacy in
            let fm = FileManager.default
            let diaryID = UUID()
            try autoreleasepool {
                let container = try PersistenceController.openStore(at: legacy)
                let context = ModelContext(container)
                context.insert(SDDiaryEntry(id: diaryID, date: Date(), text: "Old text"))
                try context.save()
            }
            let directory = group.deletingLastPathComponent()
            let staging = directory.appendingPathComponent(".default.store.migration-staging")
            try fm.createDirectory(at: staging, withIntermediateDirectories: false)
            try Data([0]).write(to: staging.appendingPathComponent("default.store"))
            let originalWAL = Data("orphan WAL from a prior attempt".utf8)
            let originalSHM = Data("orphan SHM from a prior attempt".utf8)
            let groupWAL = URL(fileURLWithPath: group.path + "-wal")
            let groupSHM = URL(fileURLWithPath: group.path + "-shm")
            try originalWAL.write(to: groupWAL)
            try originalSHM.write(to: groupSHM)

            var connection: OpaquePointer?
            let opened = sqlite3_open_v2(legacy.path, &connection, SQLITE_OPEN_READWRITE, nil)
            defer { sqlite3_close(connection) }
            XCTAssertEqual(opened, SQLITE_OK)
            XCTAssertEqual(sqlite3_exec(connection, """
                PRAGMA journal_mode=WAL;
                PRAGMA wal_autocheckpoint=0;
                PRAGMA wal_checkpoint(TRUNCATE);
                UPDATE ZSDDIARYENTRY SET ZTEXT='Latest WAL commit';
                """, nil, nil, nil), SQLITE_OK)
            XCTAssertGreaterThan(try Data(contentsOf: URL(fileURLWithPath: legacy.path + "-wal")).count, 32)

            XCTAssertThrowsError(try PersistenceController.resolveStoreLocation(groupStore: group, legacyStore: legacy, isExtension: true))
            let migrated = try PersistenceController.resolveStoreLocation(groupStore: group, legacyStore: legacy, isExtension: false)
            XCTAssertEqual(migrated.url, group)
            XCTAssertEqual(migrated.migratedFrom, legacy)
            XCTAssertTrue(fm.fileExists(atPath: legacy.path))
            XCTAssertFalse(fm.fileExists(atPath: staging.path))
            XCTAssertFalse(fm.fileExists(atPath: groupWAL.path))
            XCTAssertFalse(fm.fileExists(atPath: groupSHM.path))
            let archived = try XCTUnwrap(fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent.hasPrefix(".default.store.orphaned-") })
            XCTAssertEqual(try Data(contentsOf: archived.appendingPathComponent("default.store-wal")), originalWAL)
            XCTAssertEqual(try Data(contentsOf: archived.appendingPathComponent("default.store-shm")), originalSHM)
            let container = try PersistenceController.openStore(at: group)
            let entries = try ModelContext(container).fetch(FetchDescriptor<SDDiaryEntry>())
            XCTAssertEqual(entries.map(\.id), [diaryID])
            XCTAssertEqual(entries.first?.text, "Latest WAL commit")
            let reopened = try PersistenceController.resolveStoreLocation(groupStore: group, legacyStore: legacy, isExtension: true)
            XCTAssertEqual(reopened.url, group)
            XCTAssertNil(reopened.migratedFrom)
        }
    }

    func testOrphanedJournalWithoutReadableSourceDoesNotPublishEmptyGroupStore() throws {
        try withStoreURLs { group, legacy in
            let groupWAL = URL(fileURLWithPath: group.path + "-wal")
            let legacyWAL = URL(fileURLWithPath: legacy.path + "-wal")
            let bytes = Data("journal with missing main".utf8)
            try bytes.write(to: legacyWAL)
            XCTAssertThrowsError(try PersistenceController.resolveStoreLocation(groupStore: group, legacyStore: legacy, isExtension: false))
            XCTAssertEqual(try Data(contentsOf: legacyWAL), bytes)
            try FileManager.default.moveItem(at: legacyWAL, to: groupWAL)
            XCTAssertThrowsError(try PersistenceController.resolveStoreLocation(groupStore: group, legacyStore: legacy, isExtension: false))
            try Data().write(to: legacy)
            XCTAssertThrowsError(try PersistenceController.resolveStoreLocation(groupStore: group, legacyStore: legacy, isExtension: false))
            XCTAssertEqual(try Data(contentsOf: groupWAL), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: group.path))
        }
    }

    private func withStoreURLs(_ body: (URL, URL) throws -> Void) throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let group = directory.appendingPathComponent("group/default.store")
        let legacy = directory.appendingPathComponent("sandbox/default.store")
        try fm.createDirectory(at: group.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        try body(group, legacy)
    }
}
