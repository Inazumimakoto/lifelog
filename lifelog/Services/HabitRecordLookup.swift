import Foundation

/// Day/identity lookups shared by Home, Calendar and Habits (§4.1/4.6/§6).
/// Legacy duplicate days deliberately retain first, last and any-complete semantics.
final class HabitRecordLookup {
    private struct Key: Hashable {
        let habitID: UUID
        let day: Date
    }

    let calendar: Calendar
    private var firstIndicesByDay: [Date: [UUID: Int]] = [:]
    private var indicesByDay: [Date: [Int]] = [:]
    private var latestIndices: [Key: Int] = [:]
    private(set) var latestByHabit: [UUID: [Date: HabitRecord]] = [:]
    private var completionCounts: [Key: Int] = [:]
    private var completedDaysByHabit: [UUID: Set<Date>] = [:]
    private var completedIDsByDay: [Date: Set<UUID>] = [:]
    private var completedRecordCountsByHabit: [UUID: Int] = [:]
    private var completedRecordCountsByMonth: [UUID: [Date: Int]] = [:]

    init(records: [HabitRecord], calendar: Calendar = .current) {
        self.calendar = calendar
        for (index, record) in records.enumerated() {
            append(record, at: index)
        }
    }

    // Match AppDataStore's workaround for isolated teardown on iOS 26.1.
    nonisolated deinit {}

    func firstIndex(for habitID: UUID, on date: Date) -> Int? {
        firstIndicesByDay[calendar.startOfDay(for: date)]?[habitID]
    }

    func firstRecords(on date: Date, from records: [HabitRecord]) -> [UUID: HabitRecord] {
        (firstIndicesByDay[calendar.startOfDay(for: date)] ?? [:]).mapValues { records[$0] }
    }

    func records(on date: Date, from records: [HabitRecord]) -> [HabitRecord] {
        (indicesByDay[calendar.startOfDay(for: date)] ?? []).map { records[$0] }
    }

    func completedDays(for habitID: UUID) -> Set<Date> {
        completedDaysByHabit[habitID] ?? []
    }

    func completedHabitIDs(on date: Date) -> Set<UUID> {
        completedIDsByDay[calendar.startOfDay(for: date)] ?? []
    }

    func completionCount(for habitID: UUID) -> Int {
        completedRecordCountsByHabit[habitID] ?? 0
    }

    func completionCount(for habitID: UUID, in month: Date) -> Int {
        guard let start = calendar.dateInterval(of: .month, for: month)?.start else { return 0 }
        return completedRecordCountsByMonth[habitID]?[start] ?? 0
    }

    func append(_ record: HabitRecord, at index: Int) {
        let day = calendar.startOfDay(for: record.date)
        let key = Key(habitID: record.habitID, day: day)
        if firstIndicesByDay[day]?[record.habitID] == nil {
            firstIndicesByDay[day, default: [:]][record.habitID] = index
        }
        indicesByDay[day, default: []].append(index)
        latestIndices[key] = index
        latestByHabit[record.habitID, default: [:]][day] = record
        if record.isCompleted { updateCompletionCount(for: key, by: 1) }
    }

    /// Completion edits keep the record's ID, habit and original timestamp.
    func updateCompletion(_ record: HabitRecord, replacing previous: HabitRecord, at index: Int) {
        let key = Key(habitID: record.habitID, day: calendar.startOfDay(for: record.date))
        if latestIndices[key] == index {
            latestByHabit[record.habitID, default: [:]][key.day] = record
        }
        if record.isCompleted != previous.isCompleted {
            updateCompletionCount(for: key, by: record.isCompleted ? 1 : -1)
        }
    }

    private func updateCompletionCount(for key: Key, by delta: Int) {
        completedRecordCountsByHabit[key.habitID, default: 0] += delta
        if let month = calendar.dateInterval(of: .month, for: key.day)?.start {
            completedRecordCountsByMonth[key.habitID, default: [:]][month, default: 0] += delta
        }
        let count = (completionCounts[key] ?? 0) + delta
        if count > 0 {
            completionCounts[key] = count
            completedDaysByHabit[key.habitID, default: []].insert(key.day)
            completedIDsByDay[key.day, default: []].insert(key.habitID)
        } else {
            completionCounts.removeValue(forKey: key)
            completedDaysByHabit[key.habitID]?.remove(key.day)
            completedIDsByDay[key.day]?.remove(key.habitID)
        }
    }
}
