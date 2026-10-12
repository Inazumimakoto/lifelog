import XCTest
import MapKit
@testable import lifelify

final class ReviewMapSpatialIndexTests: XCTestCase {
    func testTenThousandDistributedPlaces_smallViewportPrunesDistantPoints() {
        let coordinates = (0..<10_000).map { index in
            CLLocationCoordinate2D(latitude: -70 + Double(index / 100) * 1.4,
                                   longitude: -179 + Double(index % 100) * 3.58)
        }
        let index = ReviewMapSpatialIndex(coordinates: coordinates)
        let rect = mapRect(south: 32, north: 38, west: 136, east: 143)
        let expected = coordinates.indices.filter { rect.contains(MKMapPoint(coordinates[$0])) }

        let result = index.query(in: rect)

        XCTAssertEqual(result.indices, expected)
        XCTAssertFalse(result.indices.isEmpty)
        XCTAssertLessThan(result.indices.count, 20)
        XCTAssertLessThan(result.examinedPointCount, 100)
        XCTAssertLessThan(result.visitedNodeCount, 100)
    }

    func testDistributedPlaces_manyViewportsMatchExactProjectionAndOriginalOrder() {
        let coordinates = (0..<2_000).map { index in
            CLLocationCoordinate2D(latitude: -65 + Double((index * 37) % 1300) / 10,
                                   longitude: -175 + Double((index * 71) % 3500) / 10)
        }
        let index = ReviewMapSpatialIndex(coordinates: coordinates)

        for step in 0..<30 {
            let south = -60 + Double((step * 7) % 100)
            let west = -170 + Double((step * 29) % 310)
            let rect = mapRect(south: south, north: south + 15, west: west, east: west + 20)
            let expected = coordinates.indices.filter { rect.contains(MKMapPoint(coordinates[$0])) }
            XCTAssertEqual(index.indices(in: rect), expected, "Viewport \(step)")
        }
    }

    func testSeparatePlacesAtSameCoordinate_keepEveryOriginalIndex() {
        let coordinates = (0..<100).map { index in
            index.isMultiple(of: 3) ? coordinate(35, 139) : coordinate(-35, -139)
        }
        let index = ReviewMapSpatialIndex(coordinates: coordinates)
        let point = MKMapPoint(coordinate(35, 139))
        let rect = MKMapRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2)

        XCTAssertEqual(index.indices(in: rect), coordinates.indices.filter { $0.isMultiple(of: 3) })
    }

    func testDateLineCrossing_returnsBothSidesWithoutDuplicates() {
        let coordinates = [coordinate(0, 179), coordinate(0, -179), coordinate(0, 0),
                           coordinate(0, 180), coordinate(0, -180), coordinate(40, 179)]
        let index = ReviewMapSpatialIndex(coordinates: coordinates)
        let worldWidth = MKMapRect.world.size.width
        let west = MKMapPoint(coordinate(0, 178)).x
        let east = MKMapPoint(coordinate(0, -178)).x + worldWidth
        let north = MKMapPoint(coordinate(1, 0)).y
        let south = MKMapPoint(coordinate(-1, 0)).y
        let rect = MKMapRect(x: west, y: north, width: east - west, height: south - north)

        XCTAssertEqual(index.indices(in: rect), [0, 1, 3, 4])
        XCTAssertEqual(index.indices(in: MKMapRect(x: rect.origin.x - worldWidth, y: rect.origin.y,
                                                  width: rect.size.width, height: rect.size.height)),
                       [0, 1, 3, 4])
    }

    func testDateLineOnRectangleEdge_includesBothCoordinateRepresentations() {
        let index = ReviewMapSpatialIndex(coordinates: [coordinate(0, 180), coordinate(0, -180),
                                                        coordinate(0, 179), coordinate(0, -179)])
        let world = MKMapRect.world
        let west = MKMapPoint(coordinate(0, 179)).x

        XCTAssertEqual(index.indices(in: MKMapRect(x: west, y: 0, width: world.size.width - west,
                                                  height: world.size.height)), [0, 1, 2])
        XCTAssertEqual(index.indices(in: MKMapRect(x: world.size.width, y: 0, width: 0,
                                                  height: world.size.height)), [0, 1])
    }

    func testRectangleEdges_includeExactBoundaryPoints() {
        let coordinates = [coordinate(10, 20), coordinate(20, 30), coordinate(15, 25),
                           coordinate(9, 20), coordinate(20, 31)]
        let index = ReviewMapSpatialIndex(coordinates: coordinates)
        let southWest = MKMapPoint(coordinates[0])
        let northEast = MKMapPoint(coordinates[1])
        let rect = MKMapRect(x: southWest.x, y: northEast.y,
                             width: northEast.x - southWest.x, height: southWest.y - northEast.y)

        XCTAssertEqual(index.indices(in: rect), [0, 1, 2])
    }

    func testWholeWorldAndWiderRepeatedWorld_returnAllValidIndicesOnce() {
        let coordinates = [coordinate(35, 139), coordinate(0, 180), coordinate(-40, -120),
                           coordinate(0, -180), coordinate(35, 139)]
        let index = ReviewMapSpatialIndex(coordinates: coordinates)
        let world = MKMapRect.world
        let wide = MKMapRect(x: -world.size.width * 1.5, y: 0,
                             width: world.size.width * 3, height: world.size.height)

        XCTAssertEqual(index.indices(in: world), Array(coordinates.indices))
        XCTAssertEqual(index.indices(in: wide), Array(coordinates.indices))
        XCTAssertEqual(index.query(in: world).visitedNodeCount, 1)
        XCTAssertEqual(index.query(in: world).examinedPointCount, 0)
    }

    func testInvalidCoordinatesAndQueries_areIgnored() {
        let coordinates = [coordinate(35, 139), coordinate(100, 0), coordinate(0, 181),
                           coordinate(.nan, 0), coordinate(0, .infinity)]
        let index = ReviewMapSpatialIndex(coordinates: coordinates)

        XCTAssertEqual(index.indices(in: .world), [0])
        XCTAssertTrue(index.indices(in: .null).isEmpty)
        XCTAssertTrue(index.indices(in: MKMapRect(x: 0, y: 0, width: -1, height: 1)).isEmpty)
        XCTAssertTrue(index.indices(in: MKMapRect(x: 0, y: -10, width: 1, height: 1)).isEmpty)
        XCTAssertTrue(ReviewMapSpatialIndex(coordinates: []).indices(in: .world).isEmpty)
    }

    func testCancelledBuild_abandonsSupersededRefresh() async {
        let index = await _Concurrency.Task.detached {
            _Concurrency.withUnsafeCurrentTask { $0?.cancel() }
            return ReviewMapSpatialIndex(coordinates: [CLLocationCoordinate2D(latitude: 35, longitude: 139)])
        }.value

        XCTAssertTrue(index.indices(in: .world).isEmpty)
    }

    private func coordinate(_ latitude: Double, _ longitude: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func mapRect(south: Double, north: Double, west: Double, east: Double) -> MKMapRect {
        let southWest = MKMapPoint(coordinate(south, west))
        let northEast = MKMapPoint(coordinate(north, east))
        return MKMapRect(x: southWest.x, y: northEast.y,
                         width: northEast.x - southWest.x, height: southWest.y - northEast.y)
    }
}
