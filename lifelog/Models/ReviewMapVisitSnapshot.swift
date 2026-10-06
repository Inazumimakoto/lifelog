import Foundation

nonisolated struct ReviewMapVisitSnapshot: Hashable, Codable, Sendable {
    let date: Date
    let photoPaths: [String]
    let tags: [String]

    init(date: Date, photoPaths: [String], tags: [String]) {
        self.date = date
        self.photoPaths = photoPaths
        self.tags = tags
    }
}
