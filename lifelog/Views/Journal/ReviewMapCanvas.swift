import SwiftUI
import MapKit

/// Camera-dependent state stays local; data, colors, and text come from prepared snapshots.
struct ReviewMapCanvas: View {
    let renderedPlaces: [ReviewMapRenderedPlace]
    let highlightedGroupID: String?
    let hasFilterChips: Bool
    @Binding var cameraPosition: MapCameraPosition
    @Binding var selection: String?

    @State private var expanded = false
    @State private var datesVisible = false
    @State private var visibleDateIDs: Set<String> = []
    @State private var viewportPlaces: [ReviewMapRenderedPlace] = []
    @State private var projectedPlaces: [ProjectedPlace] = []

    private static let viewportMargin: CGFloat = 200

    private var placesForRendering: [ReviewMapRenderedPlace] {
        expanded ? viewportPlaces : renderedPlaces
    }

    var body: some View {
        MapReader { proxy in
            GeometryReader { geometry in
                Map(position: $cameraPosition, interactionModes: .all, selection: $selection) {
                    ForEach(placesForRendering) { place in
                        Annotation(place.snapshot.location.name, coordinate: place.coordinate, anchor: .center) {
                            marker(for: place)
                        }
                        .tag(place.id)
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .simultaneousGesture(SpatialTapGesture().onEnded { value in
                    selectNearestPlace(to: value.location, proxy: proxy, size: geometry.size)
                })
                .onMapCameraChange(frequency: .onEnd) { context in
                    let zoom = ReviewMapPresentation.updateZoomState(distance: context.camera.distance,
                                                                     wasExpanded: expanded,
                                                                     wereDatesVisible: datesVisible)
                    if expanded != zoom.expanded { expanded = zoom.expanded }
                    if datesVisible != zoom.datesVisible { datesVisible = zoom.datesVisible }
                    updateProjection(proxy: proxy, size: geometry.size,
                                     expanded: zoom.expanded, datesVisible: zoom.datesVisible)
                }
                .onChange(of: geometry.size) { _, _ in
                    updateProjection(proxy: proxy, size: geometry.size, expanded: expanded, datesVisible: datesVisible)
                }
                .onChange(of: renderedPlaces) { _, _ in
                    updateProjection(proxy: proxy, size: geometry.size, expanded: expanded, datesVisible: datesVisible)
                }
                .onChange(of: highlightedGroupID) { _, _ in
                    updateDateLabels(size: geometry.size, expanded: expanded, datesVisible: datesVisible)
                }
                .onChange(of: hasFilterChips) { _, _ in
                    updateDateLabels(size: geometry.size, expanded: expanded, datesVisible: datesVisible)
                }
            }
        }
    }

    private func marker(for place: ReviewMapRenderedPlace) -> some View {
        ReviewMapMarker(colors: expanded ? place.expandedColors : place.compactColors,
                        diameter: expanded ? place.expandedDiameter : place.compactDiameter,
                        isSelected: highlightedGroupID == place.id)
            .equatable()
            .contentShape(Circle().inset(by: -14))
            .overlay(alignment: .top) {
                if visibleDateIDs.contains(place.id) {
                    Text(verbatim: place.snapshot.dateLabelText)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.7), in: Capsule())
                        .fixedSize()
                        .offset(y: -place.dateLabelSize.height - 4)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: place.snapshot.location.name))
            .accessibilityValue(Text(verbatim: place.snapshot.accessibilityText))
            .accessibilityIdentifier("review-map-place-\(place.id)")
    }

    private func selectNearestPlace(to location: CGPoint, proxy: MapProxy, size: CGSize) {
        // Reproject at the actual tap so a pan still in flight cannot leave stale hit targets.
        // Only visible points participate; nearby places keep separate markers and identities.
        let bounds = CGRect(origin: .zero, size: size)
        var nearest: (id: String, distance: CGFloat)?
        for place in renderedPlaces {
            guard let point = proxy.convert(place.coordinate, to: .local), bounds.contains(point) else { continue }
            let x = point.x - location.x
            let y = point.y - location.y
            let distance = x * x + y * y
            guard distance <= 22 * 22 else { continue }
            if let current = nearest, current.distance <= distance { continue }
            nearest = (place.id, distance)
        }
        if let nearest, selection != nearest.id { selection = nearest.id }
    }

    private func updateProjection(proxy: MapProxy, size: CGSize, expanded: Bool, datesVisible: Bool) {
        guard size.width > 0, size.height > 0 else { return }
        guard expanded else {
            if !viewportPlaces.isEmpty { viewportPlaces = [] }
            if !projectedPlaces.isEmpty { projectedPlaces = [] }
            if !visibleDateIDs.isEmpty { visibleDateIDs = [] }
            return
        }
        let bounds = CGRect(origin: .zero, size: size)
        let retainedBounds = bounds.insetBy(dx: -Self.viewportMargin, dy: -Self.viewportMargin)
        var retained: [ReviewMapRenderedPlace] = []
        var projected: [ProjectedPlace] = []
        for place in renderedPlaces {
            guard let point = proxy.convert(place.coordinate, to: .local), retainedBounds.contains(point) else { continue }
            retained.append(place)
            if datesVisible, bounds.contains(point) {
                projected.append(ProjectedPlace(place: place, point: point))
            }
        }
        if viewportPlaces != retained { viewportPlaces = retained }
        if projectedPlaces != projected { projectedPlaces = projected }
        updateDateLabels(size: size, expanded: expanded, datesVisible: datesVisible)
    }

    private func updateDateLabels(size: CGSize, expanded: Bool, datesVisible: Bool) {
        guard datesVisible else {
            if !visibleDateIDs.isEmpty { visibleDateIDs = [] }
            return
        }
        let bounds = CGRect(origin: .zero, size: size)
        let candidates = projectedPlaces.map { projected in
            let place = projected.place
            let point = projected.point
            let diameter = expanded ? place.expandedDiameter : place.compactDiameter
            let frame = CGRect(x: point.x - place.dateLabelSize.width / 2,
                               y: point.y - diameter / 2 - place.dateLabelSize.height - 4,
                               width: place.dateLabelSize.width, height: place.dateLabelSize.height)
            return ReviewMapLabelCandidate(id: place.id, frame: frame, latestDate: place.snapshot.latestDate,
                                           isSelected: highlightedGroupID == place.id)
        }
        let pointFrames = projectedPlaces.map { projected in
            let diameter = expanded ? projected.place.expandedDiameter : projected.place.compactDiameter
            return CGRect(x: projected.point.x - diameter / 2, y: projected.point.y - diameter / 2,
                          width: diameter, height: diameter).insetBy(dx: -0.5, dy: -0.5)
        }
        let reserved = pointFrames + [
            CGRect(x: 0, y: 0, width: size.width, height: hasFilterChips ? 84 : 46),
            CGRect(x: 0, y: max(0, size.height - 30), width: size.width, height: 30),
            CGRect(x: max(0, size.width - 110), y: max(0, size.height - 60), width: 110, height: 60)
        ]
        let nextIDs = ReviewMapLabelLayout.visibleIDs(for: candidates, in: bounds, avoiding: reserved)
        if visibleDateIDs != nextIDs { visibleDateIDs = nextIDs }
    }

    private struct ProjectedPlace: Equatable {
        let place: ReviewMapRenderedPlace
        let point: CGPoint
    }
}
