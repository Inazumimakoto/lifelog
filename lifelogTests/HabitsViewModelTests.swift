import XCTest
@testable import lifelify

@MainActor
final class HabitsViewModelTests: XCTestCase {
    func testCustomScheduleWithoutDays_returnsZeroWithoutScanningForever() {
        let habit = Habit(title: "Imported", iconName: "star", colorHex: "#000000", schedule: .custom(days: []))
        XCTAssertEqual(HabitsViewModel.calculateCurrentStreak(for: habit,
                                                             asOf: Date(),
                                                             records: [:],
                                                             calendar: .current), 0)
    }

    func testScheduledGaps_preserveCurrentStreakUntilMissingScheduledDay() {
        let calendar = Calendar.current
        let monday = calendar.nextDate(after: Date(timeIntervalSince1970: 0),
                                       matching: DateComponents(weekday: 2),
                                       matchingPolicy: .nextTime)!
        let wednesday = calendar.date(byAdding: .day, value: 2, to: monday)!
        let habit = Habit(title: "Routine", iconName: "star", colorHex: "#000000",
                          schedule: .custom(days: [.monday, .wednesday]))
        let records = [monday, wednesday].map {
            HabitRecord(habitID: habit.id, date: $0, isCompleted: true)
        }
        let index = HabitRecordIndex.latestRecordsByHabit(from: records)
        XCTAssertEqual(HabitsViewModel.calculateCurrentStreak(for: habit,
                                                             asOf: wednesday,
                                                             records: index[habit.id]!,
                                                             calendar: calendar), 2)
    }
}
