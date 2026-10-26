import Foundation

enum HealthSummaryMerging {
    /// Preserve stored identity and weather when HealthKit refreshes a day.
    /// Equal refreshes can then skip publishing and SwiftData writes (§6).
    static func merge(existing: [HealthSummary], incoming: [HealthSummary]) -> [HealthSummary] {
        var byDate: [Date: HealthSummary] = [:]
        for summary in existing where byDate[summary.date] == nil {
            byDate[summary.date] = summary
        }
        for summary in incoming {
            guard var stored = byDate[summary.date] else {
                byDate[summary.date] = summary
                continue
            }
            stored.steps = summary.steps ?? stored.steps
            stored.sleepHours = summary.sleepHours ?? stored.sleepHours
            stored.sleepStart = summary.sleepStart ?? stored.sleepStart
            stored.sleepEnd = summary.sleepEnd ?? stored.sleepEnd
            stored.activeEnergy = summary.activeEnergy ?? stored.activeEnergy
            stored.moveMinutes = summary.moveMinutes ?? stored.moveMinutes
            stored.exerciseMinutes = summary.exerciseMinutes ?? stored.exerciseMinutes
            stored.standHours = summary.standHours ?? stored.standHours
            stored.activeEnergyGoal = summary.activeEnergyGoal ?? stored.activeEnergyGoal
            stored.moveMinutesGoal = summary.moveMinutesGoal ?? stored.moveMinutesGoal
            stored.exerciseMinutesGoal = summary.exerciseMinutesGoal ?? stored.exerciseMinutesGoal
            stored.standHoursGoal = summary.standHoursGoal ?? stored.standHoursGoal
            stored.fitnessMoveMode = summary.fitnessMoveMode ?? stored.fitnessMoveMode
            // A refreshed sleep measurement may now have no stages. Do not
            // leave an obsolete stage timeline attached to the new duration.
            if (summary.sleepHours != nil || !summary.sleepStages.isEmpty) && !sameStages(stored.sleepStages, summary.sleepStages) {
                stored.sleepStages = summary.sleepStages
            }
            stored.weatherCondition = summary.weatherCondition ?? stored.weatherCondition
            stored.highTemperature = summary.highTemperature ?? stored.highTemperature
            stored.lowTemperature = summary.lowTemperature ?? stored.lowTemperature
            byDate[summary.date] = stored
        }
        return byDate.values.sorted { $0.date > $1.date }
    }

    // HealthKit refreshes can create fresh SleepStage UUIDs. Those generated
    // identities are not a changed sleep measurement and must not force writes.
    static func hasSameContent(_ lhs: HealthSummary, _ rhs: HealthSummary) -> Bool {
        guard sameStages(lhs.sleepStages, rhs.sleepStages) else { return false }
        var comparable = rhs
        comparable.sleepStages = lhs.sleepStages
        return lhs == comparable
    }

    private static func sameStages(_ lhs: [SleepStage], _ rhs: [SleepStage]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
            $0.start == $1.start && $0.end == $1.end && $0.stage == $1.stage
        }
    }
}
