import Foundation

/// Diary and location imports share loading, saving, and failure accounting.
/// The caller chooses limits and matching: location imports always save a new
/// original, while diary imports can reuse an already stored location photo.
@MainActor
enum DiaryPhotoImporter {
    struct Item {
        let assetIdentifier: String?
        let loadData: @MainActor () async throws -> Data?
        let loadVideo: (@MainActor () async throws -> ImportedDiaryVideo?)?

        init(assetIdentifier: String?, loadData: @escaping @MainActor () async throws -> Data?) {
            self.assetIdentifier = assetIdentifier
            self.loadData = loadData
            loadVideo = nil
        }

        private init(videoAssetIdentifier: String?, loadVideo: @escaping @MainActor () async throws -> ImportedDiaryVideo?) {
            assetIdentifier = videoAssetIdentifier
            self.loadVideo = loadVideo
            loadData = { nil }
        }

        static func video(assetIdentifier: String?, load: @escaping @MainActor () async throws -> ImportedDiaryVideo?) -> Self {
            Self(videoAssetIdentifier: assetIdentifier, loadVideo: load)
        }
    }

    struct Summary: Equatable {
        var addedPaths: [String] = []
        var skippedCount = 0
        var failedLoadCount = 0
        var failedSaveCount = 0

        var addedCount: Int { addedPaths.count }
        var hasIssues: Bool { skippedCount > 0 || failedLoadCount > 0 || failedSaveCount > 0 }
    }

    static func importPhotos(
        from items: [Item],
        maximumCount: Int? = nil,
        alreadyContains: (String) -> Bool = { _ in false },
        matchingAssetPath: (@MainActor (String) async -> String?)? = nil,
        matchingPath: (@MainActor (String?, Data) async -> String?)? = nil,
        matchingVideoPath: (@MainActor (String?, URL) async -> String?)? = nil,
        save: @MainActor (Data, String?) async throws -> String = {
            try await PhotoStorage.saveAsync(data: $0, sourceAssetIdentifier: $1)
        },
        saveVideo: @MainActor (URL, String?) async throws -> String = {
            try await PhotoStorage.saveVideoAsync(fileURL: $0, sourceAssetIdentifier: $1)
        },
        onAdded: @MainActor (String) -> Void = { _ in }
    ) async -> Summary {
        let usableItems = items.prefix(max(0, maximumCount ?? items.count))
        var summary = Summary()
        summary.skippedCount = items.count - usableItems.count

        for item in usableItems {
            guard !_Concurrency.Task.isCancelled else { break }
            do {
                if let identifier = item.assetIdentifier,
                   let existingPath = await matchingAssetPath?(identifier) {
                    append(existingPath, to: &summary, alreadyContains: alreadyContains, onAdded: onAdded)
                    continue
                }
                if let loadVideo = item.loadVideo {
                    guard let video = try await loadVideo() else {
                        summary.failedLoadCount += 1
                        continue
                    }
                    defer { video.removeTemporaryFile() }
                    guard !_Concurrency.Task.isCancelled else { break }
                    if let existingPath = await matchingVideoPath?(item.assetIdentifier, video.url) {
                        append(existingPath, to: &summary, alreadyContains: alreadyContains, onAdded: onAdded)
                        continue
                    }
                    do {
                        let path = try await saveVideo(video.url, item.assetIdentifier)
                        append(path, to: &summary, alreadyContains: alreadyContains, onAdded: onAdded)
                    } catch {
                        summary.failedSaveCount += 1
                    }
                    continue
                }
                guard let data = try await item.loadData() else {
                    summary.failedLoadCount += 1
                    continue
                }
                guard !_Concurrency.Task.isCancelled else { break }
                if let existingPath = await matchingPath?(item.assetIdentifier, data) {
                    append(existingPath, to: &summary, alreadyContains: alreadyContains, onAdded: onAdded)
                    continue
                }
                do {
                    let path = try await save(data, item.assetIdentifier)
                    append(path, to: &summary, alreadyContains: alreadyContains, onAdded: onAdded)
                } catch {
                    summary.failedSaveCount += 1
                }
            } catch {
                summary.failedLoadCount += 1
            }
        }
        return summary
    }

    private static func append(_ path: String, to summary: inout Summary,
                               alreadyContains: (String) -> Bool,
                               onAdded: @MainActor (String) -> Void) {
        guard !alreadyContains(path), !summary.addedPaths.contains(path) else {
            summary.skippedCount += 1
            return
        }
        summary.addedPaths.append(path)
        onAdded(path)
    }
}
