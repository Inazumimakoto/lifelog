import XCTest
@testable import lifelify

final class ScheduleMonthTests: XCTestCase {
    private func calendar(
        identifier: Calendar.Identifier = .gregorian,
        timeZone: String = "Asia/Tokyo",
        firstWeekday: Int = 1
    ) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0,
        in calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    func testLeapFebruary_includesLeapDayAndPadsWholeWeeks() {
        let calendar = calendar()
        let month = ScheduleMonth(containing: date(2024, 2, 20, in: calendar), calendar: calendar)

        XCTAssertEqual(month.monthStart, date(2024, 2, 1, in: calendar))
        XCTAssertEqual(month.weekCount, 5)
        XCTAssertEqual(month.dates.prefix(4).compactMap { $0 }, [])
        XCTAssertEqual(month.dates[4], date(2024, 2, 1, in: calendar))
        XCTAssertEqual(month.dates[32], date(2024, 2, 29, in: calendar))
        XCTAssertNil(month.dates[33])
        XCTAssertNil(month.dates[34])
        XCTAssertEqual(month.dates.compactMap { $0 }.count, 29)
    }

    func testMonthStartingSaturday_preservesSixthWeek() {
        let calendar = calendar()
        let month = ScheduleMonth(containing: date(2026, 8, 12, in: calendar), calendar: calendar)

        XCTAssertEqual(month.weekCount, 6)
        XCTAssertEqual(month.dates[6], date(2026, 8, 1, in: calendar))
        XCTAssertEqual(month.dates[35], date(2026, 8, 30, in: calendar))
        XCTAssertEqual(month.dates[36], date(2026, 8, 31, in: calendar))
        XCTAssertTrue(month.dates.suffix(5).allSatisfy { $0 == nil })
    }

    func testFebruaryAlignedToSunday_hasExactlyFourWeeks() {
        let calendar = calendar()
        let month = ScheduleMonth(containing: date(2026, 2, 14, in: calendar), calendar: calendar)

        XCTAssertEqual(month.weekdayNumbers, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(month.weekCount, 4)
        XCTAssertEqual(month.dates.compactMap { $0 }.count, month.dates.count)
        XCTAssertEqual(month.dates.first!, date(2026, 2, 1, in: calendar))
        XCTAssertEqual(month.dates.last!, date(2026, 2, 28, in: calendar))
    }

    func testMondayFirst_reordersHeadingsAndAlignsDates() {
        let calendar = calendar(firstWeekday: 2)
        let month = ScheduleMonth(containing: date(2026, 9, 6, in: calendar), calendar: calendar)

        XCTAssertEqual(month.weekdayNumbers, [2, 3, 4, 5, 6, 7, 1])
        XCTAssertNil(month.dates[0])
        XCTAssertEqual(month.dates[1], date(2026, 9, 1, in: calendar))
        XCTAssertEqual(month.dates[6], date(2026, 9, 6, in: calendar))
        XCTAssertEqual(month.weekCount, 5)
        XCTAssertEqual(month.calendar.firstWeekday, 2)
    }

    func testChineseLeapMonth_usesItsOwnMonthBoundaries() {
        let solarCalendar = calendar(timeZone: "UTC")
        let lunarCalendar = calendar(identifier: .chinese, timeZone: "UTC")
        let month = ScheduleMonth(
            containing: date(2023, 3, 25, in: solarCalendar),
            calendar: lunarCalendar
        )

        // The leap second month in 2023 begins March 22 and ends before April 20.
        XCTAssertEqual(month.monthStart, date(2023, 3, 22, in: solarCalendar))
        XCTAssertEqual(month.dates.compactMap { $0 }.last, date(2023, 4, 19, in: solarCalendar))
        XCTAssertEqual(month.dates.compactMap { $0 }.count, 29)
        XCTAssertEqual(lunarCalendar.dateComponents([.isLeapMonth], from: month.monthStart).isLeapMonth, true)
    }

    func testEventBoundaries_onlyMarksDaysWithPositiveOverlap() {
        let calendar = calendar()
        let intervals = [
            DateInterval(start: date(2026, 2, 28, 12, in: calendar), end: date(2026, 3, 1, in: calendar)),
            DateInterval(start: date(2026, 2, 28, 23, in: calendar), end: date(2026, 3, 2, in: calendar)),
            DateInterval(start: date(2026, 3, 6, 22, in: calendar), end: date(2026, 3, 8, 1, in: calendar)),
            DateInterval(start: date(2026, 3, 10, in: calendar), end: date(2026, 3, 11, in: calendar)),
            DateInterval(start: date(2026, 3, 20, 12, in: calendar), duration: 0),
            DateInterval(start: date(2026, 3, 31, 23, in: calendar), end: date(2026, 4, 3, in: calendar)),
            DateInterval(start: date(2026, 4, 1, in: calendar), end: date(2026, 4, 2, in: calendar))
        ]
        let month = ScheduleMonth(
            containing: date(2026, 3, 15, in: calendar),
            eventIntervals: intervals,
            calendar: calendar
        )

        XCTAssertEqual(month.daysWithEvents, Set([1, 6, 7, 8, 10, 31].map {
            date(2026, 3, $0, in: calendar)
        }))
    }

    func testLongAndRepeatedEvents_clampsDotsToDisplayedMonth() {
        let calendar = calendar()
        let interval = DateInterval(
            start: date(1900, 1, 1, in: calendar),
            end: date(2100, 1, 1, in: calendar)
        )
        let month = ScheduleMonth(
            containing: date(2026, 9, 15, in: calendar),
            eventIntervals: [interval, interval],
            calendar: calendar
        )

        XCTAssertEqual(month.daysWithEvents.count, 30)
        XCTAssertEqual(month.daysWithEvents, Set((1...30).map { date(2026, 9, $0, in: calendar) }))
    }

    func testSpringDaylightSavingTransition_keepsGridAndEventDatesAtLocalMidnight() {
        let calendar = calendar(timeZone: "America/Los_Angeles")
        let month = ScheduleMonth(
            containing: date(2026, 3, 8, 12, in: calendar),
            eventIntervals: [DateInterval(
                start: date(2026, 3, 7, 23, in: calendar),
                end: date(2026, 3, 10, in: calendar)
            )],
            calendar: calendar
        )

        XCTAssertEqual(month.dates.compactMap { $0 }, (1...31).map { date(2026, 3, $0, in: calendar) })
        XCTAssertEqual(month.daysWithEvents, Set([7, 8, 9].map { date(2026, 3, $0, in: calendar) }))
    }

    func testAutumnDaylightSavingTransition_doesNotRepeatOrSkipADate() {
        let calendar = calendar(timeZone: "America/Los_Angeles")
        let month = ScheduleMonth(
            containing: date(2026, 11, 1, 12, in: calendar),
            eventIntervals: [DateInterval(
                start: date(2026, 10, 31, 23, in: calendar),
                end: date(2026, 11, 3, in: calendar)
            )],
            calendar: calendar
        )

        XCTAssertEqual(month.dates.compactMap { $0 }, (1...30).map { date(2026, 11, $0, in: calendar) })
        XCTAssertEqual(month.daysWithEvents, Set([1, 2].map { date(2026, 11, $0, in: calendar) }))
    }
}
