import Foundation

/// Changes to diary text, mood and unrelated app data do not invalidate this source.
nonisolated struct ReviewMapDiarySource: Hashable, Codable, Sendable {
    var id: UUID
    var date: Date
    var locations: [ReviewMapLocationSource]

    init(id: UUID, date: Date, locations: [ReviewMapLocationSource]) {
        self.id = id
        self.date = date
        self.locations = locations
    }
}
