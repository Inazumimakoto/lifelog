import Foundation

nonisolated struct ReviewMapQuery: Hashable, Codable, Sendable {
    let monthStart: Date?
    let monthEnd: Date?
    let selectedFilters: [String]

    var filterKeys: [String] { selectedFilters.map(ReviewMapCacheIdentity.normalizedName) }

    static let all = ReviewMapQuery()

    init(monthStart: Date? = nil, monthEnd: Date? = nil, selectedFilters: [String] = []) {
        self.monthStart = monthStart
        self.monthEnd = monthEnd
        var originalNames: [String: String] = [:]
        for filter in selectedFilters {
            let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = ReviewMapCacheIdentity.normalizedName(trimmed)
            guard !key.isEmpty, originalNames[key] == nil else { continue }
            originalNames[key] = trimmed
        }
        self.selectedFilters = originalNames.keys.sorted().compactMap { originalNames[$0] }
    }

    private enum CodingKeys: String, CodingKey {
        case monthStart, monthEnd, selectedFilters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(monthStart: try container.decodeIfPresent(Date.self, forKey: .monthStart),
                  monthEnd: try container.decodeIfPresent(Date.self, forKey: .monthEnd),
                  selectedFilters: try container.decode([String].self, forKey: .selectedFilters))
    }
}
