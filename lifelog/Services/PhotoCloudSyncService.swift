import CloudKit
import Combine
import Foundation
import Network

nonisolated enum PhotoStorageMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case optimizeStorage
    case keepAllLocal

    var id: String { rawValue }
}

nonisolated enum PhotoCloudSyncError: Error, LocalizedError {
    case notSignedIn
    case accountUnavailable
    case differentAccount
    case manifestUnreadable
    case missingLocalPhoto
    case missingCloudPhoto
    case invalidCloudPhoto

    var errorDescription: String? {
        switch self {
        case .notSignedIn: String(localized: "photoStorage.error.notSignedIn")
        case .accountUnavailable: String(localized: "photoStorage.error.accountUnavailable")
        case .differentAccount: String(localized: "photoStorage.error.differentAccount")
        case .manifestUnreadable: String(localized: "photoStorage.error.manifestUnreadable")
        case .missingLocalPhoto: String(localized: "photoStorage.error.missingLocalPhoto")
        case .missingCloudPhoto: String(localized: "photoStorage.error.missingCloudPhoto")
        case .invalidCloudPhoto: String(localized: "photoStorage.error.invalidCloudPhoto")
        }
    }
}

nonisolated protocol PhotoCloudBackend: Sendable {
    func accountIdentifier() async throws -> String
    func upload(path: String, fullImageURL: URL, thumbnailURL: URL) async throws
    func containsPhoto(path: String) async throws -> Bool
    func delete(path: String) async throws
    func fetch(path: String, thumbnail: Bool) async throws -> Data
}

nonisolated final class CloudKitPhotoBackend: PhotoCloudBackend, @unchecked Sendable {
    private let container: CKContainer
    private var database: CKDatabase { container.privateCloudDatabase }

    init(container: CKContainer = CKContainer(identifier: "iCloud.com.inazumimakoto.lifelog")) {
        self.container = container
    }

    func accountIdentifier() async throws -> String {
        switch try await container.accountStatus() {
        case .available:
            return try await container.userRecordID().recordName
        case .noAccount:
            throw PhotoCloudSyncError.notSignedIn
        default:
            throw PhotoCloudSyncError.accountUnavailable
        }
    }

    func upload(path: String, fullImageURL: URL, thumbnailURL: URL) async throws {
        let record = CKRecord(recordType: "DiaryPhoto", recordID: recordID(path))
        record["photo"] = CKAsset(fileURL: fullImageURL)
        record["thumbnail"] = CKAsset(fileURL: thumbnailURL)
        record["filename"] = path as CKRecordValue
        // Repeating an interrupted upload uses the same record identity.
        let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys, atomically: false)
        guard let saved = result.saveResults[record.recordID] else {
            throw PhotoCloudSyncError.invalidCloudPhoto
        }
        _ = try saved.get()
    }

    func delete(path: String) async throws {
        do {
            _ = try await database.deleteRecord(withID: recordID(path))
        } catch let error as CKError where error.code == .unknownItem {
            // A previous attempt may already have deleted the record.
        }
    }

    func containsPhoto(path: String) async throws -> Bool {
        let id = recordID(path)
        let records = try await database.records(for: [id], desiredKeys: ["filename"])
        guard let result = records[id] else { throw PhotoCloudSyncError.invalidCloudPhoto }
        do {
            let record = try result.get()
            guard record["filename"] as? String == path else { throw PhotoCloudSyncError.invalidCloudPhoto }
            return true
        } catch let error as CKError where error.code == .unknownItem {
            return false
        }
    }

    func fetch(path: String, thumbnail: Bool) async throws -> Data {
        let id = recordID(path)
        let key = thumbnail ? "thumbnail" : "photo"
        let records = try await database.records(for: [id], desiredKeys: [key])
        guard let result = records[id] else { throw PhotoCloudSyncError.missingCloudPhoto }
        let record: CKRecord
        do {
            record = try result.get()
        } catch let error as CKError where error.code == .unknownItem {
            throw PhotoCloudSyncError.missingCloudPhoto
        }
        guard let asset = record[key] as? CKAsset, let url = asset.fileURL else {
            throw PhotoCloudSyncError.invalidCloudPhoto
        }
        // CloudKit owns the temporary asset file. Keep only the returned bytes.
        return try await _Concurrency.Task.detached(priority: .userInitiated) {
            try Data(contentsOf: url)
        }.value
    }

    private func recordID(_ path: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "diary-photo-" + path)
    }
}

/// File operations are injectable so sync transitions can be tested without iCloud.
nonisolated struct PhotoSyncFiles: Sendable {
    var fullImageURL: @Sendable (String) -> URL
    var thumbnailURL: @Sendable (String) -> URL
    var fullImageExists: @Sendable (String) -> Bool
    var ensureThumbnail: @Sendable (String) throws -> Void
    var removeFullImage: @Sendable (String) throws -> Void
    var storeFullImage: @Sendable (Data, String) throws -> Void

    static let live = PhotoSyncFiles(
        fullImageURL: { PhotoStorage.localFileURL(for: $0) },
        thumbnailURL: { PhotoStorage.thumbnailFileURL(for: $0) },
        fullImageExists: { PhotoStorage.fileExists(for: $0) },
        ensureThumbnail: { try PhotoStorage.ensureThumbnail(at: $0) },
        removeFullImage: { try PhotoStorage.removeLocalFullImage(at: $0) },
        storeFullImage: { try PhotoStorage.storeDownloadedData($0, at: $1) }
    )
}

/// Photo-only CloudKit storage; the diary database remains local and is backed up by iOS.
/// See docs/requirements.md: diary photo storage and device-space optimization.
@MainActor
final class PhotoCloudSyncService: ObservableObject {
    static let shared = PhotoCloudSyncService(
        manifest: .shared,
        backend: CloudKitPhotoBackend(),
        files: .live,
        defaults: .standard,
        allowsCloud: !PersistenceController.isSimulatorDemoMode &&
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil &&
            ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" &&
            Set(["-screenshots-mode", "-ScreenshotsMode", "-simulator-demo-data"])
                .isDisjoint(with: ProcessInfo.processInfo.arguments),
        observesEnvironment: true
    )

    @Published private(set) var mode: PhotoStorageMode
    @Published private(set) var isEnabled: Bool
    @Published private(set) var isSyncing = false
    @Published private(set) var completedCount = 0
    @Published private(set) var totalCount = 0
    @Published private(set) var pendingCount = 0
    @Published private(set) var syncedCount = 0
    @Published private(set) var lastError: String?

    private let manifest: PhotoSyncManifest
    private let backend: any PhotoCloudBackend
    private let files: PhotoSyncFiles
    private let defaults: UserDefaults
    private let allowsCloud: Bool
    private var paths: Set<String> = []
    private var syncTask: _Concurrency.Task<Void, Never>?
    private var rerunRequested = false
    private var fetchTasks: [String: _Concurrency.Task<Data, Error>] = [:]
    private var networkMonitor: NWPathMonitor?
    private var accountObserver: NSObjectProtocol?

    init(manifest: PhotoSyncManifest, backend: any PhotoCloudBackend, files: PhotoSyncFiles,
         defaults: UserDefaults, allowsCloud: Bool = true, observesEnvironment: Bool = false) {
        self.manifest = manifest
        self.backend = backend
        self.files = files
        self.defaults = defaults
        self.allowsCloud = allowsCloud
        mode = defaults.string(forKey: "diaryPhotoStorageMode").flatMap(PhotoStorageMode.init(rawValue:)) ?? .optimizeStorage
        isEnabled = defaults.bool(forKey: "diaryPhotoCloudSyncEnabled")
        if allowsCloud && observesEnvironment { observeEnvironmentChanges() }
    }

    func configure(paths: [String]) {
        self.paths = Set(paths)
        refreshCounts()
    }

    func startSync() {
        guard allowsCloud else { return }
        isEnabled = true
        defaults.set(true, forKey: "diaryPhotoCloudSyncEnabled")
        resumeSync()
    }

    func resumeSync() {
        guard allowsCloud, isEnabled else { return }
        if syncTask != nil {
            rerunRequested = true
            return
        }
        syncTask = _Concurrency.Task { [weak self] in
            guard let self else { return }
            repeat {
                rerunRequested = false
                await syncOnce()
            } while rerunRequested
            syncTask = nil
        }
    }

    func setMode(_ mode: PhotoStorageMode) {
        self.mode = mode
        defaults.set(mode.rawValue, forKey: "diaryPhotoStorageMode")
        resumeSync()
    }

    func report(error: Error) {
        lastError = message(for: error)
        refreshCounts()
    }

    func fetchPhotoData(at path: String) async throws -> Data {
        try await fetchData(at: path, thumbnail: false)
    }

    func fetchThumbnailData(at path: String) async throws -> Data {
        try await fetchData(at: path, thumbnail: true)
    }

    /// Used by deterministic state-transition tests and callers awaiting a manual run.
    func waitForSync() async {
        await syncTask?.value
    }

    private func fetchData(at path: String, thumbnail: Bool) async throws -> Data {
        guard allowsCloud else { throw PhotoCloudSyncError.accountUnavailable }
        guard manifest.isCloudBacked(path: path), !manifest.isDeleted(path: path) else {
            throw PhotoCloudSyncError.missingCloudPhoto
        }
        let key = (thumbnail ? "thumbnail:" : "photo:") + path
        if let existing = fetchTasks[key] { return try await existing.value }
        let task = _Concurrency.Task { [self] in
            let account = try await checkedAccount()
            let data = try await backend.fetch(path: path, thumbnail: thumbnail)
            try await verifyAccount(account)
            guard !manifest.isDeleted(path: path) else { throw PhotoCloudSyncError.missingCloudPhoto }
            if !thumbnail && mode == .keepAllLocal {
                guard paths.contains(path) else { throw PhotoCloudSyncError.missingCloudPhoto }
                try await performFileOperation(path: path, account: account) { files in
                    try files.storeFullImage(data, path)
                }
                try await verifyAccount(account)
                guard !manifest.isDeleted(path: path), paths.contains(path) else {
                    throw PhotoCloudSyncError.missingCloudPhoto
                }
                // A mode switch during the disk write must not leave a persistent original.
                if mode == .optimizeStorage {
                    try await performFileOperation(path: path, account: account) { files in
                        try files.removeFullImage(path)
                    }
                }
            }
            return data
        }
        fetchTasks[key] = task
        defer { fetchTasks[key] = nil }
        return try await task.value
    }

    private func syncOnce() async {
        isSyncing = true
        lastError = nil
        completedCount = 0
        let deletions = manifest.pendingDeletionPaths
        let livePaths = paths.filter { path in
            guard !manifest.isDeleted(path: path) else { return false }
            if !manifest.isCloudBacked(path: path) { return true }
            return mode == .keepAllLocal ? !files.fullImageExists(path) : files.fullImageExists(path)
        }.sorted()
        totalCount = deletions.count + livePaths.count
        defer {
            isSyncing = false
            refreshCounts()
        }
        guard !deletions.isEmpty || !livePaths.isEmpty else { return }
        do {
            let account = try await checkedAccount()
            for path in deletions {
                do {
                    try await deleteCloudPhoto(path, account: account)
                } catch {
                    lastError = message(for: error)
                }
                completedCount += 1
            }
            for path in livePaths {
                guard paths.contains(path), !manifest.isDeleted(path: path) else {
                    completedCount += 1
                    continue
                }
                do {
                    try await syncPhoto(path, account: account)
                } catch {
                    lastError = message(for: error)
                }
                completedCount += 1
                refreshCounts()
            }
        } catch {
            lastError = message(for: error)
        }
    }

    private func syncPhoto(_ path: String, account: String) async throws {
        try await verifyAccount(account)
        var needsUpload = !manifest.isCloudBacked(path: path)
        if !needsUpload && mode == .optimizeStorage && files.fullImageExists(path) {
            // A restored backup can contain an old acknowledgment after the remote
            // copy was deleted. Never evict its original solely on that old marker.
            needsUpload = !(try await backend.containsPhoto(path: path))
            try await verifyAccount(account)
        }
        guard paths.contains(path), !manifest.isDeleted(path: path) else { return }
        if needsUpload {
            guard files.fullImageExists(path) else { throw PhotoCloudSyncError.missingLocalPhoto }
            try await performFileOperation(path: path, account: account) { files in
                try files.ensureThumbnail(path)
            }
            try await verifyAccount(account)
            guard paths.contains(path), !manifest.isDeleted(path: path) else { return }
            guard try manifest.beginUpload(path: path, accountIdentifier: account) else { return }
            try await backend.upload(path: path, fullImageURL: files.fullImageURL(path), thumbnailURL: files.thumbnailURL(path))
            // An account change during the request must never authorize local eviction.
            try await verifyAccount(account)
            // The durable acknowledgment must precede eviction of the only local copy.
            try manifest.markUploaded(path: path, accountIdentifier: account)
        }
        if manifest.isDeleted(path: path) {
            try await deleteCloudPhoto(path, account: account)
            return
        }
        guard paths.contains(path) else { return }
        switch mode {
        case .optimizeStorage:
            // A thumbnail must exist even for uploads completed in a previous launch.
            if files.fullImageExists(path) {
                try await performFileOperation(path: path, account: account) { files in
                    try files.ensureThumbnail(path)
                }
                try await verifyAccount(account)
                guard mode == .optimizeStorage, paths.contains(path), !manifest.isDeleted(path: path) else { return }
                try await performFileOperation(path: path, account: account) { files in
                    try files.removeFullImage(path)
                }
            }
        case .keepAllLocal:
            if !files.fullImageExists(path) {
                _ = try await fetchPhotoData(at: path)
            }
        }
    }

    private func deleteCloudPhoto(_ path: String, account: String) async throws {
        try await verifyAccount(account)
        try await backend.delete(path: path)
        try await verifyAccount(account)
        try manifest.markDeletionSucceeded(path: path)
    }

    private func performFileOperation(path: String, account: String,
                                      operation: @escaping @Sendable (PhotoSyncFiles) throws -> Void) async throws {
        let manifest = manifest
        let files = files
        try await _Concurrency.Task.detached(priority: .utility) {
            let performed: Void? = try manifest.withLivePhoto(path: path, accountIdentifier: account) {
                try operation(files)
            }
            guard performed != nil else { throw PhotoCloudSyncError.missingCloudPhoto }
        }.value
    }

    private func checkedAccount() async throws -> String {
        let account = try await backend.accountIdentifier()
        try manifest.validateAccount(account)
        return account
    }

    private func verifyAccount(_ expected: String) async throws {
        guard try await checkedAccount() == expected else { throw PhotoCloudSyncError.differentAccount }
    }

    private func refreshCounts() {
        let current = paths.filter { !manifest.isDeleted(path: $0) }
        syncedCount = current.filter { manifest.isCloudBacked(path: $0) }.count
        pendingCount = current.count - syncedCount
    }

    private func observeEnvironmentChanges() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            _Concurrency.Task { @MainActor [weak self] in self?.resumeSync() }
        }
        monitor.start(queue: DispatchQueue(label: "PhotoCloudSync.Network"))
        networkMonitor = monitor
        accountObserver = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            _Concurrency.Task { @MainActor [weak self] in self?.resumeSync() }
        }
    }

    private func message(for error: Error) -> String {
        guard let error = error as? CKError else { return error.localizedDescription }
        switch error.code {
        case .quotaExceeded:
            return String(localized: "photoStorage.error.quotaExceeded")
        case .networkUnavailable, .networkFailure:
            return String(localized: "photoStorage.error.networkUnavailable")
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return String(localized: "photoStorage.error.retryLater")
        case .notAuthenticated:
            return String(localized: "photoStorage.error.notSignedIn")
        default:
            return error.localizedDescription
        }
    }
}
