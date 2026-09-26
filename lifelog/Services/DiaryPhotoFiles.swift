import Foundation
import ImageIO
import UIKit

/// Persistent previews belong to the diary, including after an original moves to iCloud.
/// See docs/diary-photo-icloud-sync.md. This type has no network or account side effects.
nonisolated struct DiaryPhotoFiles: Sendable {
    let directory: URL
    static let thumbnailPixelSize = 512

    enum StorageError: Error {
        case invalidFilename
        case invalidImage
        case missingThumbnail
    }

    func fullImageURL(for path: String) -> URL {
        directory.appendingPathComponent((path as NSString).lastPathComponent)
    }

    func thumbnailURL(for path: String) -> URL {
        directory.appendingPathComponent("Thumbnails", isDirectory: true)
            .appendingPathComponent((path as NSString).lastPathComponent)
    }

    func writeOriginal(_ data: Data, at path: String) throws {
        try validate(path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fullImageURL(for: path), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func writeThumbnail(_ data: Data, at path: String) throws {
        try validate(path)
        guard isImage(data) else { throw StorageError.invalidImage }
        let url = thumbnailURL(for: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func prepareThumbnail(at path: String) throws {
        try validate(path)
        if let data = try? Data(contentsOf: thumbnailURL(for: path)), isImage(data) { return }
        guard let source = CGImageSourceCreateWithURL(fullImageURL(for: path) as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Self.thumbnailPixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary),
              let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.8)
        else { throw StorageError.invalidImage }
        try writeThumbnail(data, at: path)
    }

    func removeOriginal(at path: String) throws {
        try validate(path)
        guard let data = try? Data(contentsOf: thumbnailURL(for: path)), isImage(data) else {
            throw StorageError.missingThumbnail
        }
        try removeIfPresent(fullImageURL(for: path))
    }

    func removeFiles(at path: String) throws {
        try validate(path)
        try removeIfPresent(fullImageURL(for: path))
        try removeIfPresent(thumbnailURL(for: path))
    }

    func originalExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: fullImageURL(for: path).path)
    }

    func thumbnailExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: thumbnailURL(for: path).path)
    }

    func totalSize() -> Int64 {
        guard let files = FileManager.default.enumerator(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return 0 }
        return files.reduce(Int64(0)) { sum, item in
            guard let url = item as? URL,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { return sum }
            return sum + Int64(values.fileSize ?? 0)
        }
    }

    private func validate(_ path: String) throws {
        guard !path.isEmpty, path != ".", path != "..",
              path == (path as NSString).lastPathComponent else { throw StorageError.invalidFilename }
    }

    private func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }

    private func removeIfPresent(_ url: URL) throws {
        do { try FileManager.default.removeItem(at: url) }
        catch let error as CocoaError where error.code == .fileNoSuchFile { }
    }
}
