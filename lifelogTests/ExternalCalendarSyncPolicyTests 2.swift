import XCTest
@testable import lifelify

@MainActor
final class ExternalCalendarSyncPolicyTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testRangeForMidMonth_spansSixPreviousAndEighteenFutureMonths() {
        let range = ExternalCalendarSyncPolicy.desiredRange(for: date(2026, 10, 12, hour: 15), calendar: calendar)

        XCTAssertEqual(range.start, date(2026, 4, 1))
        XCTAssertEqual(range.end, date(2028, 5, 1).addingTimeInterval(-1))
    }

    func testSameDaySync_throttlesInclusiveStableWindowAndPrefetchesOutsideIt() {
        let reference = date(2026, 10, 12, hour: 22)
        let range = ExternalCalendarSyncPolicy.desiredRange(for: reference, calendar: calendar)
        let last = date(2026, 10, 12, hour: 2)
        func shouldSync(anchor: Date) -> Bool {
            ExternalCalendarSyncPolicy.shouldSync(anchor: anchor, storedRange: range,
                                                 lastSyncDate: last, referenceDate: reference, calendar: calendar)
        }

        XCTAssertFalse(shouldSync(anchor: date(2026, 6, 1)))
        XCTAssertFalse(shouldSync(anchor: date(2028, 2, 29)))
        XCTAssertTrue(shouldSync(anchor: date(2026, 5, 31)))
        XCTAssertTrue(shouldSync(anchor: date(2028, 3, 1)))
    }

    func testYesterdayOrMissingSync_refreshesEvenInsideStableWindow() {
        let reference = date(2026, 10, 12)
        let range = ExternalCalendarSyncPolicy.desiredRange(for: reference, calendar: calendar)

        XCTAssertTrue(ExternalCalendarSyncPolicy.shouldSync(anchor: reference, storedRange: range,
                                                           lastSyncDate: date(2026, 10, 11, hour: 23),
                                                           referenceDate: reference, calendar: calendar))
        XCTAssertTrue(ExternalCalendarSyncPolicy.shouldSync(anchor: reference, storedRange: range,
                                                           lastSyncDate: nil, referenceDate: reference,
                                                           calendar: calendar))
    }

    func testMissingStoredRange_preservesLegacyDailyThrottle() {
        let reference = date(2026, 10, 12, hour: 10)

        XCTAssertFalse(ExternalCalendarSyncPolicy.shouldSync(anchor: date(2030, 1, 1), storedRange: nil,
                                                            lastSyncDate: reference, referenceDate: reference,
                                                            calendar: calendar))
        XCTAssertTrue(ExternalCalendarSyncPolicy.shouldSync(anchor: reference, storedRange: nil,
                                                           lastSyncDate: date(2026, 10, 11),
                                                           referenceDate: reference, calendar: calendar))
    }

    func testForce_bypassesBothRangeAndDailyThrottle() {
        let reference = date(2026, 10, 12)
        let range = ExternalCalendarSyncPolicy.desiredRange(for: reference, calendar: calendar)

        XCTAssertTrue(ExternalCalendarSyncPolicy.shouldSync(anchor: reference, storedRange: range,
                                                           lastSyncDate: reference, referenceDate: reference,
                                                           calendar: calendar, force: true))
        XCTAssertTrue(ExternalCalendarSyncPolicy.shouldSync(anchor: reference, storedRange: nil,
                                                           lastSyncDate: reference, referenceDate: reference,
                                                           calendar: calendar, force: true))
    }
}
