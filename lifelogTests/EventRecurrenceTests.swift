import XCTest
@testable import lifelify

@MainActor
final class EventRecurrenceTests: XCTestCase {
    private func calendar(_ zone: String = "Asia/Tokyo", firstWeekday: Int = 1) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone)!
        value.firstWeekday = firstWeekday
        return value
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, zone: String = "Asia/Tokyo") -> Date {
        calendar(zone).date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func event(start: Date, end: Date? = nil, rule: EventRecurrenceRule? = nil, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(title: "Weekly meeting", detail: "Original note", startDate: start,
                      endDate: end ?? start.addingTimeInterval(3_600), calendarName: "Work",
                      isAllDay: allDay, reminderMinutes: 15,
                      dateOnlyTimeZoneIdentifier: allDay ? rule?.timeZoneIdentifier : nil,
                      recurrenceRule: rule)
    }

    private func expand(_ event: CalendarEvent, from start: Date, to end: Date,
                        exceptions: [CalendarEventException] = [], displayCalendar: Calendar? = nil) -> [CalendarEvent] {
        EventRecurrenceExpander.occurrences(events: [event], exceptions: exceptions,
                                           rangeStart: start, rangeEndExclusive: end,
                                           calendar: displayCalendar ?? calendar())
    }

    func testWeeklySeries_skipOneOccurrenceKeepsFollowingWeeksAndStableIdentity() throws {
        let series = event(start: date(10, 5, 9), rule: EventRecurrenceRule(frequency: .weekly, weekdays: [2], timeZoneIdentifier: "Asia/Tokyo"))
        let original = expand(series, from: date(10, 1), to: date(11, 1))
        let skippedStart = date(10, 12, 9)
        let skipped = CalendarEventException(seriesID: series.id, originalStartDate: skippedStart)
        let result = expand(series, from: date(10, 1), to: date(11, 1), exceptions: [skipped])

        XCTAssertEqual(original.map(\.startDate), [date(10, 5, 9), skippedStart, date(10, 19, 9), date(10, 26, 9)])
        XCTAssertEqual(result.map(\.startDate), [date(10, 5, 9), date(10, 19, 9), date(10, 26, 9)])
        XCTAssertEqual(result.map(\.id), original.filter { $0.startDate != skippedStart }.map(\.id))
        XCTAssertEqual(Set(result.map(\.id)).count, result.count)
        XCTAssertEqual(result.last?.occurrenceReference?.seriesID, series.id)
        XCTAssertEqual(result.last?.occurrenceReference?.originalStartDate, date(10, 26, 9))
        XCTAssertEqual(try JSONDecoder().decode(CalendarEvent.self, from: JSONEncoder().encode(result[0])), result[0])
    }

    func testReplacement_movesInFromOutsideQueryAndKeepsOriginalIdentity() throws {
        let series = event(start: date(10, 5, 9), rule: EventRecurrenceRule(frequency: .weekly, timeZoneIdentifier: "Asia/Tokyo"))
        let original = try XCTUnwrap(expand(series, from: date(10, 5), to: date(10, 6)).first)
        var moved = original
        moved.title = "Moved meeting"
        moved.startDate = date(11, 3, 11)
        moved.endDate = date(11, 3, 12)
        moved.reminderDate = date(11, 3, 10)
        let exception = CalendarEventException(seriesID: series.id, originalStartDate: date(10, 5, 9), replacement: moved)

        XCTAssertTrue(expand(series, from: date(10, 5), to: date(10, 6), exceptions: [exception]).isEmpty)
        let result = try XCTUnwrap(expand(series, from: date(11, 3), to: date(11, 4), exceptions: [exception]).first)
        XCTAssertEqual(result.id, original.id)
        XCTAssertEqual(result.occurrenceReference, original.occurrenceReference)
        XCTAssertEqual(result.title, "Moved meeting")
        XCTAssertEqual(result.reminderDate, date(11, 3, 10))
    }

    func testReplacement_duplicateLogicalKeyDoesNotDuplicateOccurrence() {
        let series = event(start: date(10, 5, 9), rule: EventRecurrenceRule(frequency: .weekly, timeZoneIdentifier: "Asia/Tokyo"))
        var moved = series
        moved.startDate = date(10, 6, 9)
        moved.endDate = date(10, 6, 10)
        let exception = CalendarEventException(seriesID: series.id, originalStartDate: series.startDate, replacement: moved)
        let duplicate = CalendarEventException(seriesID: series.id, originalStartDate: series.startDate, replacement: moved)
        let result = expand(series, from: date(10, 1), to: date(10, 8), exceptions: [exception, duplicate])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.startDate, date(10, 6, 9))
    }

    func testUntil_includesEntireFinalLocalDateAndSuppressesLaterReplacement() {
        let rule = EventRecurrenceRule(frequency: .weekly, until: date(10, 19), timeZoneIdentifier: "Asia/Tokyo")
        let series = event(start: date(10, 5, 9), rule: rule)
        let obsolete = CalendarEventException(seriesID: series.id, originalStartDate: date(10, 26, 9), replacement: series)
        let result = expand(series, from: date(10, 1), to: date(11, 1), exceptions: [obsolete])
        XCTAssertEqual(result.map(\.startDate), [date(10, 5, 9), date(10, 12, 9), date(10, 19, 9)])
    }

    func testMultipleWeekdays_startOnSelectedDayAndKeepBiweeklyCadenceAcrossDisplayWeekStarts() {
        let rule = EventRecurrenceRule(frequency: .weekly, interval: 2, weekdays: [6, 3, 6], timeZoneIdentifier: "Asia/Tokyo")
        // DTSTART is Wednesday; the selected Tuesday earlier in this week is excluded.
        let series = event(start: date(10, 7, 9), rule: rule)
        let sundayFirst = expand(series, from: date(10, 1), to: date(11, 1), displayCalendar: calendar(firstWeekday: 1))
        let mondayFirst = expand(series, from: date(10, 1), to: date(11, 1), displayCalendar: calendar(firstWeekday: 2))
        XCTAssertEqual(sundayFirst.map(\.startDate), [date(10, 9, 9), date(10, 20, 9), date(10, 23, 9)])
        XCTAssertEqual(sundayFirst, mondayFirst)
        XCTAssertEqual(rule.weekdays, [3, 6])
    }

    func testDailyInterval_anchorsToOriginalDayAndQueriesDistantWindow() {
        let series = event(start: date(1, 1, 9), rule: EventRecurrenceRule(frequency: .daily, interval: 3, timeZoneIdentifier: "Asia/Tokyo"))
        let result = expand(series, from: date(10, 1), to: date(10, 8))
        XCTAssertEqual(result.map(\.startDate), [date(10, 1, 9), date(10, 4, 9), date(10, 7, 9)])
    }

    func testWeeklyTime_preservesWallClockAcrossSpringAndAutumnDST() {
        let zone = "America/Los_Angeles"
        let spring = event(start: date(3, 1, 9, zone: zone), rule: EventRecurrenceRule(frequency: .weekly, timeZoneIdentifier: zone))
        let springResult = expand(spring, from: date(3, 1, zone: zone), to: date(3, 16, zone: zone), displayCalendar: calendar(zone))
        XCTAssertEqual(springResult.map(\.startDate), [date(3, 1, 9, zone: zone), date(3, 8, 9, zone: zone), date(3, 15, 9, zone: zone)])
        XCTAssertEqual(springResult[1].startDate.timeIntervalSince(springResult[0].startDate), 167 * 3_600)
        let autumn = event(start: date(10, 25, 9, zone: zone), rule: EventRecurrenceRule(frequency: .weekly, timeZoneIdentifier: zone))
        let autumnResult = expand(autumn, from: date(10, 25, zone: zone), to: date(11, 3, zone: zone), displayCalendar: calendar(zone))
        XCTAssertEqual(autumnResult.map(\.startDate), [date(10, 25, 9, zone: zone), date(11, 1, 9, zone: zone)])
        XCTAssertEqual(autumnResult[1].startDate.timeIntervalSince(autumnResult[0].startDate), 169 * 3_600)
    }

    func testNonexistentSpringTime_shiftsThatOccurrenceAndReturnsToOriginalWallTime() {
        let zone = "America/Los_Angeles"
        let series = event(start: date(3, 1, 2, 30, zone: zone), rule: EventRecurrenceRule(frequency: .weekly, timeZoneIdentifier: zone))
        let result = expand(series, from: date(3, 1, zone: zone), to: date(3, 16, zone: zone), displayCalendar: calendar(zone))
        XCTAssertEqual(result.map(\.startDate), [date(3, 1, 2, 30, zone: zone), date(3, 8, 3, 30, zone: zone), date(3, 15, 2, 30, zone: zone)])
    }

    func testAllDayMultipleDays_preservesDateLabelsAcrossDSTAndDisplayTimeZones() {
        let zone = "America/Los_Angeles"
        let series = event(start: date(3, 7, zone: zone), end: date(3, 9, zone: zone),
                           rule: EventRecurrenceRule(frequency: .weekly, timeZoneIdentifier: zone), allDay: true)
        let result = expand(series, from: date(3, 8), to: date(3, 9))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.displayStartDate(calendar: calendar()), date(3, 7))
        XCTAssertEqual(result.first?.displayEndDate(calendar: calendar()), date(3, 9))
        XCTAssertEqual(result.first?.endDate.timeIntervalSince(result[0].startDate), 47 * 3_600)
        XCTAssertTrue(expand(series, from: date(3, 9), to: date(3, 10)).isEmpty)
    }

    func testMultiDayTimedOccurrence_includesEarlierStartOverlappingQuery() {
        let series = event(start: date(10, 5, 22), end: date(10, 7, 1),
                           rule: EventRecurrenceRule(frequency: .weekly, timeZoneIdentifier: "Asia/Tokyo"))
        let result = expand(series, from: date(10, 13), to: date(10, 14))
        XCTAssertEqual(result.map(\.startDate), [date(10, 12, 22)])
        XCTAssertEqual(result.first?.endDate, date(10, 14, 1))
    }

    func testMidnightDSTTransition_preservesDayCadenceAndAllDayLength() {
        let zone = "America/Havana"
        // March 8 starts at 01:00; the following date starts at midnight.
        let daily = event(start: date(3, 8, 9, zone: zone),
                          rule: EventRecurrenceRule(frequency: .daily, interval: 2, timeZoneIdentifier: zone))
        XCTAssertEqual(expand(daily, from: date(3, 8, zone: zone), to: date(3, 13, zone: zone), displayCalendar: calendar(zone)).map(\.startDate),
                       [date(3, 8, 9, zone: zone), date(3, 10, 9, zone: zone), date(3, 12, 9, zone: zone)])
        let allDay = event(start: date(3, 8, zone: zone), end: date(3, 10, zone: zone),
                           rule: EventRecurrenceRule(frequency: .weekly, timeZoneIdentifier: zone), allDay: true)
        let result = expand(allDay, from: date(3, 8, zone: zone), to: date(3, 18, zone: zone), displayCalendar: calendar(zone))
        XCTAssertEqual(result.map(\.startDate), [date(3, 8, zone: zone), date(3, 15, zone: zone)])
        XCTAssertEqual(result.map(\.endDate), [date(3, 10, zone: zone), date(3, 17, zone: zone)])
    }

    func testAbsoluteReminder_inheritedOffsetMovesButExplicitExceptionDoesNot() throws {
        var series = event(start: date(10, 5, 9), rule: EventRecurrenceRule(frequency: .weekly, timeZoneIdentifier: "Asia/Tokyo"))
        series.reminderDate = date(10, 5, 8)
        let occurrence = try XCTUnwrap(expand(series, from: date(10, 12), to: date(10, 13)).first)
        XCTAssertEqual(occurrence.reminderDate, date(10, 12, 8))
        var replacement = occurrence
        replacement.reminderDate = date(10, 10, 8)
        let exception = CalendarEventException(seriesID: series.id, originalStartDate: occurrence.startDate, replacement: replacement)
        XCTAssertEqual(expand(series, from: date(10, 12), to: date(10, 13), exceptions: [exception]).first?.reminderDate, date(10, 10, 8))
    }

    func testAllDayAbsoluteReminder_preservesLocalCalendarTimeAcrossDST() {
        let zone = "America/Los_Angeles"
        var series = event(start: date(3, 1, zone: zone), end: date(3, 2, zone: zone),
                           rule: EventRecurrenceRule(frequency: .weekly, timeZoneIdentifier: zone), allDay: true)
        series.reminderDate = date(2, 28, 9, zone: zone)
        XCTAssertEqual(expand(series, from: date(3, 15, zone: zone), to: date(3, 16, zone: zone), displayCalendar: calendar(zone)).first?.reminderDate,
                       date(3, 14, 9, zone: zone))
    }

    func testResolvedOccurrence_isNotExpandedAgainAndSingleEventsRemainUnchanged() throws {
        let single = event(start: date(10, 5, 12))
        XCTAssertEqual(expand(single, from: date(10, 5), to: date(10, 6)), [single])
        let series = event(start: date(10, 5, 9), rule: EventRecurrenceRule(frequency: .daily, timeZoneIdentifier: "Asia/Tokyo"))
        let occurrence = try XCTUnwrap(expand(series, from: date(10, 5), to: date(10, 6)).first)
        XCTAssertEqual(expand(occurrence, from: date(10, 1), to: date(11, 1)), [occurrence])
        XCTAssertTrue(expand(series, from: date(10, 5), to: date(10, 5)).isEmpty)
    }

    func testResolvedQuery_mergesExternalEventsAfterApplyingLocalExceptions() {
        let series = event(start: date(10, 5, 9), rule: EventRecurrenceRule(frequency: .daily, timeZoneIdentifier: "Asia/Tokyo"))
        let external = event(start: date(10, 6, 8))
        let skip = CalendarEventException(seriesID: series.id, originalStartDate: date(10, 6, 9))
        let result = EventQuerying.resolved(internalEvents: [series], exceptions: [skip], externalEvents: [external, external],
                                           rangeStart: date(10, 5), rangeEndExclusive: date(10, 7), calendar: calendar())
        XCTAssertEqual(result.map(\.startDate), [date(10, 5, 9), date(10, 6, 8)])
    }
}
