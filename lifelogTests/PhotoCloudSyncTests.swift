import Foundation
import XCTest
@testable import lifelify

@MainActor
final class PhotoCloudSyncTests: XCTestCase {
    private var temporaryDirectories: [URL] = []
    private var defaultsSuites: [String] = []

    override func tearDown() async throws {
        await MainActor.run {
            for directory in temporaryDirectories { try? FileManager.default.removeItem(at: directory) }
            for suite in defaultsSuites { UserDefaults.standard.removePersistentDomain(forName: suite) }
            temporaryDirectories = []
            defaultsSuites = []
        }
        try await super.tearDown()
    }

    func testSuccessfulUpload_optimizeKeepsThumbnailAndEvictsFullPhoto() async throws {
        let fixture = try makeFixture()
        fixture.service.startSync()
        await fixture.service.waitForSync()

        XCTAssertTrue(fixture.manifest.isCloudBacked(path: fixture.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fullImageURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.thumbnailURL.path))
        XCTAssertEqual(fixture.service.syncedCount, 1)
        XCTAssertEqual(fixture.service.pendingCount, 0)

        let downloaded = try await fixture.service.fetchPhotoData(at: fixture.path)
        XCTAssertEqual(downloaded, fixture.data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fullImageURL.path), "Viewing in optimize mode must not persist the full photo")
    }

    func testFailedUpload_keepsLocalPhotoAndRemainsPending() async throws {
        let backend = FakePhotoCloudBackend(uploadFails: true)
        let fixture = try makeFixture(backend: backend)
        fixture.service.startSync()
        await fixture.service.waitForSync()

        XCTAssertFalse(fixture.manifest.isCloudBacked(path: fixture.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.fullImageURL.path))
        XCTAssertEqual(fixture.service.pendingCount, 1)
        XCTAssertNotNil(fixture.service.lastError)
    }

    func testKeepAllLocal_restoresPreviouslyEvictedPhoto() async throws {
        let fixture = try makeFixture()
        fixture.service.startSync()
        await fixture.service.waitForSync()
        fixture.service.setMode(.keepAllLocal)
        await fixture.service.waitForSync()

        XCTAssertEqual(try Data(contentsOf: fixture.fullImageURL), fixture.data)
        XCTAssertEqual(fixture.service.mode, .keepAllLocal)
    }

    func testDeletionDuringUpload_removesCloudCopyAndKeepsTombstone() async throws {
        let backend = FakePhotoCloudBackend(suspendUpload: true)
        let fixture = try makeFixture(backend: backend)
        fixture.service.startSync()
        await backend.waitForUploadStart()
        try fixture.manifest.markDeleted(path: fixture.path)
        fixture.service.configure(paths: [])
        await backend.releaseUpload()
        await fixture.service.waitForSync()

        let cloudCopy = await backend.storedData(for: fixture.path)
        XCTAssertNil(cloudCopy)
        XCTAssertTrue(fixture.manifest.isDeleted(path: fixture.path))
        XCTAssertFalse(fixture.manifest.isCloudBacked(path: fixture.path))
        XCTAssertTrue(fixture.manifest.pendingDeletionPaths.isEmpty)
    }

    func testAccountChange_doesNotDeleteOriginalAccountPhotos() async throws {
        let backend = FakePhotoCloudBackend()
        let fixture = try makeFixture(backend: backend)
        fixture.service.startSync()
        await fixture.service.waitForSync()
        try fixture.manifest.markDeleted(path: fixture.path)
        fixture.service.configure(paths: [])
        await backend.setAccount("another-account")
        fixture.service.resumeSync()
        await fixture.service.waitForSync()

        let deleteCount = await backend.deleteCount
        XCTAssertEqual(deleteCount, 0)
        XCTAssertEqual(fixture.manifest.pendingDeletionPaths, [fixture.path])
        XCTAssertNotNil(fixture.service.lastError)
    }

    func testAccountChangeDuringUpload_doesNotAcknowledgeOrEvictPhoto() async throws {
        let backend = FakePhotoCloudBackend(suspendUpload: true)
        let fixture = try makeFixture(backend: backend)
        fixture.service.startSync()
        await backend.waitForUploadStart()
        await backend.setAccount("another-account")
        await backend.releaseUpload()
        await fixture.service.waitForSync()

        XCTAssertFalse(fixture.manifest.isCloudBacked(path: fixture.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.fullImageURL.path))
        XCTAssertEqual(fixture.service.pendingCount, 1)
        XCTAssertNotNil(fixture.service.lastError)
    }

    func testManifestAcknowledgmentFailure_neverEvictsLocalPhoto() async throws {
        let directory = try temporaryDirectory()
        let manifestDirectory = directory.appendingPathComponent("manifest")
        let backend = FakePhotoCloudBackend(afterUpload: {
            try FileManager.default.removeItem(at: manifestDirectory)
            try Data("not a directory".utf8).write(to: manifestDirectory)
        })
        let fixture = try makeFixture(backend: backend, directory: directory)
        fixture.service.startSync()
        await fixture.service.waitForSync()

        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.fullImageURL.path))
        XCTAssertFalse(fixture.manifest.isCloudBacked(path: fixture.path))
        XCTAssertNotNil(fixture.service.lastError)
    }

    func testManifestReload_retainsInterruptedUploadDeletionIntent() throws {
        let directory = try temporaryDirectory()
        let manifest = PhotoSyncManifest(directory: directory)
        XCTAssertTrue(try manifest.beginUpload(path: "photo.jpg", accountIdentifier: "owner"))
        try manifest.markDeleted(path: "photo.jpg")

        let restored = PhotoSyncManifest(directory: directory)
        XCTAssertEqual(restored.accountIdentifier, "owner")
        XCTAssertEqual(restored.pendingDeletionPaths, ["photo.jpg"])
        XCTAssertFalse(try restored.beginUpload(path: "photo.jpg", accountIdentifier: "owner"))
        XCTAssertThrowsError(try restored.validateAccount("another-owner"))
    }

    func testUnreadableManifest_refusesMutationWithoutOverwritingFile() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("manifest.json")
        let invalidData = Data("invalid journal".utf8)
        try invalidData.write(to: url)
        let manifest = PhotoSyncManifest(directory: directory)

        XCTAssertFalse(manifest.isReadable)
        XCTAssertThrowsError(try manifest.markDeleted(path: "photo.jpg"))
        XCTAssertThrowsError(try manifest.beginUpload(path: "photo.jpg", accountIdentifier: "owner"))
        XCTAssertEqual(try Data(contentsOf: url), invalidData)
    }

    func testDeletionDuringBackgroundRestore_doesNotLeaveRecreatedPhoto() async throws {
        let gate = PhotoFileOperationGate()
        let fixture = try makeFixture(beforeStore: { gate.block() })
        fixture.service.startSync()
        await fixture.service.waitForSync()
        fixture.service.setMode(.keepAllLocal)
        await gate.waitUntilStarted()

        // Match PhotoStorage.delete's ordering without blocking the test's main actor.
        let manifest = fixture.manifest
        let path = fixture.path
        let fullImageURL = fixture.fullImageURL
        let deletionStarted = PhotoFileOperationGate()
        let deletion = _Concurrency.Task.detached {
            deletionStarted.signalStarted()
            try manifest.markDeleted(path: path)
            try? FileManager.default.removeItem(at: fullImageURL)
        }
        await deletionStarted.waitUntilStarted()
        fixture.service.configure(paths: [])
        gate.release()
        try await deletion.value
        await fixture.service.waitForSync()

        XCTAssertTrue(manifest.isDeleted(path: path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fullImageURL.path))
    }

    func testRestoredAcknowledgmentWithMissingRemotePhoto_reuploadsBeforeEvictingOriginal() async throws {
        let backend = FakePhotoCloudBackend()
        let fixture = try makeFixture(backend: backend)
        try fixture.manifest.beginUpload(path: fixture.path, accountIdentifier: "original-account")
        try fixture.manifest.markUploaded(path: fixture.path, accountIdentifier: "original-account")
        fixture.service.startSync()
        await fixture.service.waitForSync()

        let uploaded = await backend.storedData(for: fixture.path)
        XCTAssertEqual(uploaded, fixture.data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fullImageURL.path))
        XCTAssertNil(fixture.service.lastError)
    }

    private struct Fixture {
        let service: PhotoCloudSyncService
        let manifest: PhotoSyncManifest
        let path: String
        let data: Data
        let fullImageURL: URL
        let thumbnailURL: URL
    }

    private func makeFixture(backend: FakePhotoCloudBackend = FakePhotoCloudBackend(), directory: URL? = nil,
                             beforeStore: (@Sendable () -> Void)? = nil) throws -> Fixture {
        let directory = try directory ?? temporaryDirectory()
        let fullDirectory = directory.appendingPathComponent("photos")
        let thumbnailDirectory = directory.appendingPathComponent("thumbnails")
        try FileManager.default.createDirectory(at: fullDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        let path = UUID().uuidString + ".jpg"
        let data = Data("fixture photo bytes".utf8)
        let fullImageURL = fullDirectory.appendingPathComponent(path)
        let thumbnailURL = thumbnailDirectory.appendingPathComponent(path)
        try data.write(to: fullImageURL)
        let manifest = PhotoSyncManifest(directory: directory.appendingPathComponent("manifest"))
        let files = PhotoSyncFiles(
            fullImageURL: { fullDirectory.appendingPathComponent($0) },
            thumbnailURL: { thumbnailDirectory.appendingPathComponent($0) },
            fullImageExists: { FileManager.default.fileExists(atPath: fullDirectory.appendingPathComponent($0).path) },
            ensureThumbnail: { try Data("thumbnail".utf8).write(to: thumbnailDirectory.appendingPathComponent($0)) },
            removeFullImage: { try FileManager.default.removeItem(at: fullDirectory.appendingPathComponent($0)) },
            storeFullImage: { data, path in
                beforeStore?()
                try data.write(to: fullDirectory.appendingPathComponent(path))
            }
        )
        let suite = "PhotoCloudSyncTests." + UUID().uuidString
        defaultsSuites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let service = PhotoCloudSyncService(manifest: manifest, backend: backend, files: files, defaults: defaults)
        service.configure(paths: [path])
        return Fixture(service: service, manifest: manifest, path: path, data: data,
                       fullImageURL: fullImageURL, thumbnailURL: thumbnailURL)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoCloudSyncTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }
}

nonisolated private final class PhotoFileOperationGate: @unchecked Sendable {
    private let started = DispatchSemaphore(value: 0)
    private let continuation = DispatchSemaphore(value: 0)

    func signalStarted() { started.signal() }
    func block() {
        signalStarted()
        continuation.wait()
    }
    func release() { continuation.signal() }
    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                started.wait()
                continuation.resume()
            }
        }
    }
}

private actor FakePhotoCloudBackend: PhotoCloudBackend {
    enum Failure: Error { case uploadFailed, missingPhoto }
    private var account = "original-account"
    private var photos: [String: Data] = [:]
    private let uploadFails: Bool
    private let suspendUpload: Bool
    private let afterUpload: (@Sendable () throws -> Void)?
    private var uploadStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var uploadGate: CheckedContinuation<Void, Never>?
    private(set) var deleteCount = 0

    init(uploadFails: Bool = false, suspendUpload: Bool = false, afterUpload: (@Sendable () throws -> Void)? = nil) {
        self.uploadFails = uploadFails
        self.suspendUpload = suspendUpload
        self.afterUpload = afterUpload
    }

    func accountIdentifier() async throws -> String { account }

    func upload(path: String, fullImageURL: URL, thumbnailURL: URL) async throws {
        let data = try Data(contentsOf: fullImageURL)
        uploadStarted = true
        startWaiters.forEach { $0.resume() }
        startWaiters = []
        if suspendUpload { await withCheckedContinuation { uploadGate = $0 } }
        if uploadFails { throw Failure.uploadFailed }
        photos[path] = data
        try afterUpload?()
    }

    func delete(path: String) async throws {
        deleteCount += 1
        photos[path] = nil
    }

    func containsPhoto(path: String) async throws -> Bool { photos[path] != nil }

    func fetch(path: String, thumbnail: Bool) async throws -> Data {
        guard let data = photos[path] else { throw Failure.missingPhoto }
        return thumbnail ? Data("thumbnail".utf8) : data
    }

    func storedData(for path: String) -> Data? { photos[path] }
    func setAccount(_ identifier: String) { account = identifier }

    func waitForUploadStart() async {
        if uploadStarted { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseUpload() {
        uploadGate?.resume()
        uploadGate = nil
    }
}
