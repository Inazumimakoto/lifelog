import XCTest
@testable import lifelify

final class CalendarDayLinkTests: XCTestCase {
    func testDateURLRoundTrip_preservesTheDayAcrossTimeZonesAndDST() throws {
        let timeZoneIDs = ["Asia/Tokyo", "America/Los_Angeles", "Pacific/Kiritimati", "America/Santiago"]
        let dates = [DateComponents(year: 2026, month: 3, day: 8, hour: 12),
                     DateComponents(year: 2026, month: 9, day: 6, hour: 12),
                     DateComponents(year: 2026, month: 11, day: 1, hour: 12)]

        for timeZoneID in timeZoneIDs {
            let timeZone = try XCTUnwrap(TimeZone(identifier: timeZoneID))
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            for components in dates {
                let date = try XCTUnwrap(calendar.date(from: components))
                let url = CalendarDayLink.url(for: date, timeZone: timeZone)
                let decoded = try XCTUnwrap(CalendarDayLink.date(from: url, timeZone: timeZone))
                XCTAssertEqual(decoded, calendar.startOfDay(for: date), "\(timeZoneID): \(url)")
            }
        }
    }

    func testDateURL_usesGregorianASCIIComponents() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 9 * 60 * 60))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6)))

        XCTAssertEqual(CalendarDayLink.url(for: date, timeZone: calendar.timeZone).absoluteString,
                       "lifelog://calendar?date=2026-09-06")
    }
}
