//
//  PhotoStorage.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Thumbnail Cache
final class PhotoThumbnailCache {
    static let shared = PhotoThumbnailCache()
    
    private let fullSizeCache = NSCache<NSString, UIImage>()
    private let thumbnailCache = NSCache<NSString, UIImage>()
    
    private init() {
        // メモリ制限を設定
        fullSizeCache.countLimit = 20
        thumbnailCache.countLimit = 100
    }
    
    // フルサイズ画像
    func fullImage(for path: String) -> UIImage? {
        fullSizeCache.object(forKey: path as NSString)
    }
    
    func setFullImage(_ image: UIImage, for path: String) {
        fullSizeCache.setObject(image, forKey: path as NSString)
    }
    
    // サムネイル画像
    func thumbnail(for path: String) -> UIImage? {
        thumbnailCache.object(forKey: path as NSString)
    }
    
    func setThumbnail(_ image: UIImage, for path: String) {
        thumbnailCache.setObject(image, forKey: path as NSString)
    }
    
    func clearAll() {
        fullSizeCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
    }
}

// MARK: - Photo Storage
struct PhotoStorage {
    private static let directoryName = "DiaryPhotos"
    private static let thumbnailSize: CGFloat = 200  // サムネイルサイズ
    private static let jpegCompressionQuality: CGFloat = 0.8  // JPEG圧縮品質
    private static let assetIdentifierFilename = "PhotoAssetIdentifiers.json"
    private static let assetIdentifierQueue = DispatchQueue(label: "PhotoStorage.AssetIdentifierQueue")
    private static var cachedAssetIdentifierMap: [String: String]?

    private static var photosDirectory: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = documents.appendingPathComponent(directoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("Failed to create photos directory:", error)
        }
        return dir
    }()

    private static var assetIdentifierFileURL: URL {
        photosDirectory.appendingPathComponent(assetIdentifierFilename)
    }

    // MARK: - Save
    static func save(data: Data, sourceAssetIdentifier: String? = nil) throws -> String {
        let filename = UUID().uuidString + ".jpg"
        let url = photosDirectory.appendingPathComponent(filename)
        // JPEG 0.8で再エンコードして容量削減（解像度は維持）
        let dataToWrite: Data
        if let uiImage = UIImage(data: data),
           let compressed = uiImage.jpegData(compressionQuality: jpegCompressionQuality) {
            dataToWrite = compressed
        } else {
            // UIImage化できない場合は元データをそのまま保存
            dataToWrite = data
        }
        try dataToWrite.write(to: url, options: .atomic)
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
    
    // MARK: - Load Thumbnail (Async)
    static func loadThumbnail(at path: String) async -> UIImage? {
        // キャッシュチェック
        if let cached = PhotoThumbnailCache.shared.thumbnail(for: path) {
            return cached
        }
        
        // バックグラウンドで読み込み＆リサイズ
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let url = photosDirectory.appendingPathComponent(path)
                guard let uiImage = UIImage(contentsOfFile: url.path) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // サムネイル生成
                let thumbnail = resizeImage(uiImage, to: thumbnailSize)
                PhotoThumbnailCache.shared.setThumbnail(thumbnail, for: path)
                
                continuation.resume(returning: thumbnail)
            }
        }
    }
    
    // MARK: - Load Full Image (Async)
    static func loadFullImage(at path: String) async -> UIImage? {
        // キャッシュチェック
        if let cached = PhotoThumbnailCache.shared.fullImage(for: path) {
            return cached
        }
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let url = photosDirectory.appendingPathComponent(path)
                guard let uiImage = UIImage(contentsOfFile: url.path) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                PhotoThumbnailCache.shared.setFullImage(uiImage, for: path)
                continuation.resume(returning: uiImage)
            }
        }
    }
    
    // MARK: - Resize Helper
    private static func resizeImage(_ image: UIImage, to maxSize: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(maxSize / size.width, maxSize / size.height)
        
        // 既に十分小さい場合はそのまま返す
        if scale >= 1.0 {
            return image
        }
        
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    // MARK: - Prefetch (バックグラウンドで並列先読み)
    private static let prefetchQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4  // 4並列で読み込み
        queue.qualityOfService = .userInitiated  // 高優先度
        return queue
    }()

    private static let backgroundPrefetchQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2  // UI負荷を抑えるため控えめに並列化
        queue.qualityOfService = .utility
        return queue
    }()
    
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

            // 並列でキューに追加
            queue.addOperation {
                let url = photosDirectory.appendingPathComponent(path)
                guard let uiImage = UIImage(contentsOfFile: url.path) else { return }

                let thumbnail = resizeImage(uiImage, to: thumbnailSize)
                PhotoThumbnailCache.shared.setThumbnail(thumbnail, for: path)
            }
        }
    }

    // MARK: - Delete
    static func delete(at path: String) {
        let url = photosDirectory.appendingPathComponent(path)
        try? FileManager.default.removeItem(at: url)
        removeAssetIdentifier(for: path)
    }

    static func fileExists(for path: String) -> Bool {
        let url = photosDirectory.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path)
    }

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
    // MARK: - Optimize Existing Photos
    /// 既存の全写真をJPEG 0.8で再エンコードしてストレージを最適化する
    /// - Parameter progress: (処理済み枚数, 総枚数, 削減バイト数) を報告するコールバック
    /// - Returns: 合計削減バイト数
    @discardableResult
    static func optimizeExistingPhotos(progress: @escaping (Int, Int, Int64) -> Void) async -> Int64 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let fileManager = FileManager.default
                let dir = photosDirectory
                guard let files = try? fileManager.contentsOfDirectory(atPath: dir.path) else {
                    continuation.resume(returning: 0)
                    return
                }
                
                let jpgFiles = files.filter { $0.hasSuffix(".jpg") || $0.hasSuffix(".jpeg") }
                let total = jpgFiles.count
                var totalSaved: Int64 = 0
                
                for (index, filename) in jpgFiles.enumerated() {
                    let fileURL = dir.appendingPathComponent(filename)
                    guard let originalData = try? Data(contentsOf: fileURL),
                          let uiImage = UIImage(data: originalData),
                          let compressed = uiImage.jpegData(compressionQuality: jpegCompressionQuality) else {
                        progress(index + 1, total, totalSaved)
                        continue
                    }
                    
                    // 再エンコード後のほうが小さい場合のみ上書き
                    let saved = Int64(originalData.count) - Int64(compressed.count)
                    if saved > 0 {
                        try? compressed.write(to: fileURL, options: .atomic)
                        totalSaved += saved
                    }
                    
                    progress(index + 1, total, totalSaved)
                }
                
                continuation.resume(returning: totalSaved)
            }
        }
    }

    /// DiaryPhotos ディレクトリの合計サイズ（バイト）を返す
    static func totalStorageSize() -> Int64 {
        let fileManager = FileManager.default
        let dir = photosDirectory
        guard let files = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return 0 }
        var total: Int64 = 0
        for filename in files {
            let path = dir.appendingPathComponent(filename).path
            if let attrs = try? fileManager.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
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
        .task {
            image = await PhotoStorage.loadThumbnail(at: path)
            isLoading = false
        }
    }
}
