import XCTest
@testable import lifelify

@MainActor
final class HabitScheduleMappingTests: XCTestCase {
    func testCreationAndUpdate_useSameFlattenedRepresentation() {
        let schedules: [HabitSchedule] = [.daily, .weekdays, .custom(days: [.friday, .monday, .friday]), .custom(days: [])]
        for schedule in schedules {
            let habit = makeHabit(schedule: schedule)
            let created = SDHabit(domain: habit)
            let updated = SDHabit(domain: makeHabit(schedule: .custom(days: [.sunday])))
            updated.update(from: habit)
            XCTAssertEqual(created.scheduleType, updated.scheduleType)
            XCTAssertEqual(created.scheduleDays, updated.scheduleDays)
            XCTAssertEqual(Habit(sd: created).schedule, schedule)
            XCTAssertEqual(Habit(sd: updated).schedule, schedule)
        }
    }

    func testUnknownStoredType_keepsAppFallbackAndWidgetInactivePolicy() {
        let stored = SDHabit(domain: makeHabit(schedule: .daily))
        stored.scheduleType = "unknown-future-type"
        XCTAssertEqual(Habit(sd: stored).schedule, .daily)
        XCTAssertFalse(stored.scheduleIsActive(on: Date(timeIntervalSince1970: 1_700_000_000)))
    }

    func testInvalidStoredWeekdays_areIgnoredWhileDuplicatesAndOrderAreRetained() {
        let stored = SDHabit(domain: makeHabit(schedule: .daily))
        stored.scheduleType = "custom"
        stored.scheduleDays = [6, 0, 2, 8, 6]
        XCTAssertEqual(Habit(sd: stored).schedule, .custom(days: [.friday, .monday, .friday]))
        for offset in 0..<7 {
            let day = Calendar.current.date(byAdding: .day, value: offset, to: Date(timeIntervalSince1970: 1_700_000_000))!
            XCTAssertEqual(stored.scheduleIsActive(on: day), Habit(sd: stored).schedule.isActive(on: day))
        }
    }

    private func makeHabit(schedule: HabitSchedule) -> Habit {
        Habit(title: "Habit", iconName: "checkmark", colorHex: "#123456", schedule: schedule)
    }
}
