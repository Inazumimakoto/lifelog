import Foundation

nonisolated struct ReviewMapSnapshot: Hashable, Codable, Sendable {
    let query: ReviewMapQuery
    let places: [ReviewMapPlaceSnapshot]
    let availableTagNames: [String]
    let region: ReviewMapRegion?
    let unfilteredPlaceCount: Int

    static let empty = ReviewMapSnapshot(query: .all, places: [], availableTagNames: [], region: nil)

    init(query: ReviewMapQuery, places: [ReviewMapPlaceSnapshot], availableTagNames: [String],
         region: ReviewMapRegion?, unfilteredPlaceCount: Int = 0) {
        self.query = query
        self.places = places
        self.availableTagNames = availableTagNames
        self.region = region
        self.unfilteredPlaceCount = unfilteredPlaceCount
    }
}
