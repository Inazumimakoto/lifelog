import XCTest
@testable import lifelify

@MainActor
final class HealthSummaryMergingTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_700_000_000)

    func testEqualRefreshWithNewGeneratedIDs_preservesStoredSummaryAndStages() {
        var stored = HealthSummary(date: day)
        stored.steps = 1234
        stored.sleepStages = [SleepStage(start: day, end: day.addingTimeInterval(3600), stage: .deep)]
        var fetched = HealthSummary(date: day)
        fetched.steps = 1234
        fetched.sleepStages = [SleepStage(start: day, end: day.addingTimeInterval(3600), stage: .deep)]

        XCTAssertEqual(HealthSummaryMerging.merge(existing: [stored], incoming: [fetched]), [stored])
    }

    func testMissingMeasurements_preservesWeatherAndPreviousMeasurements() {
        var stored = HealthSummary(date: day)
        stored.steps = 1200
        stored.sleepHours = 7
        stored.weatherCondition = "Sunny"
        stored.highTemperature = 25
        var fetched = HealthSummary(date: day)
        fetched.steps = 2400

        let merged = HealthSummaryMerging.merge(existing: [stored], incoming: [fetched])[0]
        XCTAssertEqual(merged.id, stored.id)
        XCTAssertEqual(merged.steps, 2400)
        XCTAssertEqual(merged.sleepHours, 7)
        XCTAssertEqual(merged.weatherCondition, "Sunny")
        XCTAssertEqual(merged.highTemperature, 25)
    }

    func testChangedSleepStage_updatesMeasurement() {
        var stored = HealthSummary(date: day)
        stored.sleepStages = [SleepStage(start: day, end: day.addingTimeInterval(3600), stage: .deep)]
        var fetched = HealthSummary(date: day)
        fetched.sleepStages = [SleepStage(start: day, end: day.addingTimeInterval(3600), stage: .rem)]

        let merged = HealthSummaryMerging.merge(existing: [stored], incoming: [fetched])[0]
        XCTAssertEqual(merged.sleepStages[0].stage, .rem)
        XCTAssertFalse(HealthSummaryMerging.hasSameContent(stored, merged))
    }

    func testPersistedSleepStageDecode_ignoresRegeneratedIdentityOnly() throws {
        var stored = HealthSummary(date: day)
        stored.sleepStages = [SleepStage(start: day, end: day.addingTimeInterval(3600), stage: .core)]
        let restored = try JSONDecoder().decode(HealthSummary.self, from: JSONEncoder().encode(stored))

        XCTAssertTrue(HealthSummaryMerging.hasSameContent(stored, restored))
        var changed = restored
        changed.sleepStages[0].end = day.addingTimeInterval(7200)
        XCTAssertFalse(HealthSummaryMerging.hasSameContent(stored, changed))
    }

    func testDuplicateStoredDates_deduplicatesAndSortsWithoutTrapping() {
        let first = HealthSummary(date: day)
        let duplicate = HealthSummary(date: day)
        let later = HealthSummary(date: day.addingTimeInterval(86400))
        let result = HealthSummaryMerging.merge(existing: [first, duplicate], incoming: [later])

        XCTAssertEqual(result.map(\.id), [later.id, first.id])
    }

    func testRingGoalRefresh_updatesGoalsAndPreservesIdentity() {
        var stored = HealthSummary(date: day)
        stored.activeEnergyGoal = 450
        stored.exerciseMinutesGoal = 30
        stored.fitnessMoveMode = .energy
        var fetched = HealthSummary(date: day)
        fetched.activeEnergyGoal = 500
        fetched.exerciseMinutesGoal = 0
        fetched.fitnessMoveMode = .time
        fetched.moveMinutesGoal = 60

        let merged = HealthSummaryMerging.merge(existing: [stored], incoming: [fetched])[0]

        XCTAssertEqual(merged.id, stored.id)
        XCTAssertEqual(merged.activeEnergyGoal, 500)
        XCTAssertEqual(merged.exerciseMinutesGoal, 0)
        XCTAssertEqual(merged.fitnessMoveMode, .time)
        XCTAssertEqual(merged.moveMinutesGoal, 60)
    }

    func testRefreshedSleepWithoutStages_clearsObsoleteTimeline() {
        var stored = HealthSummary(date: day)
        stored.sleepHours = 7
        stored.sleepStages = [SleepStage(start: day, end: day.addingTimeInterval(3600), stage: .deep)]
        var fetched = HealthSummary(date: day)
        fetched.sleepHours = 6

        let merged = HealthSummaryMerging.merge(existing: [stored], incoming: [fetched])[0]

        XCTAssertEqual(merged.sleepHours, 6)
        XCTAssertTrue(merged.sleepStages.isEmpty)
    }
}
