import Foundation
import HealthKit

extension HealthKitManager {
    /// §4.8: Read the actual ring totals and goals for each historical day.
    func fetchFitnessData(from start: Date, to endExclusive: Date) async -> [HealthSummary] {
        // Activity-summary predicates require Gregorian date components, even
        // when the user's preferred calendar is Japanese or Buddhist.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let lastDay = calendar.date(byAdding: .day, value: -1, to: endExclusive) else { return [] }
        let components: Set<Calendar.Component> = [.calendar, .timeZone, .era, .year, .month, .day]
        let predicate = HKQuery.predicate(
            forActivitySummariesBetweenStart: calendar.dateComponents(components, from: start),
            end: calendar.dateComponents(components, from: lastDay)
        )
        let activities: [HKActivitySummary] = await withCheckedContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, results, error in
                guard error == nil else {
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: results ?? [])
            }
            healthStore.execute(query)
        }
        return activities.compactMap { FitnessSummaryMapping.summary(from: $0, calendar: calendar) }
            .filter { $0.date >= start && $0.date < endExclusive }
    }
}

enum FitnessSummaryMapping {
    static func summary(from activity: HKActivitySummary, calendar: Calendar) -> HealthSummary? {
        guard let date = calendar.date(from: activity.dateComponents(for: calendar)) else { return nil }
        return summary(from: activity, on: calendar.startOfDay(for: date))
    }

    static func summary(from activity: HKActivitySummary, on day: Date) -> HealthSummary {
        var summary = HealthSummary(date: day)
        summary.fitnessMoveMode = activity.activityMoveMode == .appleMoveTime ? .time : .energy
        summary.activeEnergy = activity.activeEnergyBurned.doubleValue(for: .kilocalorie())
        summary.moveMinutes = activity.appleMoveTime.doubleValue(for: .minute())
        summary.exerciseMinutes = activity.appleExerciseTime.doubleValue(for: .minute())
        summary.standHours = activity.appleStandHours.doubleValue(for: .count())

        var paused = false
        if #available(iOS 18.0, *) { paused = activity.isPaused }
        // Zero means no active goal, including paused rings. It also replaces
        // cached goals without presenting a fabricated achievement ratio.
        summary.activeEnergyGoal = paused ? 0 : activity.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
        summary.moveMinutesGoal = paused ? 0 : activity.appleMoveTimeGoal.doubleValue(for: .minute())
        summary.exerciseMinutesGoal = paused ? 0 : activity.exerciseTimeGoal?.doubleValue(for: .minute())
        summary.standHoursGoal = paused ? 0 : activity.standHoursGoal?.doubleValue(for: .count())
        return summary
    }
}
