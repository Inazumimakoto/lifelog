import Foundation

/// Preserve the user's first spelling while comparing visit tags consistently.
enum DiaryVisitTagNormalizer {
    static func key(for rawName: String) -> String {
        rawName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    static func normalize(_ tags: [String], limit: Int = 8) -> [String] {
        guard limit > 0 else { return [] }
        var seen: Set<String> = []
        var normalized: [String] = []
        for raw in tags {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            guard seen.insert(key(for: trimmed)).inserted else { continue }
            normalized.append(trimmed)
            if normalized.count >= limit { break }
        }
        return normalized
    }
}
