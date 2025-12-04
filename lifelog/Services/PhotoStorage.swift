//
//  PhotoStorage.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import SwiftUI
import UIKit

final class PhotoThumbnailCache {
    static let shared = PhotoThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(for path: String) -> UIImage? {
        cache.object(forKey: path as NSString)
    }

    func set(_ image: UIImage, for path: String) {
        cache.setObject(image, forKey: path as NSString)
    }
}

struct PhotoStorage {
    private static let directoryName = "DiaryPhotos"

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

    static func save(data: Data) throws -> String {
        let filename = UUID().uuidString + ".jpg"
        let url = photosDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return filename
    }

    static func loadImage(at path: String) -> Image? {
        if let cached = PhotoThumbnailCache.shared.image(for: path) {
            return Image(uiImage: cached)
        }
        let url = photosDirectory.appendingPathComponent(path)
        guard let uiImage = UIImage(contentsOfFile: url.path) else { return nil }
        PhotoThumbnailCache.shared.set(uiImage, for: path)
        return Image(uiImage: uiImage)
    }

    static func delete(at path: String) {
        let url = photosDirectory.appendingPathComponent(path)
        try? FileManager.default.removeItem(at: url)
    }

    static func fileExists(for path: String) -> Bool {
        let url = photosDirectory.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path)
    }
}
