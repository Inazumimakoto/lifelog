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

    // MARK: - Save
    static func save(data: Data) throws -> String {
        let filename = UUID().uuidString + ".jpg"
        let url = photosDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return filename
    }

    // MARK: - Save (Async)
    static func saveAsync(data: Data) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let path = try save(data: data)
                    continuation.resume(returning: path)
                } catch {
                    continuation.resume(throwing: error)
                }
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
    
    static func prefetchThumbnails(paths: [String]) {
        for path in paths {
            // 既にキャッシュにあればスキップ
            if PhotoThumbnailCache.shared.thumbnail(for: path) != nil {
                continue
            }
            
            // 並列でキューに追加
            prefetchQueue.addOperation {
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
    }

    static func fileExists(for path: String) -> Bool {
        let url = photosDirectory.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path)
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
