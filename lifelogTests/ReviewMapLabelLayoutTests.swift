import XCTest
import CoreGraphics
#if canImport(lifelify)
@testable import lifelify
#else
@testable import ReviewMapCacheCore
#endif

final class ReviewMapLabelLayoutTests: XCTestCase {
    func testThousandSparseLabels_allRemainVisible() {
        let candidates: [ReviewMapLabelCandidate] = (0..<1_000).map { index in
            let x = CGFloat(4 + (index % 25) * 80)
            let y = CGFloat(4 + (index / 25) * 28)
            return candidate(index, frame: CGRect(x: x, y: y, width: 70, height: 18))
        }
        let bounds = CGRect(x: 0, y: 0, width: 2_000, height: 1_120)

        XCTAssertEqual(ReviewMapLabelLayout.visibleIDs(for: candidates, in: bounds),
                       Set(candidates.map(\.id)))
    }

    func testThousandDenseLabels_keepSelectedPlaceWithoutCollisionsOrControlsOverlap() throws {
        let candidates: [ReviewMapLabelCandidate] = (0..<1_000).map { index in
            let x = CGFloat(4 + (index % 40) * 8)
            let y = CGFloat(4 + (index / 40) * 8)
            return candidate(index, frame: CGRect(x: x, y: y, width: 70, height: 18),
                             selected: index == 500)
        }
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 230)
        let reserved = CGRect(x: 0, y: 0, width: 110, height: 40)

        let visible = ReviewMapLabelLayout.visibleIDs(for: candidates, in: bounds, avoiding: [reserved])
        let shown = candidates.filter { visible.contains($0.id) }

        XCTAssertTrue(visible.contains(candidates[500].id))
        XCTAssertGreaterThan(visible.count, 1)
        XCTAssertLessThan(visible.count, 50)
        for (index, label) in shown.enumerated() {
            let padded = label.frame.insetBy(dx: -3, dy: -3)
            XCTAssertTrue(bounds.contains(padded))
            XCTAssertFalse(padded.intersects(reserved))
            for other in shown.dropFirst(index + 1) {
                XCTAssertFalse(padded.intersects(other.frame.insetBy(dx: -3, dy: -3)))
            }
        }
        XCTAssertEqual(ReviewMapLabelLayout.visibleIDs(for: Array(candidates.reversed()),
                                                       in: bounds, avoiding: [reserved]), visible)
    }

    func testEqualVisitDates_chooseStableIDWhenLabelsOverlap() {
        let frame = CGRect(x: 10, y: 10, width: 70, height: 18)
        let first = candidate(1, frame: frame)
        let second = candidate(2, frame: frame)

        XCTAssertEqual(ReviewMapLabelLayout.visibleIDs(for: [second, first],
                       in: CGRect(x: 0, y: 0, width: 100, height: 100)), Set([first.id]))
    }

    func testLabelAtMapEdge_isHiddenWhenPaddingWouldLeaveBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let candidates = [candidate(0, frame: CGRect(x: 0, y: 10, width: 70, height: 18)),
                          candidate(1, frame: CGRect(x: 4, y: 50, width: 70, height: 18))]

        XCTAssertEqual(ReviewMapLabelLayout.visibleIDs(for: candidates, in: bounds), Set([candidates[1].id]))
    }

    func testLabelsAcrossCellBoundary_stillAvoidNarrowControls() {
        let reserved = CGRect(x: 63, y: 63, width: 4, height: 4)
        let candidates = [candidate(0, frame: CGRect(x: 68, y: 65, width: 10, height: 10)),
                          candidate(1, frame: CGRect(x: 100, y: 100, width: 10, height: 10))]

        XCTAssertEqual(ReviewMapLabelLayout.visibleIDs(for: candidates,
                       in: CGRect(x: 0, y: 0, width: 200, height: 200), avoiding: [reserved]),
                       Set([candidates[1].id]))
    }

    func testLargeReservedArea_blocksOverlappingLabelButKeepsDistantLabel() {
        let reserved = CGRect(x: 0, y: 0, width: 6_400, height: 6_400)
        let candidates = [candidate(0, frame: CGRect(x: 3_000, y: 3_000, width: 70, height: 18)),
                          candidate(1, frame: CGRect(x: 6_500, y: 6_500, width: 70, height: 18))]

        XCTAssertEqual(ReviewMapLabelLayout.visibleIDs(for: candidates,
                       in: CGRect(x: 0, y: 0, width: 7_000, height: 7_000), avoiding: [reserved]),
                       Set([candidates[1].id]))
    }

    private func candidate(_ index: Int, frame: CGRect, selected: Bool = false) -> ReviewMapLabelCandidate {
        ReviewMapLabelCandidate(id: String(format: "point%04d", index), frame: frame,
                                latestDate: Date(timeIntervalSince1970: 0), isSelected: selected)
    }
}
