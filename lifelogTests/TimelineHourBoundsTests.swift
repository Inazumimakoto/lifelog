import XCTest
@testable import lifelify

@MainActor
final class TimelineHourBoundsTests: XCTestCase {
    func testEmptyTimeline_preservesFullDayWithEndPadding() {
        let bounds = TimelineHourBounds(items: [])

        XCTAssertEqual(bounds.start, 0)
        XCTAssertEqual(bounds.end, 26)
    }

    func testShortTimeline_expandsAroundMidpointAndClampsStartToMidnight() {
        let daytime = TimelineHourBounds(items: [.init(start: 9, end: 10, isSleep: false)])
        let early = TimelineHourBounds(items: [.init(start: 1, end: 2, isSleep: false)])

        XCTAssertEqual(daytime.start, 3.5)
        XCTAssertEqual(daytime.end, 15.5)
        XCTAssertEqual(early.start, 0)
        XCTAssertEqual(early.end, 7.5)
    }

    func testWrappedSleepRange_requiresTwentyFourHourSpan() {
        let sleep = TimelineHourBounds(items: [.init(start: 22, end: 6, isSleep: true)])
        let event = TimelineHourBounds(items: [.init(start: 22, end: 6, isSleep: false)])

        XCTAssertEqual(sleep.start, 2)
        XCTAssertEqual(sleep.end, 26)
        XCTAssertEqual(event.start, 4)
        XCTAssertEqual(event.end, 24)
    }

    func testNextDayHours_preserveDateOffsetInsteadOfWrappingAxis() {
        let bounds = TimelineHourBounds(items: [.init(start: 22, end: 30, isSleep: true)])

        XCTAssertEqual(bounds.start, 20)
        XCTAssertEqual(bounds.end, 32)
    }
}
