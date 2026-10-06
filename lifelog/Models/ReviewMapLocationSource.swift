import Foundation

/// Map-only source data. Saved place names, tags and photos retain their original values.
nonisolated struct ReviewMapLocationSource: Hashable, Codable, Sendable {
    var id: UUID
    var name: String
    var address: String?
    var latitude: Double
    var longitude: Double
    var mapItemURL: String?
    var photoPaths: [String]
    var visitTags: [String]

    init(id: UUID,
         name: String,
         address: String? = nil,
         latitude: Double,
         longitude: Double,
         mapItemURL: String? = nil,
         photoPaths: [String] = [],
         visitTags: [String] = []) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.mapItemURL = mapItemURL
        self.photoPaths = photoPaths
        self.visitTags = visitTags
    }
}
