import SwiftUI
import UIKit
import MapKit

/// Main-thread rendering values are decoded once when a place snapshot changes.
/// docs/requirements.md §4.4.2: camera updates never regroup visits or format dates.
nonisolated struct ReviewMapRenderedPlace: Identifiable, Equatable {
    let snapshot: ReviewMapPlaceSnapshot
    let coordinate: CLLocationCoordinate2D
    let compactColors: [Color]
    let expandedColors: [Color]
    let compactDiameter: CGFloat
    let expandedDiameter: CGFloat
    let dateLabelSize: CGSize

    var id: String { snapshot.id }

    @MainActor
    init(snapshot: ReviewMapPlaceSnapshot) {
        self.snapshot = snapshot
        coordinate = CLLocationCoordinate2D(latitude: snapshot.location.latitude,
                                            longitude: snapshot.location.longitude)
        let fallback = Color(hex: LocationVisitTagPalette.untaggedHex) ?? .gray
        compactColors = [Color(hex: snapshot.compactColorHex) ?? fallback]
        expandedColors = snapshot.expandedColorHexes.isEmpty
            ? [fallback] : snapshot.expandedColorHexes.map { Color(hex: $0) ?? fallback }
        compactDiameter = ReviewMapPresentation.markerDiameter(for: snapshot.count, expanded: false)
        expandedDiameter = ReviewMapPresentation.markerDiameter(for: snapshot.count, expanded: true)
        let font = UIFont.systemFont(ofSize: 9, weight: .semibold)
        let textSize = (snapshot.dateLabelText as NSString).size(withAttributes: [.font: font])
        dateLabelSize = CGSize(width: ceil(textSize.width) + 10, height: ceil(textSize.height) + 2)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.snapshot == rhs.snapshot
    }

    /// Recreate domain detail data only when a place is opened, preserving its IDs and photos.
    @MainActor
    func detailGroup() -> ReviewLocationGroup {
        let source = snapshot.location
        let location = DiaryLocation(id: source.id,
                                     name: source.name,
                                     address: source.address,
                                     latitude: source.latitude,
                                     longitude: source.longitude,
                                     mapItemURL: source.mapItemURL,
                                     photoPaths: source.photoPaths,
                                     visitTags: source.visitTags)
        let visits = snapshot.visits.map {
            ReviewLocationVisit(date: $0.date, photoPaths: $0.photoPaths, tags: $0.tags)
        }
        return ReviewLocationGroup(id: snapshot.id, location: location, visits: visits)
    }
}
