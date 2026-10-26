import HealthKit
import XCTest
@testable import lifelify

@MainActor
final class FitnessSummaryMappingTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_700_000_000)

    func testEnergyRings_keepActualTotalsAndGoals() {
        let activity = fixture()
        let summary = FitnessSummaryMapping.summary(from: activity, on: day)

        XCTAssertEqual(summary.date, day)
        XCTAssertEqual(summary.fitnessMoveMode, .energy)
        XCTAssertEqual(summary.activeEnergy, 420)
        XCTAssertEqual(summary.activeEnergyGoal, 450)
        XCTAssertEqual(summary.exerciseMinutes, 32)
        XCTAssertEqual(summary.exerciseMinutesGoal, 35)
        XCTAssertEqual(summary.standHours, 9)
        XCTAssertEqual(summary.standHoursGoal, 10)
    }

    func testMoveTimeMode_keepsMinutesWithoutEnergyConversion() {
        let activity = fixture()
        activity.activityMoveMode = .appleMoveTime
        activity.appleMoveTime = HKQuantity(unit: .minute(), doubleValue: 75)
        activity.appleMoveTimeGoal = HKQuantity(unit: .minute(), doubleValue: 60)

        let summary = FitnessSummaryMapping.summary(from: activity, on: day)

        XCTAssertEqual(summary.fitnessMoveMode, .time)
        XCTAssertEqual(summary.moveMinutes, 75)
        XCTAssertEqual(summary.moveMinutesGoal, 60)
        XCTAssertEqual(summary.activeEnergy, 420)
    }

    func testMissingGoals_keepsUnavailableInsteadOfFixedTargets() {
        let activity = fixture()
        activity.exerciseTimeGoal = nil
        activity.standHoursGoal = nil

        let summary = FitnessSummaryMapping.summary(from: activity, on: day)

        XCTAssertNil(summary.exerciseMinutesGoal)
        XCTAssertNil(summary.standHoursGoal)
    }

    func testPausedRings_clearAchievementGoalsButKeepMeasurements() {
        guard #available(iOS 18.0, *) else { return }
        let activity = fixture()
        activity.isPaused = true
        let summary = FitnessSummaryMapping.summary(from: activity, on: day)

        XCTAssertEqual(summary.activeEnergy, 420)
        XCTAssertEqual(summary.activeEnergyGoal, 0)
        XCTAssertEqual(summary.exerciseMinutesGoal, 0)
        XCTAssertEqual(summary.standHoursGoal, 0)
    }

    func testPersistenceRoundTrip_keepsHistoricalGoalsAndMoveMode() {
        let activity = fixture()
        activity.activityMoveMode = .appleMoveTime
        let summary = FitnessSummaryMapping.summary(from: activity, on: day)

        let stored = SDHealthSummary(domain: summary)
        let restored = HealthSummary(sd: stored)

        XCTAssertEqual(restored, summary)
        var updated = summary
        updated.activeEnergyGoal = 500
        updated.exerciseMinutesGoal = 40
        stored.update(from: updated)
        XCTAssertEqual(HealthSummary(sd: stored), updated)
    }

    func testLegacyJSON_decodesWithoutNewOptionalGoalFields() throws {
        let summary = HealthSummary(date: day)
        let encoded = try JSONEncoder().encode(summary)
        // Synthesized Codable omits nil optionals, matching the old cache.
        let restored = try JSONDecoder().decode(HealthSummary.self, from: encoded)

        XCTAssertNil(restored.fitnessMoveMode)
        XCTAssertNil(restored.activeEnergyGoal)
        XCTAssertNil(restored.exerciseMinutesGoal)
        XCTAssertEqual(restored.id, summary.id)
    }

    private func fixture() -> HKActivitySummary {
        let activity = HKActivitySummary()
        activity.activityMoveMode = .activeEnergy
        activity.activeEnergyBurned = HKQuantity(unit: .kilocalorie(), doubleValue: 420)
        activity.activeEnergyBurnedGoal = HKQuantity(unit: .kilocalorie(), doubleValue: 450)
        activity.appleMoveTime = HKQuantity(unit: .minute(), doubleValue: 48)
        activity.appleMoveTimeGoal = HKQuantity(unit: .minute(), doubleValue: 60)
        activity.appleExerciseTime = HKQuantity(unit: .minute(), doubleValue: 32)
        activity.exerciseTimeGoal = HKQuantity(unit: .minute(), doubleValue: 35)
        activity.appleStandHours = HKQuantity(unit: .count(), doubleValue: 9)
        activity.standHoursGoal = HKQuantity(unit: .count(), doubleValue: 10)
        return activity
    }
}
