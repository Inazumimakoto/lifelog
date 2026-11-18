import Foundation
import UIKit
import XCTest
@testable import lifelify

/// File-level guarantees that keep diary previews available after cloud optimization.
@MainActor
final class DiaryPhotoFilesTests: XCTestCase {
    func testLargeRetinaImage_thumbnailIsLimitedTo512ActualPixels() throws {
        let files = try makeFiles()
        let original = try makeImageData()
        let source = try XCTUnwrap(UIImage(data: original)?.cgImage)
        XCTAssertEqual(source.width, 2_400)
        XCTAssertEqual(source.height, 1_500)
        try files.writeOriginal(original, at: "photo.jpg")

        try files.prepareThumbnail(at: "photo.jpg")

        let thumbnailData = try Data(contentsOf: files.thumbnailURL(for: "photo.jpg"))
        let thumbnail = try XCTUnwrap(UIImage(data: thumbnailData)?.cgImage)
        XCTAssertEqual(thumbnail.width, 512)
        XCTAssertEqual(thumbnail.height, 320)
        XCTAssertLessThan(thumbnailData.count, original.count)
    }

    func testOriginalEviction_previewSurvivesAndCanBeLoadedByNewStorageInstance() throws {
        let files = try makeFiles()
        try files.writeOriginal(makeImageData(), at: "photo.jpg")
        try files.prepareThumbnail(at: "photo.jpg")
        let preview = try Data(contentsOf: files.thumbnailURL(for: "photo.jpg"))

        try files.removeOriginal(at: "photo.jpg")

        let restored = DiaryPhotoFiles(directory: files.directory)
        XCTAssertFalse(restored.originalExists(at: "photo.jpg"))
        XCTAssertTrue(restored.thumbnailExists(at: "photo.jpg"))
        XCTAssertNoThrow(try restored.prepareThumbnail(at: "photo.jpg"))
        let retainedPreview = try Data(contentsOf: restored.thumbnailURL(for: "photo.jpg"))
        XCTAssertEqual(retainedPreview, preview)
        XCTAssertNotNil(UIImage(data: retainedPreview)?.cgImage)
    }

    func testMissingThumbnail_refusesEvictionAndPreservesOriginal() throws {
        let files = try makeFiles()
        let original = try makeImageData()
        try files.writeOriginal(original, at: "photo.jpg")

        XCTAssertThrowsError(try files.removeOriginal(at: "photo.jpg")) { error in
            guard case DiaryPhotoFiles.StorageError.missingThumbnail = error else {
                return XCTFail("Expected missingThumbnail, got \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: files.fullImageURL(for: "photo.jpg")), original)
    }

    func testCorruptThumbnail_refusesEvictionAndPreservesOriginal() throws {
        let files = try makeFiles()
        let original = try makeImageData()
        try files.writeOriginal(original, at: "photo.jpg")
        try files.prepareThumbnail(at: "photo.jpg")
        try Data("corrupt image".utf8).write(to: files.thumbnailURL(for: "photo.jpg"))

        XCTAssertThrowsError(try files.removeOriginal(at: "photo.jpg")) { error in
            guard case DiaryPhotoFiles.StorageError.missingThumbnail = error else {
                return XCTFail("Expected missingThumbnail, got \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: files.fullImageURL(for: "photo.jpg")), original)
    }

    func testRestoredOriginal_preservesStoredBytesWithoutFurtherCompression() throws {
        let files = try makeFiles()
        let storedOriginal = try makeImageData()
        try files.writeOriginal(storedOriginal, at: "photo.jpg")
        try files.prepareThumbnail(at: "photo.jpg")
        XCTAssertEqual(try Data(contentsOf: files.fullImageURL(for: "photo.jpg")), storedOriginal)
        try files.removeOriginal(at: "photo.jpg")

        // Downloading the cloud copy must restore the bytes that were uploaded.
        try files.writeOriginal(storedOriginal, at: "photo.jpg")
        try files.prepareThumbnail(at: "photo.jpg")

        XCTAssertEqual(try Data(contentsOf: files.fullImageURL(for: "photo.jpg")), storedOriginal)
    }

    func testInvalidFilenames_allThrowingOperationsRejectTraversal() throws {
        let files = try makeFiles()
        let original = try makeImageData()
        try files.writeOriginal(original, at: "photo.jpg")
        try files.prepareThumbnail(at: "photo.jpg")
        let thumbnail = try Data(contentsOf: files.thumbnailURL(for: "photo.jpg"))
        let invalidPaths = ["", ".", "..", "../photo.jpg", "nested/photo.jpg", "/photo.jpg"]

        for path in invalidPaths {
            let operations: [() throws -> Void] = [
                { try files.writeOriginal(original, at: path) },
                { try files.writeThumbnail(original, at: path) },
                { try files.prepareThumbnail(at: path) },
                { try files.removeOriginal(at: path) },
                { try files.removeFiles(at: path) }
            ]
            for operation in operations {
                XCTAssertThrowsError(try operation(), "Invalid path: \(path)") { error in
                    guard case DiaryPhotoFiles.StorageError.invalidFilename = error else {
                        return XCTFail("Expected invalidFilename for \(path), got \(error)")
                    }
                }
            }
        }

        XCTAssertEqual(try Data(contentsOf: files.fullImageURL(for: "photo.jpg")), original)
        XCTAssertEqual(try Data(contentsOf: files.thumbnailURL(for: "photo.jpg")), thumbnail)
        XCTAssertEqual(files.totalSize(), Int64(original.count + thumbnail.count))
    }

    func testStorageSize_countsPersistentThumbnailAfterOriginalEviction() throws {
        let files = try makeFiles()
        let original = try makeImageData()
        try files.writeOriginal(original, at: "photo.jpg")
        try files.prepareThumbnail(at: "photo.jpg")
        let thumbnail = try Data(contentsOf: files.thumbnailURL(for: "photo.jpg"))

        XCTAssertEqual(files.totalSize(), Int64(original.count + thumbnail.count))
        try files.removeOriginal(at: "photo.jpg")

        XCTAssertEqual(files.totalSize(), Int64(thumbnail.count))
    }

    func testDeletingPhoto_removesOriginalAndPersistentThumbnail() throws {
        let files = try makeFiles()
        try files.writeOriginal(makeImageData(), at: "photo.jpg")
        try files.prepareThumbnail(at: "photo.jpg")

        try files.removeFiles(at: "photo.jpg")

        XCTAssertFalse(files.originalExists(at: "photo.jpg"))
        XCTAssertFalse(files.thumbnailExists(at: "photo.jpg"))
        XCTAssertEqual(files.totalSize(), 0)
        XCTAssertNoThrow(try files.removeFiles(at: "photo.jpg"), "Deletion retries must be safe")
    }

    func testVideoContainerDetection_distinguishesMoviesFromImages() {
        for path in ["video.mov", "video.mp4", "video.MOV", "video.m4v"] {
            XCTAssertTrue(DiaryPhotoFiles.isVideo(at: path), path)
        }
        for path in ["photo.jpg", "photo.heic", "photo.png", "unknown", "photo.gif"] {
            XCTAssertFalse(DiaryPhotoFiles.isVideo(at: path), path)
        }
    }

    func testVideoThumbnail_survivesOriginalEvictionAndIsLimitedTo512Pixels() throws {
        let files = try makeFiles()
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "diary-video-fixture", withExtension: "mov"))
        try files.copyOriginal(from: source, at: "video.mov")

        try files.prepareThumbnail(at: "video.mov")

        let thumbnail = try XCTUnwrap(UIImage(contentsOfFile: files.thumbnailURL(for: "video.mov").path)?.cgImage)
        XCTAssertEqual(thumbnail.width, 512)
        XCTAssertEqual(thumbnail.height, 288)
        try files.removeOriginal(at: "video.mov")
        XCTAssertFalse(files.originalExists(at: "video.mov"))
        XCTAssertTrue(files.thumbnailExists(at: "video.mov"))
        XCTAssertNoThrow(try files.prepareThumbnail(at: "video.mov"))
    }

    func testFileCopy_preservesOriginalBytesAndCanReplaceDownloadedOriginal() throws {
        let files = try makeFiles()
        let source = files.directory.appendingPathComponent("source.mov")
        let first = Data(repeating: 0x42, count: 32_768)
        try first.write(to: source)

        try files.copyOriginal(from: source, at: "video.mov")
        XCTAssertEqual(try Data(contentsOf: files.fullImageURL(for: "video.mov")), first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "Picker transfer ownership is separate")
        let second = Data("restored movie".utf8)
        try second.write(to: source)
        try files.copyOriginal(from: source, at: "video.mov")
        XCTAssertEqual(try Data(contentsOf: files.fullImageURL(for: "video.mov")), second)
        XCTAssertThrowsError(try files.copyOriginal(from: source, at: "../video.mov"))
    }

    func testStreamingMovieFingerprint_matchesDataDigestAcrossChunkBoundaries() throws {
        let files = try makeFiles()
        let bytes = Data((0..<2_100_003).map { UInt8($0 % 251) })
        let url = files.directory.appendingPathComponent("video.mov")
        try bytes.write(to: url)

        XCTAssertEqual(try PhotoStorage.digestHex(forFileAt: url), PhotoStorage.digestHex(for: bytes))
    }

    func testPlaybackSnapshot_survivesOriginalRemovalAndReleasesOnlyOwnedFile() throws {
        let files = try makeFiles()
        let source = files.directory.appendingPathComponent("video.mov")
        let bytes = Data("video fixture".utf8)
        try bytes.write(to: source)
        let playbackURL = try PhotoStorage.makeVideoPlaybackCopy(from: source, path: "video.mov")
        defer { PhotoStorage.releaseVideoURL(playbackURL) }

        PhotoStorage.releaseVideoURL(source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "Release must leave persistent originals alone")
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try Data(contentsOf: playbackURL), bytes)
        PhotoStorage.releaseVideoURL(playbackURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: playbackURL.path))
    }

    private func makeFiles() throws -> DiaryPhotoFiles {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiaryPhotoFilesTests-" + UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return DiaryPhotoFiles(directory: directory)
    }

    private func makeImageData() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 500), format: format)
        let image = renderer.image { context in
            context.cgContext.setFillColor(UIColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 500))
            context.cgContext.setFillColor(UIColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1).cgColor)
            context.fill(CGRect(x: 100, y: 100, width: 400, height: 250))
            context.cgContext.setStrokeColor(UIColor.white.cgColor)
            context.cgContext.setLineWidth(12)
            context.cgContext.move(to: CGPoint(x: 0, y: 0))
            context.cgContext.addLine(to: CGPoint(x: 800, y: 500))
            context.cgContext.strokePath()
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.97))
    }
}
