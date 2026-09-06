import XCTest
@testable import lifelify

final class DeepLinkManagerTests: XCTestCase {
    @MainActor
    func testCalendarDateURL_selectsTheRequestedLocalDay() async throws {
        let manager = DeepLinkManager.shared
        defer { manager.clearPendingWidgetDestination() }

        XCTAssertTrue(manager.handleWidgetURL(try XCTUnwrap(URL(string: "lifelog://calendar?date=2028-02-29"))))
        guard case .calendar(let date) = manager.pendingWidgetDestination else {
            return XCTFail("Expected a calendar destination")
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(components.year, 2028)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 29)
        XCTAssertEqual(date, calendar.startOfDay(for: date))
    }

    @MainActor
    func testInvalidCalendarDateURL_keepsTheExistingDestination() async throws {
        let manager = DeepLinkManager.shared
        defer { manager.clearPendingWidgetDestination() }
        manager.pendingWidgetDestination = .memo

        let invalidDates = ["2026-02-29", "2026-04-31", "2026-13-01", "2026-00-01",
                            "2026-09-00", "0000-09-06", "2026-9-06", "2026-09-6",
                            "2026-09-06extra", "2026-09-06T12:00:00Z", "not-a-date", ""]
        for value in invalidDates {
            let url = try XCTUnwrap(URL(string: "lifelog://calendar?date=\(value)"))
            XCTAssertFalse(manager.handleWidgetURL(url), value)
            XCTAssertEqual(manager.pendingWidgetDestination, .memo, value)
        }
        XCTAssertFalse(manager.handleWidgetURL(try XCTUnwrap(URL(string: "lifelog://calendar"))))
        XCTAssertFalse(manager.handleWidgetURL(try XCTUnwrap(URL(string: "https://calendar?date=2026-09-06"))))
        XCTAssertEqual(manager.pendingWidgetDestination, .memo)
    }

    @MainActor
    func testCalendarDateURLAfterClearing_canOpenTheSameDayAgain() async throws {
        let manager = DeepLinkManager.shared
        defer { manager.clearPendingWidgetDestination() }
        let url = try XCTUnwrap(URL(string: "lifelog://calendar?date=2026-09-06"))

        XCTAssertTrue(manager.handleWidgetURL(url))
        let originalDestination = manager.pendingWidgetDestination
        manager.clearPendingWidgetDestination()
        XCTAssertNil(manager.pendingWidgetDestination)
        XCTAssertTrue(manager.handleWidgetURL(url))
        XCTAssertEqual(manager.pendingWidgetDestination, originalDestination)
    }

    @MainActor
    func testMemoWidgetURL_preservesTheMemoDestination() async throws {
        let manager = DeepLinkManager.shared
        defer { manager.clearPendingWidgetDestination() }

        XCTAssertTrue(manager.handleWidgetURL(try XCTUnwrap(URL(string: "lifelog://memo"))))
        XCTAssertEqual(manager.pendingWidgetDestination, .memo)
    }
}
