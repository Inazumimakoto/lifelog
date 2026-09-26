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
