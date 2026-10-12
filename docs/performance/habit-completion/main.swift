import Foundation
import CoreFoundation

struct HabitRecord {
    let habitID: UUID
    let date: Date
    let isCompleted: Bool
}

@inline(never)
func baselineStreak(habitID: UUID, upTo date: Date, records: [HabitRecord], calendar: Calendar) -> Int {
    var streak = 0
    var currentDate = calendar.startOfDay(for: date)
    while true {
        let isCompleted = records.contains {
            $0.habitID == habitID && calendar.isDate($0.date, inSameDayAs: currentDate) && $0.isCompleted
        }
        if isCompleted { streak += 1 } else { break }
        guard let previous = calendar.date(byAdding: .day, value: -1, to: currentDate) else { break }
        currentDate = previous
    }
    return streak
}

func medianMS(_ operation: () -> Int, expected: Int) -> Double {
    var times: [Double] = []
    for _ in 0..<3 {
        let start = CFAbsoluteTimeGetCurrent()
        let result = operation()
        times.append((CFAbsoluteTimeGetCurrent() - start) * 1_000)
        precondition(result == expected)
    }
    return times.sorted()[1]
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))!
let ids = (0..<20).map { _ in UUID() }
let dates = (0..<2_000).map { calendar.date(byAdding: .day, value: $0 - 1_999, to: day)! }
let records = ids.flatMap { id in dates.map { HabitRecord(habitID: id, date: $0, isCompleted: true) } }
let target = ids.last!
let oldMS = medianMS({ baselineStreak(habitID: target, upTo: day, records: records, calendar: calendar) }, expected: 2_000)
let newMS = medianMS({
    let completed = HabitCompletionQuery.completedDays(for: target, from: records, calendar: calendar)
    return HabitCompletionQuery.currentDailyStreak(upTo: day, completedDays: completed, calendar: calendar)
}, expected: 2_000)
print(String(format: "20 habits × 2,000 days, target last: streak baseline %.2f ms; fixed %.2f ms; %.1f×", oldMS, newMS, oldMS / newMS))
let oldAllMS = medianMS({
    ids.allSatisfy { id in
        records.contains { $0.habitID == id && calendar.isDate($0.date, inSameDayAs: day) && $0.isCompleted }
    } ? 1 : 0
}, expected: 1)
let newAllMS = medianMS({
    let completed = HabitCompletionQuery.completedHabitIDs(on: day, from: records, calendar: calendar)
    return ids.allSatisfy { completed.contains($0) } ? 1 : 0
}, expected: 1)
print(String(format: "All habits completion: baseline %.2f ms; fixed %.2f ms; %.1f×", oldAllMS, newAllMS, oldAllMS / newAllMS))
