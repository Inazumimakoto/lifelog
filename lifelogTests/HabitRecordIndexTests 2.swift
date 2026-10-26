import XCTest
@testable import lifelify

@MainActor
final class HabitRecordIndexTests: XCTestCase {
    func testDuplicateDay_preservesFirstForTodayAndLastForHabitHistory() throws {
        let habitID = UUID()
        let day = date(2026, 3, 8)
        let first = HabitRecord(habitID: habitID, date: day, isCompleted: false)
        let last = HabitRecord(habitID: habitID, date: day.addingTimeInterval(3_600), isCompleted: true)
        let records = [first, last]

        let today = HabitRecordIndex.firstRecords(on: day, from: records, calendar: calendar)
        let history = HabitRecordIndex.latestRecordsByHabit(from: records, calendar: calendar)

        XCTAssertEqual(today[habitID]?.id, first.id)
        XCTAssertEqual(history[habitID]?[day]?.id, last.id)
    }

    func testDaylightSavingBoundary_keepsRecordsInTheirLocalDays() {
        let habitID = UUID()
        let day = date(2026, 3, 8)
        let nextDay = date(2026, 3, 9)
        let records = [
            HabitRecord(habitID: habitID, date: nextDay.addingTimeInterval(-1), isCompleted: true),
            HabitRecord(habitID: habitID, date: nextDay, isCompleted: false)
        ]
        XCTAssertEqual(nextDay.timeIntervalSince(day), 23 * 3_600)
        XCTAssertEqual(HabitRecordIndex.firstRecords(on: day, from: records, calendar: calendar)[habitID]?.id,
                       records[0].id)
        XCTAssertEqual(HabitRecordIndex.firstRecords(on: nextDay, from: records, calendar: calendar)[habitID]?.id,
                       records[1].id)
        XCTAssertEqual(HabitRecordIndex.latestRecordsByHabit(from: records, calendar: calendar)[habitID]?.count, 2)
    }

    func testLongHistory_preservesEveryHabitAndDay() {
        let ids = (0..<10).map { _ in UUID() }
        let start = date(2020, 1, 1)
        let records = ids.flatMap { id in
            (0..<2_000).map { offset in
                HabitRecord(habitID: id,
                            date: calendar.date(byAdding: .day, value: offset, to: start)!,
                            isCompleted: offset.isMultiple(of: 2))
            }
        }
        let result = HabitRecordIndex.latestRecordsByHabit(from: records, calendar: calendar)
        XCTAssertEqual(result.count, ids.count)
        for id in ids {
            XCTAssertEqual(result[id]?.count, 2_000)
            XCTAssertEqual(result[id]?[start]?.isCompleted, true)
            let lastDay = calendar.date(byAdding: .day, value: 1_999, to: start)!
            XCTAssertEqual(result[id]?[lastDay]?.isCompleted, false)
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
