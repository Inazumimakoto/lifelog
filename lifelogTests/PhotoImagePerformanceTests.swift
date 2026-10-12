import CryptoKit
import Foundation
import UIKit
import XCTest
@testable import lifelify

@MainActor
final class PhotoImagePerformanceTests: XCTestCase {
    func testRetinaImage_cacheCostUsesPixelBufferInsteadOfPointSize() throws {
        let image = makeImage(size: CGSize(width: 80, height: 40), scale: 3)
        let pixels = try XCTUnwrap(image.cgImage)

        XCTAssertEqual(PhotoThumbnailCache.decodedCost(of: image), pixels.bytesPerRow * pixels.height)
        XCTAssertGreaterThan(PhotoThumbnailCache.decodedCost(of: image), 80 * 40 * 4)
    }

    func testOversizedImage_cacheRejectsItAndRemovesPriorEntry() {
        let cache = PhotoThumbnailCache(fullImageCostLimit: 16_384, thumbnailCostLimit: 16_384)
        let small = makeImage(size: CGSize(width: 20, height: 20))
        let oversized = makeImage(size: CGSize(width: 200, height: 200))
        cache.setFullImage(small, for: "photo.jpg")
        cache.setThumbnail(small, for: "photo.jpg")
        XCTAssertNotNil(cache.fullImage(for: "photo.jpg"))
        XCTAssertNotNil(cache.thumbnail(for: "photo.jpg"))

        cache.setFullImage(oversized, for: "photo.jpg")
        cache.setThumbnail(oversized, for: "photo.jpg")

        XCTAssertNil(cache.fullImage(for: "photo.jpg"))
        XCTAssertNil(cache.thumbnail(for: "photo.jpg"))
    }

    func testMemoryWarning_releasesBothImageCaches() {
        let cache = PhotoThumbnailCache()
        let image = makeImage(size: CGSize(width: 20, height: 20))
        cache.setFullImage(image, for: "photo.jpg")
        cache.setThumbnail(image, for: "photo.jpg")

        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)

        XCTAssertNil(cache.fullImage(for: "photo.jpg"))
        XCTAssertNil(cache.thumbnail(for: "photo.jpg"))
    }

    func testImageLoad_operationRunsOffMainThreadAndPreservesOriginalPixels() async throws {
        let image = makeImage(size: CGSize(width: 800, height: 500), scale: 3)
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        let loader = PhotoImageLoader()

        let loaded = await loader.load(key: "original") {
            XCTAssertFalse(Thread.isMainThread)
            return PhotoImageLoader.preparedImage(from: data)
        }

        let pixels = try XCTUnwrap(loaded?.cgImage)
        XCTAssertEqual(pixels.width, 2_400)
        XCTAssertEqual(pixels.height, 1_500)
    }

    func testPreviewLoad_doesNotMigrateOriginalFingerprints() async throws {
        let path = "PhotoImagePerformanceTests-" + UUID().uuidString + ".jpg"
        let originalURL = PhotoStorage.localFileURL(for: path)
        let files = DiaryPhotoFiles(directory: originalURL.deletingLastPathComponent())
        let fingerprintURL = originalURL.deletingLastPathComponent()
            .appendingPathComponent("Fingerprints", isDirectory: true)
            .appendingPathComponent(path + ".json")
        defer {
            try? files.removeFiles(at: path)
            try? FileManager.default.removeItem(at: fingerprintURL)
            PhotoThumbnailCache.shared.removeImages(for: path)
        }
        let original = try XCTUnwrap(makeImage(size: CGSize(width: 800, height: 500))
            .jpegData(compressionQuality: 0.9))
        try files.writeOriginal(original, at: path)

        let preview = await PhotoStorage.loadThumbnail(at: path)

        XCTAssertNotNil(preview)
        XCTAssertEqual(preview?.cgImage?.width, 512)
        XCTAssertTrue(files.thumbnailExists(at: path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fingerprintURL.path))
        XCTAssertEqual(try Data(contentsOf: originalURL), original)
    }

    func testCancelledImageRequest_doesNotStartDecode() async {
        let loader = PhotoImageLoader()
        let request = _Concurrency.Task { @MainActor in
            await loader.load(key: "cancelled") {
                XCTFail("A request cancelled before loading must not decode an image")
                return nil
            }
        }
        request.cancel()

        let image = await request.value

        XCTAssertNil(image)
    }

    func testEmptyIdentityIndex_skipsVisualDecode() {
        let index = PhotoIdentityIndex(assetIdentifiers: [:], digests: [:], visualDigests: [:])

        XCTAssertNil(index.matchingPath(assetIdentifier: nil, data: Data("new photo".utf8)) { _ in
            XCTFail("A photo cannot match an empty index, so decoding it is unnecessary")
            return nil
        })
    }

    func testIdentityMatching_preservesAssetByteAndVisualPriority() {
        let data = Data("photo bytes".utf8)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let index = PhotoIdentityIndex(assetIdentifiers: ["asset": ["asset.jpg"]],
                                      digests: [digest: ["byte.jpg"]],
                                      visualDigests: ["visual": ["visual.jpg"]])

        XCTAssertEqual(index.matchingPath(assetIdentifier: "asset", data: data) { _ in
            XCTFail("An asset match must not decode pixels")
            return "visual"
        }, "asset.jpg")
        XCTAssertEqual(index.matchingPath(assetIdentifier: nil, data: data) { _ in
            XCTFail("A byte match must not decode pixels")
            return "visual"
        }, "byte.jpg")
        XCTAssertEqual(index.matchingPath(assetIdentifier: nil, data: Data("different bytes".utf8)) { _ in
            "visual"
        }, "visual.jpg")
    }

    func testLinkIdentity_assetIdentifierAvoidsFingerprintRead() {
        func unexpectedFingerprint() -> PhotoStorage.Fingerprint? {
            XCTFail("An asset identifier must avoid decoding/hashing the original")
            return nil
        }

        XCTAssertEqual(PhotoIdentityIndex.linkIdentity(assetIdentifier: "asset",
                                                       fingerprint: unexpectedFingerprint()), "asset:asset")
    }

    func testLinkIdentity_emptyIdentifiersUseVisualThenByteFallback() {
        XCTAssertEqual(PhotoIdentityIndex.linkIdentity(
            assetIdentifier: "", fingerprint: PhotoStorage.Fingerprint(digest: "bytes", visualDigest: "visual")
        ), "visual:visual")
        XCTAssertEqual(PhotoIdentityIndex.linkIdentity(
            assetIdentifier: nil, fingerprint: PhotoStorage.Fingerprint(digest: "bytes", visualDigest: "")
        ), "digest:bytes")
        XCTAssertNil(PhotoIdentityIndex.linkIdentity(assetIdentifier: nil, fingerprint: nil))
    }

    private func makeImage(size: CGSize, scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.setFillColor(UIColor.blue.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
