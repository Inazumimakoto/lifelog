//
//  Persistence.swift
//  lifelog
//
//  Created for SwiftData Migration
//

import Darwin
import Foundation
import SQLite3
import SwiftData
import os

// ウィジェット拡張ターゲットとファイルを共有するため、AppLogger は使用せず
// ファイルローカルのロガーを定義する
private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lifelog", category: "data")

struct PersistenceController {
    @MainActor private static var cachedContainer: ModelContainer?

    let container: ModelContainer

    // App Group IDs (must be present in app/widget entitlements)
    private static let defaultAppGroupIdentifier = "group.lifelog.share"
    private static let screenshotsAppGroupIdentifier = "group.lifelog.screenshots"
    private static let activeAppGroupDefaultsKey = "lifelog.activeAppGroupIdentifier"
    private static let simulatorDemoModeKey = "lifelog.simulatorDemoMode"
    private static let screenshotsLaunchArguments: Set<String> = [
        "-screenshots-mode",
        "-ScreenshotsMode",
    ]

    private static var isRunningInExtension: Bool {
        Bundle.main.bundleURL.pathExtension == "appex" ||
        Bundle.main.object(forInfoDictionaryKey: "NSExtension") != nil
    }

    static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil ||
            environment["XCTestBundlePath"] != nil ||
            environment["XCTestSessionIdentifier"] != nil || NSClassFromString("XCTestCase") != nil
    }

    /// Debug simulator launches use an isolated demo by default. Explicit opt-out
    /// and XCTest hosts retain the normal store; device/Release never enable it.
    static var isSimulatorDemoMode: Bool {
        #if DEBUG && targetEnvironment(simulator)
        guard !isRunningTests else { return false }
        guard let defaults = UserDefaults(suiteName: screenshotsAppGroupIdentifier) else { return false }
        let storedPreference = defaults.object(forKey: simulatorDemoModeKey) as? Bool
        let enabled = simulatorDemoModePreference(
            arguments: Set(ProcessInfo.processInfo.arguments),
            storedPreference: storedPreference,
            isRunningInExtension: isRunningInExtension,
            isRunningTests: isRunningTests
        )
        if !isRunningInExtension, storedPreference != enabled {
            defaults.set(enabled, forKey: simulatorDemoModeKey)
        }
        return enabled
        #else
        return false
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    static func simulatorDemoModePreference(arguments: Set<String>, storedPreference: Bool?,
                                           isRunningInExtension: Bool, isRunningTests: Bool) -> Bool {
        guard !isRunningTests else { return false }
        if isRunningInExtension { return storedPreference ?? false }
        if arguments.contains("-simulator-demo-off") { return false }
        if arguments.contains("-simulator-demo-data") ||
            !screenshotsLaunchArguments.isDisjoint(with: arguments) { return true }
        return storedPreference ?? true
    }
    #endif

    private static var isScreenshotsModeLaunch: Bool {
        #if DEBUG && targetEnvironment(simulator)
        guard !isRunningTests else { return false }
        let arguments = Set(ProcessInfo.processInfo.arguments)
        guard !arguments.contains("-simulator-demo-off") else { return false }
        return screenshotsLaunchArguments.isDisjoint(with: arguments) == false
        #else
        return false
        #endif
    }

    /// Active App Group used by app + widgets.
    ///
    /// - App launch:
    ///   - Debug simulator demo -> screenshots group, separate demo store
    ///   - explicit opt-out, device, Release, XCTest -> normal group
    /// - Widget extension:
    ///   - follows the latest app selection stored in shared defaults.
    static var appGroupIdentifier: String {
        let selected: String
        if isSimulatorDemoMode || isScreenshotsModeLaunch {
            selected = screenshotsAppGroupIdentifier
        } else if isRunningInExtension {
            selected = persistedActiveAppGroupIdentifier ?? defaultAppGroupIdentifier
        } else {
            selected = defaultAppGroupIdentifier
        }

        persistActiveAppGroupIdentifierIfNeeded(selected)
        return selected
    }

    private static var persistedActiveAppGroupIdentifier: String? {
        guard let defaults = UserDefaults(suiteName: defaultAppGroupIdentifier) else { return nil }
        guard let value = defaults.string(forKey: activeAppGroupDefaultsKey) else { return nil }
        let allowed = [defaultAppGroupIdentifier, screenshotsAppGroupIdentifier]
        return allowed.contains(value) ? value : nil
    }

    private static func persistActiveAppGroupIdentifierIfNeeded(_ identifier: String) {
        guard isRunningInExtension == false else { return }
        guard let defaults = UserDefaults(suiteName: defaultAppGroupIdentifier) else { return }
        defaults.set(identifier, forKey: activeAppGroupDefaultsKey)
    }

    /// Local app and widgets share exactly the native data schema. Retired sync
    /// journals were scalar sidecars and are removed by lightweight migration;
    /// native records and their photo paths remain in the existing store.
    static var localSchema: Schema {
        Schema([
            SDTask.self,
            SDDiaryEntry.self,
            SDHabit.self,
            SDHabitRecord.self,
            SDAnniversary.self,
            SDHealthSummary.self,
            SDCalendarEvent.self,
            SDCalendarEventException.self,
            SDMemoPad.self,
            SDAppState.self,
            SDLetter.self,
            SDSharedLetter.self,
            SDShoppingItem.self,
            SDShoppingPlace.self
        ])
    }

    // Previews and tests use a private, ephemeral container.
    init(inMemory: Bool) {
        precondition(inMemory, "Open the persistent store with sharedContainer()")
        let schema = Self.localSchema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create in-memory ModelContainer: \(error)")
        }
    }

    /// Cache only successful opens. Unlocking the device or freeing disk space can make a retry succeed.
    @MainActor
    static func sharedContainer() throws -> ModelContainer {
        if let cachedContainer { return cachedContainer }
        let location = try resolveStoreURL()
        let container = try openStore(at: location.url)
        if let migratedFrom = location.migratedFrom {
            // Delete the legacy files only after SwiftData actually opens the new copy.
            for suffix in ["-shm", "-wal", ""] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: migratedFrom.path + suffix))
            }
        }
        cachedContainer = container
        return container
    }

    static func openStore(at url: URL) throws -> ModelContainer {
        try validateStoreFiles(at: url)
        let schema = localSchema
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        // 1.18.0 moved even healthy stores aside on a transient access error.
        // Propagate the failure and leave the database and its journal together.
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    // Set by 1.18.0 and earlier.
    static let storeRecoveryOccurredKey = "lifelog.storeRecoveryOccurred"

    /// App Group 内のストアURLを決定し、必要なら Sandbox からの移行を行う
    private static func resolveStoreURL() throws -> (url: URL, migratedFrom: URL?) {
        let fileManager = FileManager.default

        // A demo must never import, move, or fall back to the user's normal store.
        if isSimulatorDemoMode {
            guard let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: screenshotsAppGroupIdentifier) else {
                throw CocoaError(.fileReadNoPermission)
            }
            return (groupURL.appendingPathComponent("simulator-demo.store"), nil)
        }

        let sandboxURL = URL.applicationSupportDirectory.appendingPathComponent("default.store")

        guard let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            if try fileIsPresent(at: sandboxURL) { return (sandboxURL, nil) }
            throw CocoaError(.fileReadNoPermission)
        }
        return try resolveStoreLocation(groupStore: groupURL.appendingPathComponent("default.store"),
                                        legacyStore: sandboxURL, isExtension: isRunningInExtension)
    }

    static func resolveStoreLocation(groupStore: URL, legacyStore: URL, isExtension: Bool) throws
        -> (url: URL, migratedFrom: URL?) {
        if try fileIsPresent(at: groupStore) { return (groupStore, nil) }
        // An extension cannot determine whether a database still exists in the host sandbox.
        if isExtension { throw CocoaError(.fileReadNoSuchFile) }
        try validateStoreFiles(at: legacyStore)
        if try fileIsPresent(at: legacyStore) {
            do {
                let published = try migrateStore(from: legacyStore, to: groupStore)
                return (groupStore, published ? legacyStore : nil)
            } catch {
                if try fileIsPresent(at: groupStore) { return (groupStore, nil) }
                logger.error("Failed to migrate store, using the original store: \(error)")
                return (legacyStore, nil)
            }
        }
        try validateStoreFiles(at: groupStore)
        return (groupStore, nil)
    }

    private static let journalSuffixes = ["-wal", "-shm", "-journal"]

    private static func fileIsPresent(at url: URL) throws -> Bool {
        do {
            _ = try FileManager.default.attributesOfItem(atPath: url.path)
            return true
        } catch let error as CocoaError where [.fileReadNoSuchFile, .fileNoSuchFile].contains(error.code) {
            return false
        }
    }

    private static func validateStoreFiles(at url: URL) throws {
        let fm = FileManager.default
        guard try fileIsPresent(at: url) else {
            for suffix in journalSuffixes {
                if try fileIsPresent(at: URL(fileURLWithPath: url.path + suffix)) {
                    throw CocoaError(.fileReadCorruptFile)
                }
            }
            return
        }
        // SQLite can reinitialize a zero-byte main file and truncate its surviving WAL.
        // A real SQLite database has at least one 512-byte page and this fixed signature.
        let attributes = try fm.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.int64Value ?? 0 >= 512 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let signature = Data("SQLite format 3\0".utf8)
        guard try handle.read(upToCount: signature.count) == signature else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    /// Fold committed WAL frames into one database, then atomically publish it. A killed
    /// migration can be retried from the source without attaching unrelated group journals.
    private static func migrateStore(from source: URL, to destination: URL) throws -> Bool {
        let fm = FileManager.default
        let directory = destination.deletingLastPathComponent()
        let lockURL = directory.appendingPathComponent(".\(destination.lastPathComponent).migration-lock")
        let lock = Darwin.open(lockURL.path, O_RDWR | O_CREAT, 0o600)
        guard lock >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { Darwin.close(lock) }
        guard flock(lock, LOCK_EX) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        if try fileIsPresent(at: destination) { return false }

        let staging = directory.appendingPathComponent(".\(destination.lastPathComponent).migration-staging", isDirectory: true)
        if try fileIsPresent(at: staging) { try fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let snapshot = staging.appendingPathComponent(destination.lastPathComponent)
        try writeSnapshot(from: source, to: snapshot)
        #if os(iOS)
        if let protection = try fm.attributesOfItem(atPath: source.path)[.protectionKey] {
            try fm.setAttributes([.protectionKey: protection], ofItemAtPath: snapshot.path)
        }
        #endif

        let orphaned = try journalSuffixes.map { URL(fileURLWithPath: destination.path + $0) }
            .filter { try fileIsPresent(at: $0) }
        if !orphaned.isEmpty {
            // No matching main file exists. Preserve these bytes together without pairing them
            // with another generation, even if the process is killed partway through cleanup.
            let saved = directory.appendingPathComponent(".\(destination.lastPathComponent).orphaned-\(UUID())", isDirectory: true)
            try fm.createDirectory(at: saved, withIntermediateDirectories: false)
            for file in orphaned { try fm.copyItem(at: file, to: saved.appendingPathComponent(file.lastPathComponent)) }
            for file in orphaned { try fm.removeItem(at: file) }
        }
        // A hard link on the same volume is atomic and cannot overwrite a live database.
        try fm.linkItem(at: snapshot, to: destination)
        return true
    }

    private static func writeSnapshot(from source: URL, to snapshot: URL) throws {
        var reader: OpaquePointer?
        let readResult = sqlite3_open_v2(source.path, &reader, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(reader) }
        guard readResult == SQLITE_OK else { throw CocoaError(.fileReadUnknown) }
        var writer: OpaquePointer?
        let writeResult = sqlite3_open_v2(snapshot.path, &writer, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        defer { sqlite3_close(writer) }
        guard writeResult == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        guard let backup = sqlite3_backup_init(writer, "main", reader, "main") else { throw CocoaError(.fileReadUnknown) }
        let copied = sqlite3_backup_step(backup, -1)
        let finished = sqlite3_backup_finish(backup)
        guard copied == SQLITE_DONE, finished == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        // Switching to DELETE mode checkpoints the result and drops the destination sidecars
        // before the single .store file becomes visible to the app and its widgets.
        for (query, expected) in [("PRAGMA journal_mode=DELETE", "delete"),
                                  ("PRAGMA quick_check(1)", "ok"),
                                  ("SELECT 1 FROM Z_METADATA LIMIT 1", "1")] {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(writer, query, -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0),
                  String(cString: text) == expected else { throw CocoaError(.fileReadCorruptFile) }
        }
    }

    // For SwiftUI Previews
    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        return result
    }()
}
