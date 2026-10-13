import Foundation

/// Value snapshots keep the full habit projection off the UI actor.
/// The visible 53-week and per-habit heatmaps follow docs/requirements.md §4.6.
nonisolated struct HabitAggregateProjection: Sendable {
    nonisolated struct HabitSnapshot: Sendable {
        let id: UUID
        let createdDay: Date
        let archivedDay: Date?
        let isArchived: Bool
        let activeWeekdays: Set<Int>
        let completedDays: Set<Date>

        func isScheduled(on day: Date, calendar: Calendar) -> Bool {
            activeWeekdays.contains(calendar.component(.weekday, from: day))
        }
    }

    nonisolated struct DaySummary: Sendable {
        let scheduledIDs: [UUID]
        let completedIDs: [UUID]
    }

    nonisolated struct Streak: Sendable {
        let current: Int
        let best: Int
    }

    nonisolated struct Rate: Sendable {
        var total: Double = 0
        var count: Int = 0

        var average: Double { count == 0 ? 0 : total / Double(count) }
    }

    let yearStartDate: Date
    let yearlySummaries: [Date: DaySummary]
    let miniHeatmaps: [UUID: [HabitHeatCell]]
    let streaks: [UUID: Streak]
    let startOfYear: Date
    let startOfMonth: Date
    let yearlyRate: Rate
    let monthlyRate: Rate

    static func build(habits: [HabitSnapshot], today: Date, calendar: Calendar) -> Self {
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
        let yearStart = calendar.date(byAdding: .weekOfYear, value: -52, to: startOfWeek) ?? startOfWeek
        let miniStart = calendar.date(byAdding: .weekOfYear, value: -9, to: startOfWeek) ?? startOfWeek
        let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: today)) ?? today
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        var summaries: [Date: DaySummary] = [:]
        var yearlyRate = Rate()
        var monthlyRate = Rate()

        for offset in 0..<(53 * 7) {
            if _Concurrency.Task.isCancelled { break }
            guard let date = calendar.date(byAdding: .day, value: offset, to: yearStart) else { continue }
            let day = calendar.startOfDay(for: date)
            let scheduled = habits.filter {
                $0.createdDay <= day && ($0.archivedDay.map { day < $0 } ?? true) && $0.isScheduled(on: day, calendar: calendar)
            }
            let completed = scheduled.filter { $0.completedDays.contains(day) }
            summaries[day] = DaySummary(scheduledIDs: scheduled.map(\.id), completedIDs: completed.map(\.id))
            if !scheduled.isEmpty {
                let rate = Double(completed.count) / Double(scheduled.count)
                if day >= startOfYear {
                    yearlyRate.total += rate
                    yearlyRate.count += 1
                }
                if day >= startOfMonth {
                    monthlyRate.total += rate
                    monthlyRate.count += 1
                }
            }
        }

        var miniHeatmaps: [UUID: [HabitHeatCell]] = [:]
        var streaks: [UUID: Streak] = [:]
        for habit in habits where !habit.isArchived {
            if _Concurrency.Task.isCancelled { break }
            miniHeatmaps[habit.id] = (0..<(10 * 7)).compactMap { offset in
                guard let date = calendar.date(byAdding: .day, value: offset, to: miniStart) else { return nil }
                let day = calendar.startOfDay(for: date)
                let state: HabitHeatCell.State
                if day > today || !habit.isScheduled(on: day, calendar: calendar) {
                    state = .inactive
                } else {
                    state = habit.completedDays.contains(day) ? .completed : .pending
                }
                return HabitHeatCell(date: day, state: state, isToday: day == today)
            }
            streaks[habit.id] = streak(for: habit, asOf: today, calendar: calendar)
        }

        return Self(yearStartDate: yearStart, yearlySummaries: summaries,
                    miniHeatmaps: miniHeatmaps, streaks: streaks,
                    startOfYear: startOfYear, startOfMonth: startOfMonth,
                    yearlyRate: yearlyRate, monthlyRate: monthlyRate)
    }

    static func currentStreak(for habit: HabitSnapshot, asOf day: Date, calendar: Calendar) -> Int {
        guard !habit.activeWeekdays.isEmpty else { return 0 }
        var current = 0
        var cursor = day
        while true {
            if _Concurrency.Task.isCancelled { break }
            if habit.isScheduled(on: cursor, calendar: calendar) {
                guard habit.completedDays.contains(cursor) else { break }
                current += 1
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return current
    }

    static func streak(for habit: HabitSnapshot, asOf day: Date, calendar: Calendar) -> Streak {
        let current = currentStreak(for: habit, asOf: day, calendar: calendar)
        guard let start = calendar.date(byAdding: .day, value: -365, to: day) else {
            return Streak(current: current, best: current)
        }
        var cursor = start
        var best = 0
        var running = 0
        while cursor <= day {
            if _Concurrency.Task.isCancelled { break }
            if habit.isScheduled(on: cursor, calendar: calendar) {
                if habit.completedDays.contains(cursor) {
                    running += 1
                    best = max(best, running)
                } else {
                    running = 0
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return Streak(current: current, best: max(best, current))
    }
}
