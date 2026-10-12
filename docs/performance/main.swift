// Reproduce algorithm timings on macOS without accessing an app/user store:
// swiftc -O docs/performance/main.swift lifelog/ViewModels/HabitRecordIndex.swift -o /tmp/lifelog-perf
// /tmp/lifelog-perf
import Foundation
import CoreFoundation

struct HabitRecord: Equatable {
    let id = UUID()
    let habitID: UUID
    let date: Date
    let isCompleted: Bool
}

@inline(never)
func oldHabitIndex(_ records: [HabitRecord], calendar: Calendar) -> [UUID: [Date: HabitRecord]] {
    records.reduce(into: [UUID: [Date: HabitRecord]]()) { result, record in
        var habitMap = result[record.habitID] ?? [:]
        habitMap[calendar.startOfDay(for: record.date)] = record
        result[record.habitID] = habitMap
    }
}

func elapsed<T>(_ operation: () -> T) -> (Double, T) {
    let start = CFAbsoluteTimeGetCurrent()
    let result = operation()
    return ((CFAbsoluteTimeGetCurrent() - start) * 1_000, result)
}

func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

let calendar = Calendar(identifier: .gregorian)
let start = Date(timeIntervalSince1970: 1_000_000_000)
for (habitCount, days) in [(1, 2_000), (20, 2_000), (1, 10_000)] {
    let records = (0..<habitCount).flatMap { _ in
        let id = UUID()
        return (0..<days).map { day in
            HabitRecord(habitID: id, date: start.addingTimeInterval(Double(day) * 86_400), isCompleted: true)
        }
    }
    var oldTimes: [Double] = []
    var newTimes: [Double] = []
    for _ in 0..<5 {
        let (oldMS, oldResult) = elapsed { oldHabitIndex(records, calendar: calendar) }
        let (newMS, newResult) = elapsed { HabitRecordIndex.latestRecordsByHabit(from: records, calendar: calendar) }
        precondition(oldResult == newResult)
        oldTimes.append(oldMS)
        newTimes.append(newMS)
    }
    print(String(format: "%d habits x %d days median of 5: %.2f -> %.2f ms (%.1fx)",
                 habitCount, days, median(oldTimes), median(newTimes), median(oldTimes) / median(newTimes)))
}

let dates = (0..<1_000).map { start.addingTimeInterval(Double($0) * 86_400) }
let cachedFormatter = DateFormatter()
cachedFormatter.locale = .autoupdatingCurrent
cachedFormatter.setLocalizedDateFormatFromTemplate("MdEEE")
var oldFormatTimes: [Double] = []
var newFormatTimes: [Double] = []
for _ in 0..<5 {
    let (oldMS, oldStrings) = elapsed {
        dates.map { date in
            let formatter = DateFormatter()
            formatter.locale = .autoupdatingCurrent
            formatter.setLocalizedDateFormatFromTemplate("MdEEE")
            return formatter.string(from: date)
        }
    }
    let (newMS, newStrings) = elapsed { dates.map { cachedFormatter.string(from: $0) } }
    precondition(oldStrings == newStrings)
    oldFormatTimes.append(oldMS)
    newFormatTimes.append(newMS)
}
print(String(format: "1,000 date labels median of 5: %.2f -> %.2f ms (%.1fx)",
             median(oldFormatTimes), median(newFormatTimes), median(oldFormatTimes) / median(newFormatTimes)))
