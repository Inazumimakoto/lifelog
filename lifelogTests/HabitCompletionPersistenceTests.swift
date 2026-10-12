import XCTest
import SwiftData
@testable import lifelify

@MainActor
final class HabitCompletionPersistenceTests: XCTestCase {
    func testExplicitCompletionThenToggle_updatesSameStoredRecordAndBackdatesCreation() throws {
        let habit = makeHabit()
        let store = try makeStore(habit: habit)
        let completedAt = date(day: 4, hour: 12)
        store.setHabitCompletion(habit.id, on: completedAt, completed: true)
        let firstRecord = try XCTUnwrap(store.habitRecords.first)
        store.toggleHabit(habit.id, on: completedAt.addingTimeInterval(3_600))

        let stored = try persistedRecords(in: store)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].id, firstRecord.id)
        XCTAssertEqual(stored[0].date, completedAt)
        XCTAssertFalse(stored[0].isCompleted)
        let storedHabit = try XCTUnwrap(ModelContext(store.modelContext.container).fetch(FetchDescriptor<SDHabit>()).first)
        XCTAssertEqual(storedHabit.createdAt, date(day: 4, hour: 0))
        XCTAssertEqual(store.habits[0].createdAt, storedHabit.createdAt)
    }

    func testToggleNewCompletionThenExplicitClear_keepsIDAndOriginalRecordDate() throws {
        let habit = makeHabit()
        let store = try makeStore(habit: habit)
        let completedAt = date(day: 9, hour: 12)
        store.toggleHabit(habit.id, on: completedAt)
        let recordID = try XCTUnwrap(store.habitRecords.first?.id)
        store.setHabitCompletion(habit.id, on: completedAt.addingTimeInterval(3_600), completed: false)

        let stored = try persistedRecords(in: store)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].id, recordID)
        XCTAssertEqual(stored[0].date, completedAt)
        XCTAssertFalse(stored[0].isCompleted)
        XCTAssertEqual(store.habits[0].createdAt, habit.createdAt)
    }

    func testClearingMissingRecord_doesNotCreateRecordOrBackdateHabit() throws {
        let habit = makeHabit()
        let store = try makeStore(habit: habit)
        store.setHabitCompletion(habit.id, on: date(day: 1, hour: 12), completed: false)
        XCTAssertTrue(store.habitRecords.isEmpty)
        XCTAssertTrue(try persistedRecords(in: store).isEmpty)
        XCTAssertEqual(store.habits[0].createdAt, habit.createdAt)
    }

    func testDuplicateDay_updatesFirstRecordWithoutChangingOtherRecord() throws {
        let habit = makeHabit()
        let first = HabitRecord(habitID: habit.id, date: date(day: 4, hour: 12), isCompleted: false)
        let second = HabitRecord(habitID: habit.id, date: date(day: 4, hour: 13), isCompleted: true)
        let store = try makeStore(habit: habit, records: [first, second])
        // Fetch order is deliberately irrelevant: both entry points use this
        // existing first-for-day memory order even for legacy duplicate days.
        store.habitRecords = [first, second]
        store.toggleHabit(habit.id, on: date(day: 4, hour: 14))
        store.setHabitCompletion(habit.id, on: date(day: 4, hour: 15), completed: false)

        let stored = try persistedRecords(in: store)
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(stored.first { $0.id == first.id }?.isCompleted, false)
        XCTAssertEqual(stored.first { $0.id == second.id }, second)
    }

    private func makeStore(habit: Habit, records: [HabitRecord] = []) throws -> AppDataStore {
        let container = PersistenceController(inMemory: true).container
        container.mainContext.insert(SDHabit(domain: habit))
        for record in records { container.mainContext.insert(SDHabitRecord(domain: record)) }
        try container.mainContext.save()
        return AppDataStore(container: container, startsBackgroundServices: false)
    }

    private func persistedRecords(in store: AppDataStore) throws -> [HabitRecord] {
        try ModelContext(store.modelContext.container).fetch(FetchDescriptor<SDHabitRecord>()).map { HabitRecord(sd: $0) }
    }

    private func makeHabit() -> Habit {
        Habit(title: "Habit", iconName: "checkmark", colorHex: "#123456", schedule: .daily,
              createdAt: date(day: 8, hour: 12))
    }

    private func date(day: Int, hour: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2030, month: 3, day: day, hour: hour))!
    }
}
