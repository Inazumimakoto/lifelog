import Foundation

/// Immutable display information, calculated by the cache worker instead of map View.body.
nonisolated struct ReviewMapPlaceSnapshot: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let location: ReviewMapLocationSource
    let visits: [ReviewMapVisitSnapshot]
    let count: Int
    let latestDate: Date
    let dateSummary: String
    let dateLabelText: String
    let allTags: [String]
    let listTagText: String
    let accessibilityText: String
    let compactColorHex: String
    let expandedColorHexes: [String]

    init(id: String, location: ReviewMapLocationSource, visits: [ReviewMapVisitSnapshot],
         count: Int, latestDate: Date, dateSummary: String, dateLabelText: String,
         allTags: [String], listTagText: String, accessibilityText: String,
         compactColorHex: String, expandedColorHexes: [String]) {
        self.id = id
        self.location = location
        self.visits = visits
        self.count = count
        self.latestDate = latestDate
        self.dateSummary = dateSummary
        self.dateLabelText = dateLabelText
        self.allTags = allTags
        self.listTagText = listTagText
        self.accessibilityText = accessibilityText
        self.compactColorHex = compactColorHex
        self.expandedColorHexes = expandedColorHexes
    }
}
