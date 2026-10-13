import Foundation

// Standalone synthetic fixture; compile with the app's actual query/index files.
struct HabitRecord: Equatable {
    let id: UUID
    let habitID: UUID
    let date: Date
    var isCompleted: Bool

    init(habitID: UUID, date: Date, isCompleted: Bool) {
        self.id = UUID()
        self.habitID = habitID
        self.date = date
        self.isCompleted = isCompleted
    }
}

let calendar = Calendar.current
let today = calendar.startOfDay(for: Date())
let habitIDs = (0..<20).map { _ in UUID() }
var records = habitIDs.flatMap { id in
    (0..<2_000).map { offset in
        HabitRecord(habitID: id,
                    date: calendar.date(byAdding: .day, value: -offset, to: today)!,
                    isCompleted: offset.isMultiple(of: 2))
    }
}
let lookup = HabitRecordLookup(records: records, calendar: calendar)
let target = habitIDs.last!
precondition(lookup.firstRecords(on: today, from: records)
             == HabitRecordIndex.firstRecords(on: today, from: records, calendar: calendar))
precondition(lookup.completedHabitIDs(on: today)
             == HabitCompletionQuery.completedHabitIDs(on: today, from: records, calendar: calendar))

func medianMilliseconds(iterations: Int = 25, _ operation: () -> Int) -> Double {
    let durations = (0..<5).map { _ in
        let start = DispatchTime.now().uptimeNanoseconds
        var checksum = 0
        for _ in 0..<iterations { checksum += operation() }
        precondition(checksum > 0)
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000 / Double(iterations)
    }
    return durations.sorted()[2]
}

let oldToday = medianMilliseconds {
    HabitRecordIndex.firstRecords(on: today, from: records, calendar: calendar).count
}
let indexedToday = medianMilliseconds {
    lookup.firstRecords(on: today, from: records).count
}
let oldFeedback = medianMilliseconds {
    HabitCompletionQuery.completedDays(for: target, from: records, calendar: calendar).count
        + HabitCompletionQuery.completedHabitIDs(on: today, from: records, calendar: calendar).count
}
let indexedFeedback = medianMilliseconds {
    lookup.completedDays(for: target).count + lookup.completedHabitIDs(on: today).count
}

for _ in 0..<100 {
    let index = lookup.firstIndex(for: target, on: today)!
    let previous = records[index]
    records[index].isCompleted.toggle()
    lookup.updateCompletion(records[index], replacing: previous, at: index)
}
precondition(lookup.latestByHabit == HabitRecordIndex.latestRecordsByHabit(from: records, calendar: calendar))
precondition(lookup.completedDays(for: target)
             == HabitCompletionQuery.completedDays(for: target, from: records, calendar: calendar))
print("Synthetic input: 20 habits × 2,000 days = \(records.count) records; 5 samples × 25 queries, median per query")
print(String(format: "Today record lookup: scan %.4f ms, cached %.4f ms", oldToday, indexedToday))
print(String(format: "Completion feedback lookups: scan %.4f ms, cached %.4f ms", oldFeedback, indexedFeedback))
print("Query results and 100 incremental completion edits match full recomputation.")
