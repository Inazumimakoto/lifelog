import XCTest
@testable import lifelify

final class HealthQueryWindowTests: XCTestCase {
    func testRecentWindow_includesTodayAndRequestedHistoricalDays() throws {
        let calendar = try calendar(timeZone: "Asia/Tokyo")
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 15)))
        let window = try XCTUnwrap(HealthQueryWindow(lastNDays: 7, referenceDate: reference, calendar: calendar))

        XCTAssertEqual(window.summaryDays.count, 8)
        XCTAssertEqual(window.summaryDays.first, calendar.startOfDay(for: reference))
        XCTAssertEqual(window.start, window.summaryDays.last)
        XCTAssertGreaterThan(window.endExclusive, reference)
        XCTAssertEqual(calendar.component(.day, from: window.endExclusive), 13)
    }

    func testDSTTransition_usesCalendarDaysInsteadOfFixed24HourOffsets() throws {
        let calendar = try calendar(timeZone: "America/Los_Angeles")
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 16)))
        let window = try XCTUnwrap(HealthQueryWindow(lastNDays: 1, referenceDate: reference, calendar: calendar))

        XCTAssertEqual(window.endExclusive.timeIntervalSince(window.summaryDays[0]), 23 * 3_600)
        XCTAssertEqual(window.summaryDays.map { calendar.component(.hour, from: $0) }, [0, 0])
        XCTAssertEqual(window.summaryDays.map { calendar.component(.day, from: $0) }, [8, 7])
    }

    func testTodayOnlyWindow_canIncludeOvernightSleepAndTodaysActivity() throws {
        let calendar = try calendar(timeZone: "Asia/Tokyo")
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 15)))
        let window = try XCTUnwrap(HealthQueryWindow(lastNDays: 0, referenceDate: reference, calendar: calendar))

        XCTAssertEqual(window.summaryDays, [calendar.startOfDay(for: reference)])
        XCTAssertLessThan(window.start, reference)
        XCTAssertGreaterThan(window.endExclusive, reference)
    }

    func testNegativeDays_returnsNoWindow() {
        XCTAssertNil(HealthQueryWindow(lastNDays: -1))
    }

    private func calendar(timeZone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: timeZone))
        return calendar
    }
}
