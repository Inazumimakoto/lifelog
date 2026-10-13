import Combine
import XCTest
@testable import lifelify

@MainActor
final class HabitRecordLookupTests: XCTestCase {
    func testDuplicateDayEdit_preservesFirstLastAndAnyCompletedSemantics() {
        let day = calendar.startOfDay(for: Date())
        let habitID = UUID()
        var records = [
            HabitRecord(habitID: habitID, date: day, isCompleted: false),
            HabitRecord(habitID: habitID, date: day.addingTimeInterval(3_600), isCompleted: true)
        ]
        let lookup = HabitRecordLookup(records: records, calendar: calendar)
        let previous = records[0]
        records[0].isCompleted = true
        lookup.updateCompletion(records[0], replacing: previous, at: 0)

        XCTAssertEqual(lookup.firstRecords(on: day, from: records)[habitID], records[0])
        XCTAssertEqual(lookup.latestByHabit[habitID]?[day], records[1])
        XCTAssertEqual(lookup.completedDays(for: habitID), [day])
        XCTAssertEqual(lookup.completionCount(for: habitID), 2)
        XCTAssertEqual(lookup.completionCount(for: habitID, in: day), 2)
        let completedFirst = records[0]
        records[0].isCompleted = false
        lookup.updateCompletion(records[0], replacing: completedFirst, at: 0)
        XCTAssertEqual(lookup.completedHabitIDs(on: day), [habitID])
        XCTAssertEqual(lookup.completionCount(for: habitID), 1)
        XCTAssertEqual(lookup.completionCount(for: habitID, in: day), 1)
        let completedLast = records[1]
        records[1].isCompleted = false
        lookup.updateCompletion(records[1], replacing: completedLast, at: 1)
        XCTAssertTrue(lookup.completedDays(for: habitID).isEmpty)
        XCTAssertTrue(lookup.completedHabitIDs(on: day).isEmpty)
        XCTAssertEqual(lookup.completionCount(for: habitID), 0)
        XCTAssertEqual(lookup.records(on: day, from: records), records)
    }

    func testDaylightSavingAppend_keepsLocalDayAndRecordOrder() {
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        let habitID = UUID()
        var records = [HabitRecord(habitID: habitID, date: nextDay.addingTimeInterval(-1), isCompleted: true)]
        let lookup = HabitRecordLookup(records: records, calendar: calendar)
        records.append(HabitRecord(habitID: habitID, date: nextDay, isCompleted: false))
        lookup.append(records[1], at: 1)

        XCTAssertEqual(nextDay.timeIntervalSince(day), 23 * 3_600)
        XCTAssertEqual(lookup.records(on: day, from: records), [records[0]])
        XCTAssertEqual(lookup.records(on: nextDay, from: records), [records[1]])
        XCTAssertEqual(lookup.completedDays(for: habitID), [day])
        XCTAssertEqual(lookup.firstIndex(for: habitID, on: nextDay), 1)
    }

    func testStoreReplacementAndElementEdit_rebuildLookupAndPublishResetAfterAssignment() {
        let store = PerformanceTestStore.make()
        let day = Calendar.current.startOfDay(for: Date())
        let original = HabitRecord(habitID: UUID(), date: day, isCompleted: false)
        store.habitRecords = [original]
        XCTAssertEqual(store.firstHabitRecord(for: original.habitID, on: day), original)
        let replacement = HabitRecord(habitID: UUID(), date: day, isCompleted: true)
        var snapshots: [[HabitRecord]] = []
        let subscription = store.habitRecordChanges.sink { change in
            if case .reset = change { snapshots.append(store.records(for: day)) }
        }

        store.habitRecords = [replacement]
        store.habitRecords[0].isCompleted = false

        XCTAssertNil(store.firstHabitRecord(for: original.habitID, on: day))
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[0], [replacement])
        XCTAssertFalse(snapshots[1][0].isCompleted)
        XCTAssertFalse(store.latestHabitRecords(for: replacement.habitID)[day]!.isCompleted)
        withExtendedLifetime(subscription) {}
    }

    func testNoOpCompletion_doesNotPublishOrInvalidateLookup() {
        let store = PerformanceTestStore.make()
        let habit = Habit(title: "Habit", iconName: "star", colorHex: "#000000", schedule: .daily)
        let day = Calendar.current.startOfDay(for: Date())
        store.habits = [habit]
        store.setHabitCompletion(habit.id, on: day, completed: true)
        let lookup = store.habitRecordLookup
        var changes = 0
        let subscription = store.habitRecordChanges.sink { _ in changes += 1 }

        store.setHabitCompletion(habit.id, on: day, completed: true)
        store.setHabitCompletion(habit.id, on: day.addingTimeInterval(86_400), completed: false)

        XCTAssertEqual(changes, 0)
        XCTAssertTrue(store.habitRecordLookup === lookup)
        withExtendedLifetime(subscription) {}
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }
}
