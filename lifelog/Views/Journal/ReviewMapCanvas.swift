import SwiftUI
import MapKit

/// Camera-dependent state stays local; data, colors, and text come from prepared snapshots.
struct ReviewMapCanvas: View {
    let renderedPlaces: [ReviewMapRenderedPlace]
    let spatialIndex: ReviewMapSpatialIndex
    let revision: UInt64
    let highlightedGroupID: String?
    let hasFilterChips: Bool
    @Binding var cameraPosition: MapCameraPosition
    @Binding var selection: String?

    @State private var expanded = false
    @State private var datesVisible = false
    @State private var visibleDateIDs: Set<String> = []
    @State private var viewportPlaces: [ReviewMapRenderedPlace] = []
    @State private var projectedPlaces: [ProjectedPlace] = []
    @State private var cameraWork = CameraWork()

    var body: some View {
        MapReader { proxy in
            GeometryReader { geometry in
                Map(position: $cameraPosition, interactionModes: .all, selection: $selection) {
                    ForEach(viewportPlaces) { place in
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
                .onMapCameraChange(frequency: .continuous) { context in
                    cameraWork.visibleRect = context.rect
                    let zoom = ReviewMapPresentation.updateZoomState(distance: context.camera.distance,
                                                                     wasExpanded: expanded,
                                                                     wereDatesVisible: datesVisible)
                    if expanded != zoom.expanded { expanded = zoom.expanded }
                    if datesVisible != zoom.datesVisible { datesVisible = zoom.datesVisible }
                    updateViewport(size: geometry.size)
                    scheduleProjection(proxy: proxy, size: geometry.size)
                }
                .onChange(of: geometry.size) { _, _ in
                    updateViewport(size: geometry.size, force: true)
                    scheduleProjection(proxy: proxy, size: geometry.size)
                }
                .onChange(of: revision) { _, _ in
                    updateViewport(size: geometry.size, force: true)
                    scheduleProjection(proxy: proxy, size: geometry.size)
                }
                .onChange(of: highlightedGroupID) { _, _ in
                    updateDateLabels(size: geometry.size, expanded: expanded, datesVisible: datesVisible)
                    scheduleProjection(proxy: proxy, size: geometry.size)
                }
                .onChange(of: hasFilterChips) { _, _ in
                    updateDateLabels(size: geometry.size, expanded: expanded, datesVisible: datesVisible)
                    scheduleProjection(proxy: proxy, size: geometry.size)
                }
            }
        }
        .onDisappear {
            cameraWork.projectionTask?.cancel()
            cameraWork.projectionTask = nil
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
        let radius: CGFloat = 22
        let corners = [CGPoint(x: location.x - radius, y: location.y - radius),
                       CGPoint(x: location.x + radius, y: location.y - radius),
                       CGPoint(x: location.x - radius, y: location.y + radius),
                       CGPoint(x: location.x + radius, y: location.y + radius)]
        let coordinates = corners.compactMap { proxy.convert($0, from: .local) }
        let indices: [Int]
        if coordinates.count == corners.count,
           let center = proxy.convert(location, from: .local),
           let rect = ReviewMapViewport.mapRect(containing: coordinates, around: center) {
            indices = spatialIndex.indices(in: rect)
        } else if let rect = cameraWork.visibleRect {
            // Near a pitched horizon conversion can fail; retain exact screen hit testing.
            indices = spatialIndex.indices(in: rect)
        } else {
            indices = cameraWork.viewportIndices
        }
        var nearest: (id: String, distance: CGFloat)?
        for index in indices {
            let place = renderedPlaces[index]
            guard let point = proxy.convert(place.coordinate, to: .local), bounds.contains(point) else { continue }
            let x = point.x - location.x
            let y = point.y - location.y
            let distance = x * x + y * y
            guard distance <= radius * radius else { continue }
            if let current = nearest, current.distance <= distance { continue }
            nearest = (place.id, distance)
        }
        if let nearest, selection != nearest.id { selection = nearest.id }
    }

    private func updateViewport(size: CGSize, force: Bool = false) {
        guard let visibleRect = cameraWork.visibleRect, ReviewMapViewport.isUsable(visibleRect) else { return }
        guard force || ReviewMapViewport.needsRefresh(visibleRect: visibleRect,
                                                      retainedRect: cameraWork.retainedRect, size: size) else { return }
        let retainedRect = ReviewMapViewport.retainedRect(for: visibleRect, size: size)
        let indices = spatialIndex.indices(in: retainedRect)
        cameraWork.retainedRect = retainedRect
        if force || cameraWork.viewportIndices != indices {
            cameraWork.viewportIndices = indices
            viewportPlaces = indices.map { renderedPlaces[$0] }
        }
    }

    private func scheduleProjection(proxy: MapProxy, size: CGSize) {
        cameraWork.projectionTask?.cancel()
        cameraWork.projectionTask = nil
        guard datesVisible else {
            if !projectedPlaces.isEmpty { projectedPlaces = [] }
            if !visibleDateIDs.isEmpty { visibleDateIDs = [] }
            return
        }
        // Camera callbacks are frequent; only lay out labels after motion settles.
        // Buffer maintenance above does no screen projection and normally does no state update.
        cameraWork.projectionTask = _Concurrency.Task { @MainActor in
            do { try await _Concurrency.Task.sleep(for: .milliseconds(120)) }
            catch { return }
            guard !_Concurrency.Task.isCancelled else { return }
            updateProjection(proxy: proxy, size: size)
            cameraWork.projectionTask = nil
        }
    }

    private func updateProjection(proxy: MapProxy, size: CGSize) {
        guard datesVisible, size.width > 0, size.height > 0,
              let rect = cameraWork.visibleRect else { return }
        let bounds = CGRect(origin: .zero, size: size)
        var projected: [ProjectedPlace] = []
        for index in spatialIndex.indices(in: rect) {
            let place = renderedPlaces[index]
            if let point = proxy.convert(place.coordinate, to: .local), bounds.contains(point) {
                projected.append(ProjectedPlace(place: place, point: point))
            }
        }
        projectedPlaces = projected
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

    private struct ProjectedPlace {
        let place: ReviewMapRenderedPlace
        let point: CGPoint
    }

    /// These camera bookkeeping values do not invalidate SwiftUI on every gesture frame.
    @MainActor
    private final class CameraWork {
        var visibleRect: MKMapRect?
        var retainedRect: MKMapRect?
        var viewportIndices: [Int] = []
        var projectionTask: _Concurrency.Task<Void, Never>?
    }
}
