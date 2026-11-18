import Foundation

/// A location's attachments also belong to its diary. Keep legacy place-only
/// originals visible without duplicating files or changing their stable paths.
/// See docs/requirements.md §4.4.
enum DiaryMediaCollection {
    static func allPaths(in entry: DiaryEntry) -> [String] {
        var seen = Set<String>()
        return (entry.photoPaths + entry.locationPhotoPaths + entry.locations.flatMap(\.photoPaths))
            .filter { seen.insert($0).inserted }
    }

    static func normalized(_ entry: DiaryEntry) -> DiaryEntry {
        var result = entry
        result.photoPaths = allPaths(in: entry)
        return result
    }
}
