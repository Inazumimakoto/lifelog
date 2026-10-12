//
//  PhotoStorage.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import SwiftUI
import UIKit
import CryptoKit
import os

// MARK: - Thumbnail Cache
nonisolated final class PhotoThumbnailCache: @unchecked Sendable {
    static let shared = PhotoThumbnailCache()
    
    private let fullSizeCache = NSCache<NSString, UIImage>()
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let fullImageCostLimit: Int
    private let thumbnailCostLimit: Int
    private var memoryWarningObserver: NSObjectProtocol?
    
    init(fullImageCostLimit: Int = 64 * 1_024 * 1_024,
         thumbnailCostLimit: Int = 32 * 1_024 * 1_024) {
        self.fullImageCostLimit = fullImageCostLimit
        self.thumbnailCostLimit = thumbnailCostLimit
        // Original pixel buffers are much larger than the JPEGs on disk.
        // Keep a few recent photos, rather than up to twenty decoded originals.
        fullSizeCache.countLimit = 3
        fullSizeCache.totalCostLimit = fullImageCostLimit
        thumbnailCache.countLimit = 100
        thumbnailCache.totalCostLimit = thumbnailCostLimit
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.clearAll()
        }
    }

    deinit {
        if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
    }
    
    // フルサイズ画像
    func fullImage(for path: String) -> UIImage? {
        fullSizeCache.object(forKey: path as NSString)
    }
    
    func setFullImage(_ image: UIImage, for path: String) {
        setImage(image, for: path, in: fullSizeCache, costLimit: fullImageCostLimit)
    }
    
    // サムネイル画像
    func thumbnail(for path: String) -> UIImage? {
        thumbnailCache.object(forKey: path as NSString)
    }
    
    func setThumbnail(_ image: UIImage, for path: String) {
        setImage(image, for: path, in: thumbnailCache, costLimit: thumbnailCostLimit)
    }

    private func setImage(_ image: UIImage, for path: String, in cache: NSCache<NSString, UIImage>, costLimit: Int) {
        let cost = Self.decodedCost(of: image)
        // NSCache's limit is advisory. The visible page owns an oversized image;
        // neither cache may retain it after that page releases it.
        guard cost <= costLimit else {
            cache.removeObject(forKey: path as NSString)
            return
        }
        cache.setObject(image, forKey: path as NSString, cost: cost)
    }
    
    func removeFullImage(for path: String) {
        fullSizeCache.removeObject(forKey: path as NSString)
    }

    func removeImages(for path: String) {
        removeFullImage(for: path)
        thumbnailCache.removeObject(forKey: path as NSString)
    }

    func clearAll() {
        fullSizeCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
    }

    static func decodedCost(of image: UIImage) -> Int {
        if let pixels = image.cgImage { return pixels.bytesPerRow * pixels.height }
        return Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }
}

// MARK: - Photo Storage
nonisolated struct PhotoStorage {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lifelog", category: "photos")
    private static let directoryName = "DiaryPhotos"
    private static let jpegCompressionQuality: CGFloat = 0.8  // JPEG圧縮品質
    private static let assetIdentifierFilename = "PhotoAssetIdentifiers.json"
    private static let assetIdentifierQueue = DispatchQueue(label: "PhotoStorage.AssetIdentifierQueue")
    nonisolated(unsafe) private static var cachedAssetIdentifierMap: [String: String]?

    private static let photosDirectory: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = documents.appendingPathComponent(directoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create photos directory: \(error)")
        }
        return dir
    }()

    private static let files = DiaryPhotoFiles(directory: photosDirectory)
    private static let photoFilesQueue = DispatchQueue(label: "PhotoStorage.Files")

    private static var assetIdentifierFileURL: URL {
        photosDirectory.appendingPathComponent(assetIdentifierFilename)
    }

    // MARK: - Save
    static func save(data: Data, sourceAssetIdentifier: String? = nil) throws -> String {
        let filename = UUID().uuidString + ".jpg"
        // JPEG 0.8で再エンコードして容量削減（解像度は維持）
        let dataToWrite: Data
        if let uiImage = UIImage(data: data),
           let compressed = uiImage.jpegData(compressionQuality: jpegCompressionQuality) {
            dataToWrite = compressed
        } else {
            // UIImage化できない場合は元データをそのまま保存
            dataToWrite = data
        }
        try files.writeOriginal(dataToWrite, at: filename)
        // A failed preview never discards the only original; sync retries generation.
        try? ensureThumbnail(at: filename)
        if let sourceAssetIdentifier, sourceAssetIdentifier.isEmpty == false {
            setAssetIdentifier(sourceAssetIdentifier, for: filename)
        }
        return filename
    }

    // MARK: - Save (Async)
    static func saveAsync(data: Data, sourceAssetIdentifier: String? = nil) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let path = try save(data: data, sourceAssetIdentifier: sourceAssetIdentifier)
                    continuation.resume(returning: path)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func assetIdentifierIndex(for paths: [String]) -> [String: [String]] {
        assetIdentifierQueue.sync {
            let map = loadAssetIdentifierMapUnlocked()
            var index: [String: [String]] = [:]
            for path in paths {
                guard let identifier = map[path] else { continue }
                index[identifier, default: []].append(path)
            }
            return index
        }
    }

    static func assetIdentifierMap(for paths: [String]) -> [String: String] {
        assetIdentifierQueue.sync {
            let map = loadAssetIdentifierMapUnlocked()
            var result: [String: String] = [:]
            for path in paths {
                guard let identifier = map[path] else { continue }
                result[path] = identifier
            }
            return result
        }
    }

    private static let identityWorkQueue = DispatchQueue(label: "PhotoStorage.Identity", qos: .userInitiated)

    /// Legacy identity migration may read/hash an original and render its visual
    /// digest. Photo importing must await that work instead of blocking input.
    static func identityIndex(for paths: [String]) async -> PhotoIdentityIndex {
        await performIdentityWork {
            var digests: [String: [String]] = [:]
            var visualDigests: [String: [String]] = [:]
            for path in paths {
                guard let value = fingerprint(for: path) else { continue }
                digests[value.digest, default: []].append(path)
                if let visualDigest = value.visualDigest {
                    visualDigests[visualDigest, default: []].append(path)
                }
            }
            return PhotoIdentityIndex(assetIdentifiers: assetIdentifierIndex(for: paths),
                                      digests: digests, visualDigests: visualDigests)
        }
    }

    static func matchingPhotoPath(assetIdentifier: String?, data: Data,
                                  in index: PhotoIdentityIndex) async -> String? {
        guard !_Concurrency.Task.isCancelled else { return nil }
        return await performIdentityWork {
            index.matchingPath(assetIdentifier: assetIdentifier, data: data)
        }
    }

    static func identityMap(for paths: [String]) async -> [String: String] {
        await performIdentityWork { makeIdentityMap(for: paths) }
    }

    /// The synchronous edit path uses identities prewarmed by the async picker.
    /// Both paths must apply the same asset/visual/byte identity precedence.
    static func makeIdentityMap(for paths: [String]) -> [String: String] {
        let identifiers = assetIdentifierMap(for: paths)
        var identities: [String: String] = [:]
        for path in paths {
            identities[path] = PhotoIdentityIndex.linkIdentity(assetIdentifier: identifiers[path],
                                                              fingerprint: fingerprint(for: path))
        }
        return identities
    }

    private static func performIdentityWork<Result: Sendable>(
        _ operation: @escaping @Sendable () -> Result
    ) async -> Result {
        await withCheckedContinuation { continuation in
            identityWorkQueue.async {
                continuation.resume(returning: autoreleasepool(invoking: operation))
            }
        }
    }

    // MARK: - Load (Sync - 後方互換性のため残す)
    static func loadImage(at path: String) -> Image? {
        if let cached = PhotoThumbnailCache.shared.fullImage(for: path) {
            return Image(uiImage: cached)
        }
        let url = photosDirectory.appendingPathComponent(path)
        guard let uiImage = UIImage(contentsOfFile: url.path) else { return nil }
        PhotoThumbnailCache.shared.setFullImage(uiImage, for: path)
        return Image(uiImage: uiImage)
    }

    // MARK: - Load Raw Data
    static func loadData(at path: String) -> Data? {
        let url = photosDirectory.appendingPathComponent(path)
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }
    
    // MARK: - Persistent thumbnails and on-demand originals
    static func localFileURL(for path: String) -> URL { files.fullImageURL(for: path) }
    static func thumbnailFileURL(for path: String) -> URL { files.thumbnailURL(for: path) }

    static func ensureThumbnail(at path: String) throws {
        try photoFilesQueue.sync {
            try files.prepareThumbnail(at: path)
            _ = fingerprint(for: path)
        }
    }

    static func removeLocalFullImage(at path: String) throws {
        try photoFilesQueue.sync {
            try files.removeOriginal(at: path)
            PhotoThumbnailCache.shared.removeFullImage(for: path)
        }
    }

    static func storeDownloadedData(_ data: Data, at path: String) throws {
        try photoFilesQueue.sync {
            try files.writeOriginal(data, at: path)
            try files.prepareThumbnail(at: path)
            _ = fingerprint(for: path)
        }
    }

    static func loadThumbnail(at path: String) async -> UIImage? {
        guard !_Concurrency.Task.isCancelled, !PhotoSyncManifest.shared.isDeleted(path: path) else { return nil }
        if let cached = PhotoThumbnailCache.shared.thumbnail(for: path) { return cached }
        let local = await PhotoImageLoader.shared.load(key: "thumbnail:" + path) {
            loadLocalThumbnail(at: path)
        }
        guard !_Concurrency.Task.isCancelled, !PhotoSyncManifest.shared.isDeleted(path: path) else { return nil }
        var image = local
        if image == nil, PhotoSyncManifest.shared.isCloudBacked(path: path),
           let data = try? await PhotoCloudSyncService.shared.fetchThumbnailData(at: path) {
            guard !_Concurrency.Task.isCancelled else { return nil }
            image = await PhotoImageLoader.shared.load(key: "downloaded-thumbnail:" + path) {
                if let account = PhotoSyncManifest.shared.accountIdentifier {
                    _ = try? PhotoSyncManifest.shared.withLivePhoto(path: path, accountIdentifier: account) {
                        try photoFilesQueue.sync { try files.writeThumbnail(data, at: path) }
                    }
                }
                return PhotoImageLoader.preparedImage(from: data)
            }
        }
        guard !_Concurrency.Task.isCancelled, !PhotoSyncManifest.shared.isDeleted(path: path) else { return nil }
        if let image { PhotoThumbnailCache.shared.setThumbnail(image, for: path) }
        return image
    }

    static func loadFullImage(at path: String) async -> UIImage? {
        guard !_Concurrency.Task.isCancelled, !PhotoSyncManifest.shared.isDeleted(path: path) else { return nil }
        if let cached = PhotoThumbnailCache.shared.fullImage(for: path) { return cached }
        let local = await PhotoImageLoader.shared.load(key: "original:" + path) {
            PhotoImageLoader.preparedImage(at: localFileURL(for: path))
        }
        guard !_Concurrency.Task.isCancelled, !PhotoSyncManifest.shared.isDeleted(path: path) else { return nil }
        if let local {
            // Only retain a memory cache while the original still exists on disk.
            if fileExists(for: path) { PhotoThumbnailCache.shared.setFullImage(local, for: path) }
            return local
        }
        guard let data = try? await PhotoCloudSyncService.shared.fetchPhotoData(at: path),
              !_Concurrency.Task.isCancelled, !PhotoSyncManifest.shared.isDeleted(path: path) else { return nil }
        // Optimized downloads are owned only by the visible viewer, never a disk cache.
        let image = await PhotoImageLoader.shared.load(key: "downloaded-original:" + path) {
            PhotoImageLoader.preparedImage(from: data)
        }
        guard !_Concurrency.Task.isCancelled, !PhotoSyncManifest.shared.isDeleted(path: path) else { return nil }
        return image
    }

    private static func loadLocalThumbnail(at path: String) -> UIImage? {
        guard !PhotoSyncManifest.shared.isDeleted(path: path) else { return nil }
        if let cached = PhotoThumbnailCache.shared.thumbnail(for: path) { return cached }
        let url = thumbnailFileURL(for: path)
        if let image = PhotoImageLoader.preparedImage(at: url) { return image }
        // Displaying a preview does not need a SHA/visual fingerprint of the
        // original. Save/cloud eviction still create that durable identity.
        try? photoFilesQueue.sync { try files.prepareThumbnail(at: path) }
        return PhotoImageLoader.preparedImage(at: url)
    }

    // MARK: - Prefetch
    private static let prefetchQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated  // 高優先度
        return queue
    }()

    private static let backgroundPrefetchQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        return queue
    }()

    private static let prefetchLock = NSLock()
    nonisolated(unsafe) private static var pendingPrefetchPaths = Set<String>()
    
    static func prefetchThumbnails(paths: [String]) {
        enqueueThumbnailPrefetch(paths: paths, on: prefetchQueue)
    }

    static func prefetchThumbnailsInBackground(paths: [String]) {
        enqueueThumbnailPrefetch(paths: paths, on: backgroundPrefetchQueue)
    }

    private static func enqueueThumbnailPrefetch(paths: [String], on queue: OperationQueue) {
        var seen = Set<String>()
        for path in paths where seen.insert(path).inserted {
            // 既にキャッシュにあればスキップ
            if PhotoThumbnailCache.shared.thumbnail(for: path) != nil {
                continue
            }

            prefetchLock.lock()
            let needsPrefetch = pendingPrefetchPaths.insert(path).inserted
            prefetchLock.unlock()
            guard needsPrefetch else { continue }

            // Deduplicate overlapping month/background prefetch requests.
            queue.addOperation {
                defer {
                    prefetchLock.lock()
                    pendingPrefetchPaths.remove(path)
                    prefetchLock.unlock()
                }
                guard !PhotoSyncManifest.shared.isDeleted(path: path) else { return }
                let thumbnail = PhotoImageLoader.shared.perform {
                    loadLocalThumbnail(at: path)
                }
                guard let thumbnail, !PhotoSyncManifest.shared.isDeleted(path: path) else { return }
                PhotoThumbnailCache.shared.setThumbnail(thumbnail, for: path)
            }
        }
    }

    // MARK: - Delete
    /// The durable deletion intent is saved before the diary drops its reference.
    @discardableResult
    static func delete(at path: String) -> Bool {
        do {
            try PhotoSyncManifest.shared.markDeleted(path: path)
        } catch {
            _Concurrency.Task { @MainActor in PhotoCloudSyncService.shared.report(error: error) }
            return false
        }
        photoFilesQueue.sync { try? files.removeFiles(at: path) }
        removeAssetIdentifier(for: path)
        fingerprintQueue.sync {
            cachedFingerprints.removeValue(forKey: path)
            let url = photosDirectory.appendingPathComponent("Fingerprints", isDirectory: true)
                .appendingPathComponent((path as NSString).lastPathComponent + ".json")
            try? FileManager.default.removeItem(at: url)
        }
        PhotoThumbnailCache.shared.removeImages(for: path)
        _Concurrency.Task { @MainActor in PhotoCloudSyncService.shared.resumeSync() }
        return true
    }

    static func fileExists(for path: String) -> Bool { files.originalExists(at: path) }

    private static func loadAssetIdentifierMapUnlocked() -> [String: String] {
        if let cachedAssetIdentifierMap {
            return cachedAssetIdentifierMap
        }
        guard let data = try? Data(contentsOf: assetIdentifierFileURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            cachedAssetIdentifierMap = [:]
            return [:]
        }
        cachedAssetIdentifierMap = decoded
        return decoded
    }

    private static func persistAssetIdentifierMapUnlocked(_ map: [String: String]) {
        cachedAssetIdentifierMap = map
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: assetIdentifierFileURL, options: .atomic)
    }

    private static func setAssetIdentifier(_ identifier: String, for path: String) {
        assetIdentifierQueue.sync {
            var map = loadAssetIdentifierMapUnlocked()
            map[path] = identifier
            persistAssetIdentifierMapUnlocked(map)
        }
    }

    private static func removeAssetIdentifier(for path: String) {
        assetIdentifierQueue.sync {
            var map = loadAssetIdentifierMapUnlocked()
            guard map.removeValue(forKey: path) != nil else { return }
            persistAssetIdentifierMapUnlocked(map)
        }
    }
    /// Includes persistent thumbnails; cloud assets are not counted as local storage.
    static func totalStorageSize() -> Int64 { files.totalSize() }

    // Identity is preserved when a full image is evicted, so location linking keeps working.
    struct Fingerprint: Codable, Sendable {
        let digest: String
        let visualDigest: String?
    }

    private static let fingerprintQueue = DispatchQueue(label: "PhotoStorage.Fingerprints")
    nonisolated(unsafe) private static var cachedFingerprints: [String: Fingerprint] = [:]

    static func fingerprint(for path: String) -> Fingerprint? {
        fingerprintQueue.sync {
            if let existing = cachedFingerprints[path] { return existing }
            let directory = photosDirectory.appendingPathComponent("Fingerprints", isDirectory: true)
            let url = directory.appendingPathComponent((path as NSString).lastPathComponent + ".json")
            if let data = try? Data(contentsOf: url),
               let stored = try? JSONDecoder().decode(Fingerprint.self, from: data) {
                cachedFingerprints[path] = stored
                return stored
            }
            guard let data = loadData(at: path) else { return nil }
            let value = Fingerprint(digest: digestHex(for: data),
                                    visualDigest: visualDigest(for: data))
            // One tiny sidecar per image avoids rewriting the whole index during bulk migration.
            if let encoded = try? JSONEncoder().encode(value) {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? encoded.write(to: url, options: .atomic)
            }
            cachedFingerprints[path] = value
            return value
        }
    }

    static func visualDigest(for data: Data) -> String? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let targetSize = CGSize(width: 256, height: 256)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: targetSize))
            let scale = min(targetSize.width / image.size.width, targetSize.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (targetSize.width - size.width) / 2,
                                  y: (targetSize.height - size.height) / 2,
                                  width: size.width, height: size.height))
        }
        guard let normalized = rendered.pngData() else { return nil }
        return digestHex(for: normalized)
    }

    static func digestHex(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

}

// MARK: - Async Image View (SwiftUI)
struct AsyncThumbnailImage: View {
    let path: String
    let size: CGFloat
    
    @State private var image: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                ProgressView()
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: path) {
            image = nil
            isLoading = true
            let loadedImage = await PhotoStorage.loadThumbnail(at: path)
            guard !_Concurrency.Task.isCancelled else { return }
            image = loadedImage
            isLoading = false
        }
    }
}
