import Foundation

nonisolated struct ReviewMapTagSource: Hashable, Codable, Sendable {
    var id: UUID
    var name: String
    var displayName: String
    var sortOrder: Int
    var colorHex: String

    init(id: UUID, name: String, displayName: String, sortOrder: Int, colorHex: String) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.sortOrder = sortOrder
        self.colorHex = colorHex
    }
}
