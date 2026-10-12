import XCTest
import MapKit
@testable import lifelify

final class ReviewMapViewportTests: XCTestCase {
    func testSmallPanWithinBuffer_keepsExistingAnnotations() {
        let visible = MKMapRect(x: 1_000, y: 1_000, width: 400, height: 400)
        let retained = ReviewMapViewport.retainedRect(for: visible, size: CGSize(width: 400, height: 400))

        XCTAssertFalse(ReviewMapViewport.needsRefresh(
            visibleRect: visible.offsetBy(dx: 100, dy: 100), retainedRect: retained,
            size: CGSize(width: 400, height: 400)))
        XCTAssertTrue(ReviewMapViewport.needsRefresh(
            visibleRect: visible.offsetBy(dx: 250, dy: 0), retainedRect: retained,
            size: CGSize(width: 400, height: 400)))
    }

    func testZoomIn_releasesDistantAnnotationsEvenInsideOldBuffer() {
        let retained = MKMapRect(x: 0, y: 0, width: 1_000, height: 1_000)
        let visible = MKMapRect(x: 400, y: 400, width: 100, height: 100)

        XCTAssertTrue(ReviewMapViewport.needsRefresh(visibleRect: visible, retainedRect: retained,
                                                    size: CGSize(width: 400, height: 400)))
    }

    func testNarrowMap_retainsAtLeastTwoHundredPointsOfMargin() {
        let visible = MKMapRect(x: 1_000, y: 1_000, width: 100, height: 400)
        let retained = ReviewMapViewport.retainedRect(for: visible, size: CGSize(width: 100, height: 400))

        XCTAssertEqual(retained.minX, 800)
        XCTAssertEqual(retained.maxX, 1_300)
        XCTAssertEqual(retained.minY, 800)
        XCTAssertEqual(retained.maxY, 1_600)
        XCTAssertFalse(ReviewMapViewport.needsRefresh(visibleRect: visible, retainedRect: retained,
                                                     size: CGSize(width: 100, height: 400)))
    }

    func testTapAcrossDateLine_usesSmallWrappedBoundingRect() throws {
        let center = CLLocationCoordinate2D(latitude: 0, longitude: 179.99)
        let coordinates = [CLLocationCoordinate2D(latitude: -0.01, longitude: 179.98),
                           CLLocationCoordinate2D(latitude: 0.01, longitude: -179.98)]
        let rect = try XCTUnwrap(ReviewMapViewport.mapRect(containing: coordinates, around: center))

        XCTAssertLessThan(rect.width, MKMapRect.world.width / 1_000)
        let index = ReviewMapSpatialIndex(coordinates: coordinates + [CLLocationCoordinate2D(latitude: 0, longitude: 0)])
        XCTAssertEqual(index.indices(in: rect), [0, 1])
    }

    func testInvalidCameraRect_isRejected() {
        XCTAssertFalse(ReviewMapViewport.isUsable(.null))
        XCTAssertFalse(ReviewMapViewport.isUsable(MKMapRect(x: 0, y: 0, width: 0, height: 0)))
        XCTAssertFalse(ReviewMapViewport.isUsable(MKMapRect(x: 0, y: 0, width: .infinity, height: 1)))
        XCTAssertTrue(ReviewMapViewport.isUsable(.world))
    }
}
