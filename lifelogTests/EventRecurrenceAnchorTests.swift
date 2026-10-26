import XCTest
@testable import lifelify

@MainActor
final class EventRecurrenceAnchorTests: XCTestCase {
    func testLegacyRuleJSON_withoutAnchorRetainsOriginalCadence() throws {
        let rule = EventRecurrenceRule(frequency: .weekly, interval: 2, weekdays: [2], timeZoneIdentifier: "UTC")
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(rule)) as? [String: Any])
        payload.removeValue(forKey: "anchorDate")

        let decoded = try JSONDecoder().decode(EventRecurrenceRule.self, from: JSONSerialization.data(withJSONObject: payload))

        XCTAssertEqual(decoded, rule)
        XCTAssertNil(decoded.anchorDate)
    }

    func testWeeklyAnchor_keepsPhaseSeparateFromLaterTemplateLowerBound() {
        let rule = EventRecurrenceRule(frequency: .weekly, interval: 2, weekdays: [2], timeZoneIdentifier: "UTC", anchorDate: date(4))
        let series = CalendarEvent(title: "Weekly", startDate: date(11), endDate: date(11).addingTimeInterval(3_600), calendarName: "Work", recurrenceRule: rule)

        XCTAssertEqual(occurrences(series, from: 11, to: 31).map(\.startDate), [date(18)])
        XCTAssertNil(EventRecurrenceExpander.originalOccurrence(of: series, startingAt: date(11), calendar: calendar))
        XCTAssertNotNil(EventRecurrenceExpander.originalOccurrence(of: series, startingAt: date(18), calendar: calendar))
    }

    func testDailyAnchor_keepsArbitraryDayIntervalAcrossFutureSplit() {
        let rule = EventRecurrenceRule(frequency: .daily, interval: 3, timeZoneIdentifier: "UTC", anchorDate: date(4))
        let series = CalendarEvent(title: "Daily", startDate: date(5), endDate: date(5).addingTimeInterval(3_600), calendarName: "Work", recurrenceRule: rule)

        XCTAssertEqual(occurrences(series, from: 5, to: 14).map(\.startDate), [date(7), date(10), date(13)])
    }

    func testAnchorAfterTemplate_usesSamePhaseForHistoricalOccurrences() {
        let rule = EventRecurrenceRule(frequency: .weekly, interval: 2, weekdays: [2], timeZoneIdentifier: "UTC", anchorDate: date(18))
        let series = CalendarEvent(title: "Historical", startDate: date(4), endDate: date(4).addingTimeInterval(3_600), calendarName: "Work", recurrenceRule: rule)

        XCTAssertEqual(occurrences(series, from: 4, to: 25).map(\.startDate), [date(4), date(18)])
    }

    private func occurrences(_ series: CalendarEvent, from: Int, to: Int) -> [CalendarEvent] {
        EventRecurrenceExpander.occurrences(events: [series], exceptions: [], rangeStart: date(from, hour: 0), rangeEndExclusive: date(to, hour: 0), calendar: calendar)
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2030, month: 3, day: day, hour: hour))!
    }
}
