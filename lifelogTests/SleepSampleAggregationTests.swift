import XCTest
@testable import lifelify

final class SleepSampleAggregationTests: XCTestCase {
    private typealias Sample = SleepSampleAggregation.Sample
    private typealias State = SleepSampleAggregation.State

    func testOvernightStages_assignsWholeSessionToWakeUpDay() throws {
        let samples = try [
            sample("2026-10-11 22:00", "2026-10-12 08:00", .inBed),
            sample("2026-10-11 23:00", "2026-10-11 23:30", .core),
            sample("2026-10-11 23:30", "2026-10-12 00:30", .deep),
            sample("2026-10-12 00:30", "2026-10-12 07:00", .rem)
        ]
        let days = try aggregate(samples)
        let day = try date("2026-10-12 00:00")
        let summary = try XCTUnwrap(days[day])

        XCTAssertEqual(Array(days.keys), [day])
        XCTAssertEqual(summary.duration, 8, accuracy: 0.000_001)
        XCTAssertEqual(summary.start, try date("2026-10-11 23:00"))
        XCTAssertEqual(summary.end, try date("2026-10-12 07:00"))
        XCTAssertEqual(summary.stages.map(\.state), [.core, .deep, .rem])
        assertNormalized(summary)
    }

    func testNightAndNap_includesBothAndKeepsMainSleepTimeline() throws {
        let samples = try [
            sample("2026-10-12 00:00", "2026-10-12 07:00", .unspecified),
            sample("2026-10-12 14:00", "2026-10-12 15:00", .core)
        ]
        for order in permutations(samples) {
            let summary = try XCTUnwrap(aggregate(order).values.first)
            XCTAssertEqual(summary.duration, 8, accuracy: 0.000_001)
            XCTAssertEqual(summary.start, try date("2026-10-12 00:00"))
            XCTAssertEqual(summary.end, try date("2026-10-12 07:00"))
            XCTAssertEqual(summary.stages.count, 2)
            assertNormalized(summary)
        }
    }

    func testOverlappingAndDuplicateSources_countsIntervalUnion() throws {
        let samples = try [
            sample("2026-10-12 00:00", "2026-10-12 06:00", .unspecified, source: "a"),
            sample("2026-10-12 05:00", "2026-10-12 07:00", .unspecified, source: "b"),
            sample("2026-10-12 00:00", "2026-10-12 06:00", .unspecified, source: "a")
        ]
        for order in permutations(samples) {
            let summary = try XCTUnwrap(aggregate(order).values.first)
            XCTAssertEqual(summary.duration, 7, accuracy: 0.000_001)
            XCTAssertEqual(summary.stages.count, 1)
            XCTAssertEqual(summary.stages.first?.state, .unspecified)
            assertNormalized(summary)
        }
    }

    func testDuplicateDetailedSources_keepsOneStageAndOneHour() throws {
        let samples = try [
            sample("2026-10-12 00:00", "2026-10-12 01:00", .core, source: "a"),
            sample("2026-10-12 00:00", "2026-10-12 01:00", .core, source: "b")
        ]
        let summary = try XCTUnwrap(aggregate(samples).values.first)

        XCTAssertEqual(summary.duration, 1, accuracy: 0.000_001)
        XCTAssertEqual(summary.stages.count, 1)
        assertNormalized(summary)
    }

    func testDetailedStagesAndAwake_overrideBroadUnspecifiedSleep() throws {
        let samples = try [
            sample("2026-10-12 00:00", "2026-10-12 07:00", .unspecified, source: "app"),
            sample("2026-10-12 00:00", "2026-10-12 03:00", .core, source: "watch"),
            sample("2026-10-12 03:00", "2026-10-12 03:30", .awake, source: "watch"),
            sample("2026-10-12 03:30", "2026-10-12 07:00", .deep, source: "watch")
        ]
        let expected = try aggregate(samples)
        for order in permutations(samples) {
            let days = try aggregate(order)
            XCTAssertEqual(days, expected)
            let summary = try XCTUnwrap(days.values.first)
            XCTAssertEqual(summary.duration, 6.5, accuracy: 0.000_001)
            XCTAssertEqual(summary.stages.map(\.state), [.core, .awake, .deep])
            assertNormalized(summary)
        }
    }

    func testConflictingDetailedSources_prefersWidestDetailedSleepCoverage() throws {
        let samples = try [
            sample("2026-10-12 00:00", "2026-10-12 03:00", .core, source: "watch"),
            sample("2026-10-12 03:00", "2026-10-12 03:30", .awake, source: "watch"),
            sample("2026-10-12 03:30", "2026-10-12 07:00", .deep, source: "watch"),
            sample("2026-10-12 03:00", "2026-10-12 04:00", .rem, source: "other")
        ]
        let expected = try aggregate(samples)
        for order in permutations(samples) {
            let summary = try XCTUnwrap(aggregate(order).values.first)
            XCTAssertEqual(summary, expected.values.first)
            XCTAssertEqual(summary.duration, 6.5, accuracy: 0.000_001)
            XCTAssertEqual(summary.stages.map(\.state), [.core, .awake, .deep])
            assertNormalized(summary)
        }
    }

    func testEqualDetailedCoverage_usesStableSourceIdentifier() throws {
        let samples = try [
            sample("2026-10-12 00:00", "2026-10-12 07:00", .core, source: "a"),
            sample("2026-10-12 00:00", "2026-10-12 07:00", .deep, source: "b")
        ]
        for order in permutations(samples) {
            let summary = try XCTUnwrap(aggregate(order).values.first)
            XCTAssertEqual(summary.stages.map(\.state), [.core])
            XCTAssertEqual(summary.duration, 7, accuracy: 0.000_001)
            assertNormalized(summary)
        }
    }

    func testSameSourceConflictingSleepStages_marksConflictUnspecified() throws {
        let samples = try [
            sample("2026-10-12 00:00", "2026-10-12 02:00", .core),
            sample("2026-10-12 01:00", "2026-10-12 03:00", .deep)
        ]
        let summary = try XCTUnwrap(aggregate(samples).values.first)

        XCTAssertEqual(summary.stages.map(\.state), [.core, .unspecified, .deep])
        XCTAssertEqual(summary.duration, 3, accuracy: 0.000_001)
        assertNormalized(summary)
    }

    func testSameSourceAwake_conflictDoesNotCountAsSleep() throws {
        let samples = try [
            sample("2026-10-12 00:00", "2026-10-12 07:00", .core),
            sample("2026-10-12 03:00", "2026-10-12 03:30", .awake)
        ]
        let summary = try XCTUnwrap(aggregate(samples).values.first)

        XCTAssertEqual(summary.stages.map(\.state), [.core, .awake, .core])
        XCTAssertEqual(summary.duration, 6.5, accuracy: 0.000_001)
        assertNormalized(summary)
    }

    func testBridgeStages_allOrdersKeepEveryStage() throws {
        let samples = try [
            sample("2026-10-12 00:00", "2026-10-12 01:00", .core),
            sample("2026-10-12 01:00", "2026-10-12 05:00", .deep),
            sample("2026-10-12 05:00", "2026-10-12 06:00", .rem)
        ]
        let expected = try aggregate(samples)
        for order in permutations(samples) {
            let result = try aggregate(order)
            XCTAssertEqual(result, expected)
            XCTAssertEqual(result.values.first?.duration, 6)
        }
    }

    func testAwakeOutsideResolvedSleep_trimsToActualSleepSession() throws {
        let samples = try [
            sample("2026-10-12 00:00", "2026-10-12 08:00", .unspecified),
            sample("2026-10-12 00:00", "2026-10-12 01:00", .awake),
            sample("2026-10-12 07:00", "2026-10-12 08:00", .awake)
        ]
        let summary = try XCTUnwrap(aggregate(samples).values.first)

        XCTAssertEqual(summary.duration, 6, accuracy: 0.000_001)
        XCTAssertEqual(summary.start, try date("2026-10-12 01:00"))
        XCTAssertEqual(summary.end, try date("2026-10-12 07:00"))
        XCTAssertEqual(summary.stages.map(\.state), [.unspecified])
        XCTAssertEqual(summary.stages.first?.start, summary.start)
        XCTAssertEqual(summary.stages.last?.end, summary.end)
        assertNormalized(summary)
    }

    func testUnmeasuredGap_doesNotInventSleepOrAwakeStages() throws {
        let samples = try [
            sample("2026-10-12 00:00", "2026-10-12 03:00", .core),
            sample("2026-10-12 03:30", "2026-10-12 07:00", .deep)
        ]
        let summary = try XCTUnwrap(aggregate(samples).values.first)

        XCTAssertEqual(summary.duration, 6.5, accuracy: 0.000_001)
        XCTAssertEqual(summary.stages.map(\.state), [.core, .deep])
        XCTAssertEqual(summary.stages[1].start.timeIntervalSince(summary.stages[0].end), 30 * 60)
        assertNormalized(summary)
    }

    func testInBedAndAwakeOnly_doesNotCreateSleepSummary() throws {
        let samples = try [
            sample("2026-10-12 00:00", "2026-10-12 08:00", .inBed),
            sample("2026-10-12 02:00", "2026-10-12 03:00", .awake)
        ]
        XCTAssertTrue(try aggregate(samples).isEmpty)
    }

    func testInvalidIntervals_areIgnored() throws {
        let samples = try [
            sample("2026-10-12 02:00", "2026-10-12 02:00", .core),
            sample("2026-10-12 03:00", "2026-10-12 02:00", .deep),
            sample("2026-10-12 00:00", "2026-10-12 07:00", .unspecified)
        ]
        let summary = try XCTUnwrap(aggregate(samples).values.first)
        XCTAssertEqual(summary.duration, 7, accuracy: 0.000_001)
        assertNormalized(summary)
    }

    func testQueryContext_includesFirstNightsPreMidnightStages() throws {
        let start = try date("2026-10-12 00:00")
        let end = try date("2026-10-13 00:00")
        let bounds = try XCTUnwrap(SleepSampleAggregation.queryBounds(from: start, to: end, calendar: calendar()))
        XCTAssertEqual(bounds.start, try date("2026-10-11 00:00"))
        XCTAssertEqual(bounds.end, try date("2026-10-14 00:00"))
        let samples = try [
            sample("2026-10-11 23:00", "2026-10-11 23:30", .core),
            sample("2026-10-11 23:30", "2026-10-12 07:00", .deep)
        ]
        // Match HealthKit's overlap predicate, without clipping sample endpoints.
        let queried = samples.filter { $0.end >= bounds.start && $0.start < bounds.end }
        let summary = try XCTUnwrap(aggregate(queried).values.first)
        XCTAssertEqual(summary.duration, 8, accuracy: 0.000_001)
        assertNormalized(summary)
    }

    func testMidnightWake_boundariesIncludeStartAndExcludeEnd() throws {
        let samples = try [
            sample("2026-10-11 22:00", "2026-10-12 00:00", .core),
            sample("2026-10-12 22:00", "2026-10-13 00:00", .deep)
        ]
        let summary = try XCTUnwrap(aggregate(samples).values.first)
        XCTAssertEqual(summary.duration, 2, accuracy: 0.000_001)
        XCTAssertEqual(summary.start, try date("2026-10-11 22:00"))
        assertNormalized(summary)
    }

    func testSessionCrossingTerminalBoundary_isExcludedWhole() throws {
        let samples = try [
            sample("2026-10-12 23:00", "2026-10-12 23:30", .core),
            sample("2026-10-12 23:30", "2026-10-13 07:00", .deep)
        ]
        XCTAssertTrue(try aggregate(samples).isEmpty)
    }

    func testDSTSleepDuration_usesElapsedSeconds() throws {
        let calendar = calendar(timeZone: "America/Los_Angeles")
        for (startText, endText, dayText, followingText, expected) in [
            ("2026-03-07 23:00", "2026-03-08 07:00", "2026-03-08 00:00", "2026-03-09 00:00", 7.0),
            ("2026-10-31 23:00", "2026-11-01 07:00", "2026-11-01 00:00", "2026-11-02 00:00", 9.0)
        ] {
            let start = try date(startText, calendar: calendar)
            let end = try date(endText, calendar: calendar)
            let day = try date(dayText, calendar: calendar)
            let following = try date(followingText, calendar: calendar)
            let result = SleepSampleAggregation.aggregate(
                [Sample(start: start, end: end, state: .unspecified)],
                from: day, to: following, calendar: calendar
            )
            let summary = try XCTUnwrap(result[day])
            XCTAssertEqual(summary.duration, expected, accuracy: 0.000_001)
            assertNormalized(summary)
        }
    }

    func testDSTQueryContext_usesCalendarDayArithmetic() throws {
        let calendar = calendar(timeZone: "America/Los_Angeles")
        let start = try date("2026-03-09 00:00", calendar: calendar)
        let end = try date("2026-03-10 00:00", calendar: calendar)
        let bounds = try XCTUnwrap(SleepSampleAggregation.queryBounds(from: start, to: end, calendar: calendar))

        XCTAssertEqual(bounds.start, try date("2026-03-08 00:00", calendar: calendar))
        XCTAssertEqual(start.timeIntervalSince(bounds.start), 23 * 3_600)
    }

    private func assertNormalized(
        _ summary: SleepSampleAggregation.DailySummary,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(summary.stages.allSatisfy { $0.start < $0.end && $0.state != .inBed }, file: file, line: line)
        XCTAssertTrue(zip(summary.stages, summary.stages.dropFirst()).allSatisfy { $0.end <= $1.start }, file: file, line: line)
        let duration = summary.stages.filter { $0.state.isAsleep }.reduce(0) {
            $0 + $1.end.timeIntervalSince($1.start) / 3_600
        }
        XCTAssertEqual(duration, summary.duration, accuracy: 0.000_001, file: file, line: line)
    }

    private func aggregate(_ samples: [Sample]) throws -> [Date: SleepSampleAggregation.DailySummary] {
        SleepSampleAggregation.aggregate(samples,
                                         from: try date("2026-10-12 00:00"),
                                         to: try date("2026-10-13 00:00"),
                                         calendar: calendar())
    }

    private func sample(_ start: String, _ end: String, _ state: State, source: String = "") throws -> Sample {
        Sample(start: try date(start), end: try date(end), state: state, sourceIdentifier: source)
    }

    private func date(_ text: String, calendar: Calendar? = nil) throws -> Date {
        let calendar = calendar ?? self.calendar()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return try XCTUnwrap(formatter.date(from: text))
    }

    private func calendar(timeZone: String = "Asia/Tokyo") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    private func permutations<T>(_ values: [T]) -> [[T]] {
        guard !values.isEmpty else { return [[]] }
        return values.indices.flatMap { index in
            var remainder = values
            let first = remainder.remove(at: index)
            return permutations(remainder).map { [first] + $0 }
        }
    }
}
