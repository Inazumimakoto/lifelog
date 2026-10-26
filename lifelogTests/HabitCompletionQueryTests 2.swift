import XCTest
@testable import lifelify

@MainActor
final class HabitCompletionQueryTests: XCTestCase {
    func testDuplicateRecords_countAnyCompletedRecordWithoutDependingOnOrder() {
        let habitID = UUID()
        let day = date(2026, 3, 9)
        let records = [
            HabitRecord(habitID: habitID, date: day, isCompleted: false),
            HabitRecord(habitID: habitID, date: day.addingTimeInterval(3_600), isCompleted: true),
            HabitRecord(habitID: habitID, date: day.addingTimeInterval(7_200), isCompleted: false)
        ]
        let days = HabitCompletionQuery.completedDays(for: habitID, from: records, calendar: calendar)
        XCTAssertEqual(days, Set([day]))
        XCTAssertEqual(HabitCompletionQuery.completedDays(for: habitID,
                                                          from: Array(records.reversed()),
                                                          calendar: calendar), days)
        XCTAssertEqual(HabitCompletionQuery.currentDailyStreak(upTo: day,
                                                              completedDays: days,
                                                              calendar: calendar), 1)
        XCTAssertEqual(HabitCompletionQuery.completedHabitIDs(on: day,
                                                             from: records,
                                                             calendar: calendar), Set([habitID]))
    }

    func testCompletionFeedback_countsConsecutiveDaysWithoutSkippingScheduleGaps() {
        let monday = date(2026, 3, 9)
        let wednesday = date(2026, 3, 11)
        XCTAssertEqual(HabitCompletionQuery.currentDailyStreak(upTo: wednesday,
                                                              completedDays: Set([monday, wednesday]),
                                                              calendar: calendar), 1)
        XCTAssertEqual(HabitCompletionQuery.currentDailyStreak(upTo: monday.addingTimeInterval(86_400),
                                                              completedDays: Set([monday, wednesday]),
                                                              calendar: calendar), 0)
    }

    func testDaylightSavingTransition_countsLocalDaysAndCompletionInsertionExtendsStreak() {
        let days = [date(2026, 3, 6), date(2026, 3, 7), date(2026, 3, 8), date(2026, 3, 9)]
        XCTAssertEqual(days[3].timeIntervalSince(days[2]), 23 * 3_600)
        var completed = Set(days.dropLast())
        XCTAssertEqual(HabitCompletionQuery.currentDailyStreak(upTo: days[3],
                                                              completedDays: completed,
                                                              calendar: calendar), 0)
        completed.insert(days[3])
        XCTAssertEqual(HabitCompletionQuery.currentDailyStreak(upTo: days[3],
                                                              completedDays: completed,
                                                              calendar: calendar), 4)
    }

    func testDailyCompletion_excludesBoundaryDaysAndIncompleteHabits() {
        let day = date(2026, 3, 8)
        let nextDay = date(2026, 3, 9)
        let first = UUID(), second = UUID(), previous = UUID(), future = UUID(), incomplete = UUID()
        let records = [
            HabitRecord(habitID: first, date: day, isCompleted: true),
            HabitRecord(habitID: second, date: nextDay.addingTimeInterval(-1), isCompleted: true),
            HabitRecord(habitID: previous, date: day.addingTimeInterval(-1), isCompleted: true),
            HabitRecord(habitID: future, date: nextDay, isCompleted: true),
            HabitRecord(habitID: incomplete, date: day, isCompleted: false)
        ]
        XCTAssertEqual(HabitCompletionQuery.completedHabitIDs(on: day,
                                                             from: records,
                                                             calendar: calendar), Set([first, second]))
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
