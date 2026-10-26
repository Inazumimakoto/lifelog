import XCTest
@testable import lifelify

@MainActor
final class EventRecurrencePerformanceTests: XCTestCase {
    func testRareDailyInterval_distantWindowPreservesOriginalPhaseAndBounds() {
        let calendar = calendar()
        let first = date(2000, 2, 29, hour: 9)
        let series = event(start: first, frequency: .daily, interval: 367)
        let cycle29 = calendar.date(byAdding: .day, value: 367 * 29, to: first)!
        let cycle31 = calendar.date(byAdding: .day, value: 367 * 31, to: first)!
        let result = expand(series, from: cycle29.addingTimeInterval(-3_600), to: cycle31.addingTimeInterval(3_600))

        XCTAssertEqual(result.map(\.startDate), (29...31).map { calendar.date(byAdding: .day, value: 367 * $0, to: first)! })
        for occurrence in result {
            XCTAssertEqual(EventRecurrenceExpander.originalOccurrence(of: series, startingAt: occurrence.startDate, calendar: calendar), occurrence)
        }
        var extremeInterval = series
        extremeInterval.recurrenceRule?.interval = .max
        XCTAssertTrue(expand(extremeInterval, from: cycle29, to: cycle31).isEmpty)
        XCTAssertEqual(expand(extremeInterval, from: first, to: first.addingTimeInterval(86_400)).count, 1)
    }

    func testRareWeeklyInterval_historicalWindowKeepsPartialFirstWeekAndMultipleWeekdays() {
        let calendar = calendar()
        let first = date(2000, 1, 3, hour: 9)
        let series = event(start: first, frequency: .weekly, interval: 29, weekdays: [2, 4])
        let cycle85 = calendar.date(byAdding: .day, value: 29 * 7 * 85, to: first)!
        let cycle87 = calendar.date(byAdding: .day, value: 29 * 7 * 87, to: first)!
        let result = expand(series, from: cycle85.addingTimeInterval(86_400), to: cycle87.addingTimeInterval(86_400 * 3))
        let expected = [85, 86, 87].flatMap { cycle in
            [0, 2].map { offset in calendar.date(byAdding: .day, value: 29 * 7 * cycle + offset, to: first)! }
        }.filter { $0 > cycle85 }

        XCTAssertEqual(result.map(\.startDate), expected)
        var extremeInterval = series
        extremeInterval.recurrenceRule?.interval = .max
        XCTAssertTrue(expand(extremeInterval, from: cycle85, to: cycle87).isEmpty)
    }

    func testSkippedCivilDate_preservesDailyAndBiweeklyDayCadenceWithoutDuplicates() {
        let zone = "Pacific/Apia"
        let display = calendar(zone)
        let daily = event(start: date(2011, 12, 29, hour: 9, zone: zone), frequency: .daily, interval: 2, zone: zone)
        let dailyResult = expand(daily, from: date(2011, 12, 28, zone: zone), to: date(2012, 1, 5, zone: zone), calendar: display)
        XCTAssertEqual(dailyResult.map(\.startDate), [date(2011, 12, 29, hour: 9, zone: zone), date(2012, 1, 1, hour: 9, zone: zone), date(2012, 1, 3, hour: 9, zone: zone)])

        let weekly = event(start: date(2011, 12, 26, hour: 9, zone: zone), frequency: .weekly, interval: 2, weekdays: [1, 2], zone: zone)
        let weeklyResult = expand(weekly, from: date(2011, 12, 25, zone: zone), to: date(2012, 1, 18, zone: zone), calendar: display)
        XCTAssertEqual(weeklyResult.map(\.startDate), [date(2011, 12, 26, hour: 9, zone: zone), date(2012, 1, 1, hour: 9, zone: zone), date(2012, 1, 2, hour: 9, zone: zone), date(2012, 1, 15, hour: 9, zone: zone), date(2012, 1, 16, hour: 9, zone: zone)])
        XCTAssertEqual(Set(weeklyResult.map(\.id)).count, weeklyResult.count)
    }

    func testOriginalOccurrence_directLookupMatchesDSTExpansionAndRejectsUnscheduledSlot() throws {
        let zone = "America/Los_Angeles"
        let display = calendar(zone)
        var series = event(start: date(2026, 3, 1, hour: 2, minute: 30, zone: zone), frequency: .weekly, weekdays: [1], zone: zone)
        series.endDate = series.startDate.addingTimeInterval(86_400 * 40)
        series.reminderDate = series.startDate.addingTimeInterval(-1_800)
        series.recurrenceRule?.until = date(2026, 3, 31, zone: zone)
        let originalStart = date(2026, 3, 8, hour: 3, minute: 30, zone: zone)
        let result = expand(series, from: date(2026, 3, 8, zone: zone), to: date(2026, 3, 9, zone: zone), calendar: display)
        let expected = try XCTUnwrap(result.first { $0.occurrenceReference?.originalStartDate == originalStart })

        XCTAssertEqual(EventRecurrenceExpander.originalOccurrence(of: series, startingAt: originalStart, calendar: display), expected)
        XCTAssertEqual(expected.urlString, series.urlString)
        XCTAssertEqual(expected.reminderDate, originalStart.addingTimeInterval(-1_800))
        XCTAssertNil(EventRecurrenceExpander.originalOccurrence(of: series, startingAt: originalStart.addingTimeInterval(60), calendar: display))
        XCTAssertNil(EventRecurrenceExpander.originalOccurrence(of: series, startingAt: date(2026, 3, 9, hour: 2, minute: 30, zone: zone), calendar: display))
        XCTAssertNil(EventRecurrenceExpander.originalOccurrence(of: series, startingAt: date(2026, 4, 5, hour: 2, minute: 30, zone: zone), calendar: display))
    }

    func testLongExpiredSeries_replacementMovedIntoWindowRetainsOriginalIdentityAndReminder() throws {
        var series = event(start: date(2000, 1, 3, hour: 9), frequency: .weekly, weekdays: [2])
        series.recurrenceRule?.until = date(2001, 1, 1)
        let original = try XCTUnwrap(EventRecurrenceExpander.originalOccurrence(of: series, startingAt: series.startDate, calendar: calendar()))
        var replacement = original
        replacement.startDate = date(2030, 3, 5, hour: 11)
        replacement.endDate = date(2030, 3, 5, hour: 12)
        replacement.reminderDate = date(2030, 3, 4, hour: 18)
        replacement.urlString = "https://example.com/moved"
        let exception = CalendarEventException(seriesID: series.id, originalStartDate: series.startDate, replacement: replacement)
        let result = EventRecurrenceExpander.occurrences(events: [series], exceptions: [exception], rangeStart: date(2030, 3, 1), rangeEndExclusive: date(2030, 4, 1), calendar: calendar())

        XCTAssertEqual(result, [replacement])
        XCTAssertEqual(result.first?.id, original.id)
        XCTAssertTrue(expand(series, from: date(2030, 3, 1), to: date(2030, 4, 1)).isEmpty)
    }

    func testUnsortedExpansionAndResolvedQuery_preserveMembershipAndFinalTieOrder() {
        let start = date(2026, 10, 5, hour: 9)
        let first = event(start: start, frequency: .daily)
        let second = event(start: start, frequency: .daily)
        let sorted = EventRecurrenceExpander.occurrences(events: [first, second], exceptions: [], rangeStart: start, rangeEndExclusive: start.addingTimeInterval(86_400 * 3), calendar: calendar())
        let unsorted = EventRecurrenceExpander.occurrences(events: [first, second], exceptions: [], rangeStart: start, rangeEndExclusive: start.addingTimeInterval(86_400 * 3), calendar: calendar(), sortResults: false)
        let resolved = EventQuerying.resolved(internalEvents: [first, second], exceptions: [], externalEvents: [], rangeStart: start, rangeEndExclusive: start.addingTimeInterval(86_400 * 3), calendar: calendar())

        XCTAssertEqual(Set(sorted), Set(unsorted))
        XCTAssertEqual(resolved, sorted)
        XCTAssertLessThan(sorted[0].id.uuidString, sorted[1].id.uuidString)
    }

    func testSparseBiweeklyTwentyYearWindow_performance() {
        let series = event(start: date(2000, 1, 3, hour: 9), frequency: .weekly, interval: 2, weekdays: [2])
        let from = date(2020, 1, 1), to = date(2040, 1, 1)
        var count = 0

        measure { count = expand(series, from: from, to: to).count }

        XCTAssertEqual(count, 522)
    }

    func testManyBiweeklyMastersOneMonth_performance() {
        let masters = (0..<120).map { index -> CalendarEvent in
            var series = event(start: date(2000, 1, 3, hour: 9), frequency: .weekly, interval: 2, weekdays: [2])
            series.title = "Meeting \(index)"
            return series
        }
        let from = date(2026, 10, 1), to = date(2026, 11, 1), display = calendar()
        var count = 0

        measure { count = EventRecurrenceExpander.occurrences(events: masters, exceptions: [], rangeStart: from, rangeEndExclusive: to, calendar: display).count }

        XCTAssertEqual(count, 240)
    }

    private func expand(_ series: CalendarEvent, from: Date, to: Date, calendar: Calendar? = nil) -> [CalendarEvent] {
        EventRecurrenceExpander.occurrences(events: [series], exceptions: [], rangeStart: from, rangeEndExclusive: to, calendar: calendar ?? self.calendar())
    }

    private func event(start: Date, frequency: EventRecurrenceRule.Frequency, interval: Int = 1,
                       weekdays: [Int] = [], zone: String = "UTC") -> CalendarEvent {
        CalendarEvent(title: "Recurring", startDate: start, endDate: start.addingTimeInterval(3_600), calendarName: "Work",
                      recurrenceRule: EventRecurrenceRule(frequency: frequency, interval: interval, weekdays: weekdays, timeZoneIdentifier: zone),
                      urlString: "https://example.com/original")
    }

    private func calendar(_ zone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0, zone: String = "UTC") -> Date {
        calendar(zone).date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
