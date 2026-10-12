import Foundation

/// Shared day indexes for Today, Calendar and habit history (docs/requirements.md).
/// Default subscripts mutate the nested dictionary in place. Copying it into a
/// local variable for every record copies an ever-growing history on each write.
enum HabitRecordIndex {
    static func latestRecordsByHabit(
        from records: [HabitRecord],
        calendar: Calendar = .current
    ) -> [UUID: [Date: HabitRecord]] {
        var result: [UUID: [Date: HabitRecord]] = [:]
        for record in records {
            result[record.habitID, default: [:]][calendar.startOfDay(for: record.date)] = record
        }
        return result
    }

    /// Today and Calendar historically use the first record for each habit/day.
    static func firstRecords(
        on date: Date,
        from records: [HabitRecord],
        calendar: Calendar = .current
    ) -> [UUID: HabitRecord] {
        let target = calendar.startOfDay(for: date)
        var result: [UUID: HabitRecord] = [:]
        for record in records where calendar.startOfDay(for: record.date) == target {
            if result[record.habitID] == nil {
                result[record.habitID] = record
            }
        }
        return result
    }
}
