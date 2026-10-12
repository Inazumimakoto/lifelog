import CoreGraphics
import MapKit

/// Geographic prefiltering keeps screen projection local (docs/requirements.md §4.4.2).
nonisolated enum ReviewMapViewport {
    static func retainedRect(for visibleRect: MKMapRect, size: CGSize) -> MKMapRect {
        // Keep nearby annotations alive during a drag, without retaining the entire dataset.
        let horizontalMargin = visibleRect.width * max(0.5, 200 / max(1, Double(size.width)))
        let verticalMargin = visibleRect.height * max(0.5, 200 / max(1, Double(size.height)))
        return visibleRect.insetBy(dx: -horizontalMargin, dy: -verticalMargin)
    }

    static func needsRefresh(visibleRect: MKMapRect, retainedRect: MKMapRect?, size: CGSize) -> Bool {
        guard let retainedRect else { return true }
        let preferred = Self.retainedRect(for: visibleRect, size: size)
        return !retainedRect.contains(visibleRect) ||
            retainedRect.width > preferred.width * 1.5 ||
            retainedRect.height > preferred.height * 1.5
    }

    static func isUsable(_ rect: MKMapRect) -> Bool {
        !rect.isNull && !rect.isEmpty &&
            rect.origin.x.isFinite && rect.origin.y.isFinite &&
            rect.width.isFinite && rect.height.isFinite
    }

    /// Unwrap around the tap so a small target crossing ±180° stays a small query.
    static func mapRect(containing coordinates: [CLLocationCoordinate2D],
                        around center: CLLocationCoordinate2D) -> MKMapRect? {
        guard CLLocationCoordinate2DIsValid(center), !coordinates.isEmpty else { return nil }
        let centerPoint = MKMapPoint(center)
        let worldWidth = MKMapRect.world.width
        var minX = centerPoint.x
        var maxX = centerPoint.x
        var minY = centerPoint.y
        var maxY = centerPoint.y
        for coordinate in coordinates {
            guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
            let point = MKMapPoint(coordinate)
            guard point.x.isFinite, point.y.isFinite else { return nil }
            var x = point.x
            if x - centerPoint.x > worldWidth / 2 { x -= worldWidth }
            if centerPoint.x - x > worldWidth / 2 { x += worldWidth }
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        // Unwrapping and reconstructing a rect can round an exact edge inward. One
        // map unit is sub-metre; exact screen-distance testing still decides selection.
        return MKMapRect(x: minX - 1, y: minY - 1, width: maxX - minX + 2, height: maxY - minY + 2)
    }
}
