import XCTest
@testable import lifelify

@MainActor
final class CalendarPreviewLayoutTests: XCTestCase {
    private func calendar(timeZone: String = "Asia/Tokyo") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    private func date(_ day: Int, hour: Int = 0, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }

    private func week(in calendar: Calendar) -> [Date] {
        (8...14).map { date($0, in: calendar) }
    }

    private func event(_ title: String, from start: Date, to end: Date) -> CalendarEvent {
        CalendarEvent(title: title, startDate: start, endDate: end,
                      calendarName: "仕事", isAllDay: true)
    }

    func testCrossWeekEvent_clipsColumnsAndPreservesContinuationFlags() {
        let calendar = calendar()
        let event = event("Across weeks", from: date(6, in: calendar), to: date(17, in: calendar))
        let layout = CalendarPreviewLayout.week(dates: week(in: calendar), events: [event],
                                                itemLimit: 4, calendar: calendar)

        XCTAssertEqual(layout.visibleLaneCount, 1)
        XCTAssertEqual(layout.segments.count, 1)
        let segment = layout.segments[0]
        XCTAssertEqual(segment.event.id, event.id)
        XCTAssertEqual(segment.startColumn, 0)
        XCTAssertEqual(segment.endColumn, 6)
        XCTAssertTrue(segment.continuesBeforeWeek)
        XCTAssertTrue(segment.continuesAfterWeek)
        XCTAssertTrue(layout.dayStates.allSatisfy { $0.occupiedVisibleLanes == [0] })
    }

    func testMidnightEndAcrossDaylightSaving_excludesFollowingDay() {
        let calendar = calendar(timeZone: "America/Los_Angeles")
        let event = event("DST", from: date(7, hour: 23, in: calendar), to: date(10, in: calendar))
        let layout = CalendarPreviewLayout.week(dates: week(in: calendar), events: [event],
                                                itemLimit: 4, calendar: calendar)

        XCTAssertEqual(layout.segments[0].startColumn, 0)
        XCTAssertEqual(layout.segments[0].endColumn, 1)
        XCTAssertEqual(layout.dayStates[2].occupiedVisibleLanes, [])
        XCTAssertFalse(CalendarPreviewLayout.isMultiDayEvent(start: date(8, in: calendar),
                                                             end: date(9, in: calendar), calendar: calendar))
    }

    func testAdjacentEvents_reuseLaneAndHideOnlyOverlappingExcess() {
        let calendar = calendar()
        let first = event("Long", from: date(8, in: calendar), to: date(11, in: calendar))
        let overlap = event("Hidden", from: date(9, in: calendar), to: date(11, in: calendar))
        let next = event("Next", from: date(11, in: calendar), to: date(13, in: calendar))
        let layout = CalendarPreviewLayout.week(dates: week(in: calendar), events: [overlap, next, first],
                                                itemLimit: 2, calendar: calendar)

        XCTAssertEqual(layout.segments.map(\.event.id), [first.id, next.id])
        XCTAssertEqual(layout.segments.map(\.lane), [0, 0])
        XCTAssertEqual(layout.dayStates.map(\.hiddenMultiDayCount), [0, 1, 1, 0, 0, 0, 0])
        XCTAssertEqual(layout.dayStates[3].occupiedVisibleLanes, [0])
    }

    func testDayRows_reserveMultiDayLaneAndCountAllHiddenItems() {
        let state = CalendarDayMultiDayState(visibleLaneCount: 2,
                                             occupiedVisibleLanes: [0], hiddenMultiDayCount: 2)
        let rows = CalendarPreviewLayout.rows(regularItems: ["one", "two", "three"],
                                              itemLimit: 4, multiDayState: state)

        XCTAssertEqual(rows, [.multiDayPlaceholder, .item("one"), .item("two"), .overflow(3)])
    }

    func testDayRows_withoutOverflowKeepsUnusedLanesAvailable() {
        let state = CalendarDayMultiDayState(visibleLaneCount: 2,
                                             occupiedVisibleLanes: [1], hiddenMultiDayCount: 0)
        let rows = CalendarPreviewLayout.rows(regularItems: ["one"], itemLimit: 4, multiDayState: state)

        XCTAssertEqual(rows, [.item("one"), .multiDayPlaceholder, .empty, .empty])
        XCTAssertEqual(CalendarPreviewLayout.rows(regularItems: [1], itemLimit: 0, multiDayState: state), [])
    }

    func testNoVisibleEventLanes_preservesOverflowCountsAndStableSegmentIdentity() {
        let calendar = calendar()
        let event = event("Hidden", from: date(8, in: calendar), to: date(11, in: calendar))
        let hidden = CalendarPreviewLayout.week(dates: week(in: calendar), events: [event],
                                                itemLimit: 1, calendar: calendar)
        XCTAssertTrue(hidden.segments.isEmpty)
        XCTAssertEqual(hidden.dayStates.map(\.hiddenMultiDayCount), [1, 1, 1, 0, 0, 0, 0])
        XCTAssertEqual(CalendarPreviewLayout.rows(regularItems: [Int](), itemLimit: 1,
                                                  multiDayState: hidden.dayStates[0]), [.overflow(1)])

        let first = CalendarPreviewLayout.week(dates: week(in: calendar), events: [event],
                                               itemLimit: 4, calendar: calendar)
        let second = CalendarPreviewLayout.week(dates: week(in: calendar), events: [event],
                                                itemLimit: 4, calendar: calendar)
        XCTAssertEqual(first.segments.map(\.id), second.segments.map(\.id))
        let presentation = CalendarWeekMultiDayLayout(layout: first)
        XCTAssertEqual(presentation.segments[0].categoryName, event.calendarName)
        XCTAssertEqual(presentation.segments[0].displayTitle(privacyMode: .hidden), String(localized: "予定あり"))
    }

    func testIncompleteWeek_returnsEmptySevenDayLayout() {
        let calendar = calendar()
        let layout = CalendarPreviewLayout.week(dates: Array(week(in: calendar).prefix(6)), events: [],
                                                itemLimit: 4, calendar: calendar)
        XCTAssertTrue(layout.segments.isEmpty)
        XCTAssertEqual(layout.dayStates, Array(repeating: .empty, count: 7))
    }
}
