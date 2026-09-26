import Foundation

/// Small, backed-up journal for diary photo uploads and deletion intents.
/// A photo's existing UUID filename remains its identity during migration.
nonisolated final class PhotoSyncManifest: @unchecked Sendable {
    static let shared: PhotoSyncManifest = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return PhotoSyncManifest(directory: support.appendingPathComponent("DiaryPhotoSync", isDirectory: true))
    }()

    struct Record: Codable, Equatable, Sendable {
        var uploaded = false
        var uploadAttempted = false
        var deleted = false
    }

    private struct State: Codable, Sendable {
        var version = 1
        var accountIdentifier: String?
        var records: [String: Record] = [:]
    }

    private let lock = NSLock()
    private let fileURL: URL
    private var state = State()
    private var readError: Error?

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("manifest.json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                state = try JSONDecoder().decode(State.self, from: Data(contentsOf: fileURL))
                if state.version != 1 { readError = PhotoCloudSyncError.manifestUnreadable }
            } catch {
                // Never overwrite an unreadable journal with an empty one.
                readError = PhotoCloudSyncError.manifestUnreadable
            }
        }
    }

    var isReadable: Bool { locked { readError == nil } }
    var accountIdentifier: String? { locked { state.accountIdentifier } }

    func isCloudBacked(path: String) -> Bool {
        locked { state.records[path]?.uploaded == true && state.records[path]?.deleted != true }
    }

    func isDeleted(path: String) -> Bool {
        locked { state.records[path]?.deleted == true }
    }

    var pendingDeletionPaths: [String] {
        locked {
            state.records.compactMap { path, record in
                record.deleted && (record.uploaded || record.uploadAttempted) ? path : nil
            }.sorted()
        }
    }

    func validateAccount(_ identifier: String) throws {
        try locked {
            if let readError { throw readError }
            if let owner = state.accountIdentifier, owner != identifier {
                throw PhotoCloudSyncError.differentAccount
            }
        }
    }

    /// Serialize a local file mutation with deletion intent. The operation must not
    /// call back into this manifest. A later deletion removes its files after this returns.
    func withLivePhoto<T>(path: String, accountIdentifier: String, operation: () throws -> T) throws -> T? {
        try locked {
            if let readError { throw readError }
            if let owner = state.accountIdentifier, owner != accountIdentifier {
                throw PhotoCloudSyncError.differentAccount
            }
            guard state.records[path]?.deleted != true else { return nil }
            return try operation()
        }
    }

    /// Written before any network request, so deletion can recover after a crash.
    @discardableResult
    func beginUpload(path: String, accountIdentifier: String) throws -> Bool {
        try mutate { state in
            if let owner = state.accountIdentifier, owner != accountIdentifier {
                throw PhotoCloudSyncError.differentAccount
            }
            guard state.records[path]?.deleted != true else { return false }
            state.accountIdentifier = accountIdentifier
            var record = state.records[path] ?? Record()
            record.uploadAttempted = true
            state.records[path] = record
            return true
        }
    }

    func markUploaded(path: String, accountIdentifier: String) throws {
        try mutate { state in
            guard state.accountIdentifier == accountIdentifier else {
                throw PhotoCloudSyncError.differentAccount
            }
            var record = state.records[path] ?? Record()
            // Preserve a deletion requested while the upload was in flight.
            record.uploaded = true
            record.uploadAttempted = true
            state.records[path] = record
        }
    }

    /// Call before removing local files or references. A failed write must abort deletion.
    func markDeleted(path: String) throws {
        try mutate { state in
            var record = state.records[path] ?? Record()
            record.deleted = true
            state.records[path] = record
        }
    }

    func markDeletionSucceeded(path: String) throws {
        try mutate { state in
            guard var record = state.records[path], record.deleted else { return }
            record.uploaded = false
            record.uploadAttempted = false
            state.records[path] = record
        }
    }

    private func locked<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    private func mutate<T>(_ operation: (inout State) throws -> T) throws -> T {
        try locked {
            if let readError { throw readError }
            var updated = state
            let result = try operation(&updated)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(updated)
            try data.write(to: fileURL, options: .atomic)
            state = updated
            return result
        }
    }
}
