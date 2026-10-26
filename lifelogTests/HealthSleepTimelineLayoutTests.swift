import XCTest
@testable import lifelify

final class HealthSleepTimelineLayoutTests: XCTestCase {
    func testFallRepeatedHour_preservesTwentyMinutesInSeparateClockLanes() throws {
        let calendar = calendar(timeZone: "America/Los_Angeles")
        let start = try instant("2026-11-01T01:50:00-07:00")
        let end = try instant("2026-11-01T01:10:00-08:00")
        let day = try instant("2026-11-01T00:00:00-07:00")
        let segments = HealthSleepTimelineLayout.segments(from: start, to: end, relativeTo: day, calendar: calendar)

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].startHour, 1 + 50.0 / 60, accuracy: 0.000_001)
        XCTAssertEqual(segments[0].endHour, 2, accuracy: 0.000_001)
        XCTAssertEqual(segments[0].lane, .beforeClockChange)
        XCTAssertEqual(segments[1].startHour, 1, accuracy: 0.000_001)
        XCTAssertEqual(segments[1].endHour, 1 + 10.0 / 60, accuracy: 0.000_001)
        XCTAssertEqual(segments[1].lane, .afterClockChange)
        XCTAssertEqual(segments[1].endDate, end)
        assertElapsedDuration(segments, from: start, to: end)
    }

    func testFallWholeNight_keepsRealClockEndpointsAndNineHours() throws {
        let calendar = calendar(timeZone: "America/Los_Angeles")
        let start = try instant("2026-10-31T23:00:00-07:00")
        let end = try instant("2026-11-01T07:00:00-08:00")
        let day = try instant("2026-11-01T00:00:00-07:00")
        let segments = HealthSleepTimelineLayout.segments(from: start, to: end, relativeTo: day, calendar: calendar)

        XCTAssertEqual(segments.map(\.startHour), [-1, 1])
        XCTAssertEqual(segments.map(\.endHour), [2, 7])
        XCTAssertEqual(segments.map(\.lane), [.beforeClockChange, .afterClockChange])
        XCTAssertEqual(end.timeIntervalSince(start), 9 * 3_600)
        assertElapsedDuration(segments, from: start, to: end)
    }

    func testFallSeparateStages_shareBeforeAndAfterLanes() throws {
        let calendar = calendar(timeZone: "America/Los_Angeles")
        let day = try instant("2026-11-01T00:00:00-07:00")
        let before = HealthSleepTimelineLayout.segments(
            from: try instant("2026-11-01T01:10:00-07:00"),
            to: try instant("2026-11-01T01:30:00-07:00"), relativeTo: day, calendar: calendar
        )
        let after = HealthSleepTimelineLayout.segments(
            from: try instant("2026-11-01T01:10:00-08:00"),
            to: try instant("2026-11-01T01:30:00-08:00"), relativeTo: day, calendar: calendar
        )

        XCTAssertEqual(before.first?.lane, .beforeClockChange)
        XCTAssertEqual(after.first?.lane, .afterClockChange)
        XCTAssertEqual(before.first?.startHour, after.first?.startHour)
        XCTAssertEqual(before.first?.endHour, after.first?.endHour)
        XCTAssertLessThan(HealthSleepTimelineLayout.Lane.beforeClockChange.fractions.upperBound,
                          HealthSleepTimelineLayout.Lane.afterClockChange.fractions.lowerBound)
    }

    func testExactFallTransitionEndpoint_doesNotCreateEmptyBand() throws {
        let calendar = calendar(timeZone: "America/Los_Angeles")
        let day = try instant("2026-11-01T00:00:00-07:00")
        let start = try instant("2026-11-01T01:50:00-07:00")
        let end = try instant("2026-11-01T01:00:00-08:00")
        let segments = HealthSleepTimelineLayout.segments(from: start, to: end, relativeTo: day, calendar: calendar)

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].endHour, 2, accuracy: 0.000_001)
        XCTAssertEqual(segments[0].lane, .beforeClockChange)
        assertElapsedDuration(segments, from: start, to: end)
    }

    func testSpringClockGap_preservesTwentyMinutesAndLeavesMissingHourBlank() throws {
        let calendar = calendar(timeZone: "America/Los_Angeles")
        let start = try instant("2026-03-08T01:50:00-08:00")
        let end = try instant("2026-03-08T03:10:00-07:00")
        let day = try instant("2026-03-08T00:00:00-08:00")
        let segments = HealthSleepTimelineLayout.segments(from: start, to: end, relativeTo: day, calendar: calendar)

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].endHour, 2, accuracy: 0.000_001)
        XCTAssertEqual(segments[1].startHour, 3, accuracy: 0.000_001)
        XCTAssertEqual(segments[1].endHour, 3 + 10.0 / 60, accuracy: 0.000_001)
        XCTAssertTrue(segments.allSatisfy { $0.lane == .full })
        assertElapsedDuration(segments, from: start, to: end)
    }

    func testSpringWholeNight_keepsSevenHoursWithoutFillingClockGap() throws {
        let calendar = calendar(timeZone: "America/Los_Angeles")
        let start = try instant("2026-03-07T23:00:00-08:00")
        let end = try instant("2026-03-08T07:00:00-07:00")
        let day = try instant("2026-03-08T00:00:00-08:00")
        let segments = HealthSleepTimelineLayout.segments(from: start, to: end, relativeTo: day, calendar: calendar)

        XCTAssertEqual(segments.map(\.startHour), [-1, 3])
        XCTAssertEqual(segments.map(\.endHour), [2, 7])
        XCTAssertEqual(end.timeIntervalSince(start), 7 * 3_600)
        assertElapsedDuration(segments, from: start, to: end)
    }

    func testOrdinaryNight_usesFullWidthAndPreviousEveningCoordinates() throws {
        let calendar = calendar(timeZone: "Asia/Tokyo")
        let start = try instant("2026-10-11T23:00:00+09:00")
        let end = try instant("2026-10-12T07:00:00+09:00")
        let day = try instant("2026-10-12T00:00:00+09:00")
        let segments = HealthSleepTimelineLayout.segments(from: start, to: end, relativeTo: day, calendar: calendar)

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].startHour, -1)
        XCTAssertEqual(segments[0].endHour, 7)
        XCTAssertEqual(segments[0].lane, .full)
        assertElapsedDuration(segments, from: start, to: end)
    }

    func testAxis_adaptsToActualSleepAndRetainsOutsideFormerWindow() throws {
        let calendar = calendar(timeZone: "Asia/Tokyo")
        let day = try instant("2026-10-12T00:00:00+09:00")
        let segments = HealthSleepTimelineLayout.segments(
            from: try instant("2026-10-11T17:00:00+09:00"),
            to: try instant("2026-10-12T20:00:00+09:00"), relativeTo: day, calendar: calendar
        )
        let axis = HealthSleepTimelineLayout.axis(for: segments)

        XCTAssertEqual(segments[0].startHour, -7)
        XCTAssertEqual(segments[0].endHour, 20)
        XCTAssertLessThan(axis.lowerHour, -7)
        XCTAssertGreaterThan(axis.upperHour, 20)
        XCTAssertTrue(axis.yDomain.contains(-segments[0].startHour))
        XCTAssertTrue(axis.yDomain.contains(-segments[0].endHour))
        XCTAssertEqual(axis.tickHours, axis.tickHours.sorted())
    }

    func testAxis_regularNightDoesNotReserveTwentyFourHours() throws {
        let calendar = calendar(timeZone: "Asia/Tokyo")
        let segments = HealthSleepTimelineLayout.segments(
            from: try instant("2026-10-11T23:00:00+09:00"),
            to: try instant("2026-10-12T07:00:00+09:00"),
            relativeTo: try instant("2026-10-12T00:00:00+09:00"), calendar: calendar
        )
        let axis = HealthSleepTimelineLayout.axis(for: segments)
        XCTAssertLessThan(axis.upperHour - axis.lowerHour, 24)
        XCTAssertTrue(axis.tickHours.contains(0))
    }

    func testClockComponents_distinguishesPreviousCurrentAndFollowingDays() {
        XCTAssertEqual(HealthSleepTimelineLayout.clockComponents(for: -6), .init(dayOffset: -1, hour: 18, minute: 0))
        XCTAssertEqual(HealthSleepTimelineLayout.clockComponents(for: 0), .init(dayOffset: 0, hour: 0, minute: 0))
        XCTAssertEqual(HealthSleepTimelineLayout.clockComponents(for: 24), .init(dayOffset: 1, hour: 0, minute: 0))
        XCTAssertEqual(HealthSleepTimelineLayout.clockComponents(for: -25), .init(dayOffset: -2, hour: 23, minute: 0))
    }

    func testClockLabels_formatNominalMissingHourWithoutDSTCorrection() {
        XCTAssertEqual(HealthSleepTimelineLayout.clockText(for: 2, locale: Locale(identifier: "en_GB")), "02:00")
        XCTAssertEqual(HealthSleepTimelineLayout.clockText(for: 1 + 10.0 / 60, locale: Locale(identifier: "en_GB")), "01:10")
        XCTAssertEqual(HealthSleepTimelineLayout.clockText(for: -6, locale: Locale(identifier: "en_GB")), "18:00")
    }

    private func assertElapsedDuration(
        _ segments: [HealthSleepTimelineLayout.Segment],
        from start: Date,
        to end: Date,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(segments.allSatisfy { $0.startDate < $0.endDate && $0.startHour < $0.endHour }, file: file, line: line)
        let drawnSeconds = segments.reduce(0) { $0 + ($1.endHour - $1.startHour) * 3_600 }
        XCTAssertEqual(drawnSeconds, end.timeIntervalSince(start), accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(segments.first?.startDate, start, file: file, line: line)
        XCTAssertEqual(segments.last?.endDate, end, file: file, line: line)
    }

    private func instant(_ text: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: text))
    }

    private func calendar(timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }
}
