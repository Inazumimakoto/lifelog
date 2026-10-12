import Foundation

/// Completion feedback follows consecutive calendar days (§Habits), unlike
/// the schedule-aware streak shown by HabitsViewModel. Duplicate records count
/// as complete when any record is complete, preserving the original query.
enum HabitCompletionQuery {
    static func completedDays(
        for habitID: UUID,
        from records: [HabitRecord],
        calendar: Calendar = .current
    ) -> Set<Date> {
        var days = Set<Date>()
        for record in records where record.habitID == habitID && record.isCompleted {
            days.insert(calendar.startOfDay(for: record.date))
        }
        return days
    }

    static func currentDailyStreak(
        upTo date: Date,
        completedDays: Set<Date>,
        calendar: Calendar = .current
    ) -> Int {
        var day = calendar.startOfDay(for: date)
        var streak = 0
        while completedDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    static func completedHabitIDs(
        on date: Date,
        from records: [HabitRecord],
        calendar: Calendar = .current
    ) -> Set<UUID> {
        guard let interval = calendar.dateInterval(of: .day, for: date) else { return [] }
        var ids = Set<UUID>()
        for record in records where record.isCompleted &&
            record.date >= interval.start && record.date < interval.end {
            ids.insert(record.habitID)
        }
        return ids
    }
}
