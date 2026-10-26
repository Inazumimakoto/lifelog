import Foundation

/// Diary and location imports share loading, saving, and failure accounting.
/// The caller chooses limits and matching: location imports always save a new
/// original, while diary imports can reuse an already stored location photo.
@MainActor
enum DiaryPhotoImporter {
    struct Item {
        let assetIdentifier: String?
        let loadData: @MainActor () async throws -> Data?
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
        matchingPath: (@MainActor (String?, Data) async -> String?)? = nil,
        save: @MainActor (Data, String?) async throws -> String = {
            try await PhotoStorage.saveAsync(data: $0, sourceAssetIdentifier: $1)
        }
    ) async -> Summary {
        let usableItems = items.prefix(max(0, maximumCount ?? items.count))
        var summary = Summary()
        summary.skippedCount = items.count - usableItems.count

        for item in usableItems {
            do {
                guard let data = try await item.loadData() else {
                    summary.failedLoadCount += 1
                    continue
                }
                if let existingPath = await matchingPath?(item.assetIdentifier, data) {
                    if alreadyContains(existingPath) || summary.addedPaths.contains(existingPath) {
                        summary.skippedCount += 1
                    } else {
                        summary.addedPaths.append(existingPath)
                    }
                    continue
                }
                do {
                    let path = try await save(data, item.assetIdentifier)
                    summary.addedPaths.append(path)
                } catch {
                    summary.failedSaveCount += 1
                }
            } catch {
                summary.failedLoadCount += 1
            }
        }
        return summary
    }
}
