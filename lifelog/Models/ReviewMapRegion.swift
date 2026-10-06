import Foundation

nonisolated struct ReviewMapRegion: Hashable, Codable, Sendable {
    let centerLatitude: Double
    let centerLongitude: Double
    let latitudeDelta: Double
    let longitudeDelta: Double

    init(centerLatitude: Double, centerLongitude: Double, latitudeDelta: Double, longitudeDelta: Double) {
        self.centerLatitude = centerLatitude
        self.centerLongitude = centerLongitude
        self.latitudeDelta = latitudeDelta
        self.longitudeDelta = longitudeDelta
    }
}
