import Combine
import XCTest
@testable import lifelify

@MainActor
final class JournalViewModelTests: XCTestCase {
    func testHabitMetadataChange_invalidatesCachedDetail() async {
        let store = PerformanceTestStore.make()
        let day = Calendar.current.startOfDay(for: Date())
        store.habits = [Habit(title: "Before", iconName: "star", colorHex: "#000000", schedule: .daily)]
        let viewModel = JournalViewModel(store: store, anchorDate: day)
        XCTAssertEqual(viewModel.calendarDetailSnapshot(for: day).habitStatuses.first?.habit.title, "Before")
        let updated = expectation(description: "Habit invalidates detail")
        let subscription = viewModel.$dataRevision.dropFirst().sink { _ in updated.fulfill() }

        store.habits[0].title = "After"
        await fulfillment(of: [updated], timeout: 2)

        XCTAssertEqual(viewModel.calendarDetailSnapshot(for: day).habitStatuses.first?.habit.title, "After")
        withExtendedLifetime(subscription) {}
    }

    func testHealthChange_invalidatesCachedDetailAndRetainsTimelineIdentity() async {
        let day = Calendar.current.startOfDay(for: Date())
        var health = HealthSummary(date: day)
        health.sleepStages = [SleepStage(start: day, end: day.addingTimeInterval(6 * 3_600), stage: .deep)]
        let store = PerformanceTestStore.make(health: [health])
        let viewModel = JournalViewModel(store: store, anchorDate: day)
        XCTAssertNil(viewModel.calendarDetailSnapshot(for: day).healthSummary?.weatherCondition)
        let originalTimeline = viewModel.timelineItems(for: day)
        XCTAssertEqual(originalTimeline.count, 1)
        let updated = expectation(description: "Health invalidates detail")
        let subscription = viewModel.$dataRevision.dropFirst().sink { _ in updated.fulfill() }

        store.updateWeather(for: day, condition: "Clear", high: 25, low: 15)
        await fulfillment(of: [updated], timeout: 2)

        XCTAssertEqual(viewModel.calendarDetailSnapshot(for: day).healthSummary?.weatherCondition, "Clear")
        XCTAssertEqual(viewModel.timelineItems(for: day), originalTimeline)
        withExtendedLifetime(subscription) {}
    }

    func testUnrelatedMemoChange_doesNotInvalidateCalendar() async {
        let store = PerformanceTestStore.make()
        let viewModel = JournalViewModel(store: store)
        _ = viewModel.calendarDetailSnapshot(for: Date())
        _ = viewModel.timelineItems(for: Date())
        var publications = 0
        let subscription = viewModel.objectWillChange.sink { publications += 1 }
        store.memoPad = MemoPad(text: "Memo edit")
        await nextMainQueueTurn()
        await nextMainQueueTurn()

        XCTAssertEqual(viewModel.dataRevision, 0)
        XCTAssertEqual(publications, 0)
        withExtendedLifetime(subscription) {}
    }

    func testHabitCompletion_updatesOverlappingMonthCachesAndRetainsUnrelatedCaches() async throws {
        let day = date(month: 3, day: 1)
        let neighborDay = date(month: 3, day: 2)
        let habit = makeHabit(title: "First")
        let otherHabit = makeHabit(title: "Second")
        let first = HabitRecord(habitID: habit.id, date: day, isCompleted: false)
        let duplicate = HabitRecord(habitID: habit.id, date: day.addingTimeInterval(3_600), isCompleted: true)
        let other = HabitRecord(habitID: otherHabit.id, date: day, isCompleted: true)
        var health = HealthSummary(date: day)
        health.steps = 1_000
        health.sleepStages = [SleepStage(start: day, end: day.addingTimeInterval(6 * 3_600), stage: .deep)]
        let store = PerformanceTestStore.make(health: [health])
        store.habits = [habit, otherHabit]
        store.habitRecords = [first, duplicate, other]
        store.tasks = [Task(title: "Task", endDate: day), Task(title: "Neighbor task", endDate: neighborDay)]
        store.calendarEvents = [CalendarEvent(title: "Event", startDate: day.addingTimeInterval(9 * 3_600),
                                             endDate: day.addingTimeInterval(10 * 3_600), calendarName: "Calendar")]
        store.diaryEntries = [DiaryEntry(date: day, text: "Diary")]
        let viewModel = JournalViewModel(store: store, anchorDate: day, weekStart: .sunday)
        viewModel.preloadMonths(around: day)
        let unrelatedMonth = date(month: 7, day: 1)
        let unrelatedDays = viewModel.calendarDays(for: unrelatedMonth)
        let originalDays = viewModel.days
        let originalDetail = viewModel.calendarDetailSnapshot(for: day)
        let originalNeighbor = viewModel.calendarDetailSnapshot(for: neighborDay)
        _ = viewModel.timelineItems(for: day)
        _ = viewModel.timelineItems(for: neighborDay)
        let originalMonths: [Date: [JournalViewModel.CalendarDay]] = try cached("monthCache", in: viewModel)
        let originalTimeline: [Date: [JournalViewModel.TimelineItem]] = try cached("timelineItemsCache", in: viewModel)
        let originalTasks: [Date: [Task]] = try cached("tasksByDayCache", in: viewModel)
        XCTAssertFalse(originalDetail.habitStatuses[0].isCompleted)
        let originalRecord = try XCTUnwrap(originalDetail.habitStatuses[0].record)

        store.toggleHabit(habit.id, on: day.addingTimeInterval(2 * 3_600))
        store.setHabitCompletion(habit.id, on: day, completed: false)
        await nextMainQueueTurn()
        await nextMainQueueTurn()

        let updatedMonths: [Date: [JournalViewModel.CalendarDay]] = try cached("monthCache", in: viewModel)
        XCTAssertEqual(Set(updatedMonths.keys), Set(originalMonths.keys))
        XCTAssertGreaterThan(originalMonths.values.filter { $0.contains { $0.date == day } }.count, 1)
        for (month, originalMonthDays) in originalMonths {
            let updatedMonth = try XCTUnwrap(updatedMonths[month])
            for (original, updated) in zip(originalMonthDays, updatedMonth) {
                if original.date == day {
                    XCTAssertEqual(updated.habits, store.records(for: day))
                    XCTAssertEqual(updated.tasks, original.tasks)
                    XCTAssertEqual(updated.events, original.events)
                    XCTAssertEqual(updated.diary, original.diary)
                } else {
                    XCTAssertEqual(updated, original)
                }
            }
        }
        XCTAssertEqual(viewModel.calendarDays(for: unrelatedMonth), unrelatedDays)
        XCTAssertEqual(viewModel.days, originalDays)
        let updatedDetail = viewModel.calendarDetailSnapshot(for: day)
        XCTAssertFalse(updatedDetail.habitStatuses[0].isCompleted)
        XCTAssertEqual(updatedDetail.habitStatuses[0].record?.id, originalRecord.id)
        // Calendar dots keep all legacy records; detail uses the first record.
        XCTAssertEqual(viewModel.habits(on: day).filter(\.isCompleted).count, 2)
        XCTAssertEqual(updatedDetail.habitStatuses[1], originalDetail.habitStatuses[1])
        XCTAssertEqual(updatedDetail.events, originalDetail.events)
        XCTAssertEqual(updatedDetail.pendingTasks, originalDetail.pendingTasks)
        XCTAssertEqual(updatedDetail.completedTasks, originalDetail.completedTasks)
        XCTAssertEqual(updatedDetail.healthSummary, originalDetail.healthSummary)
        XCTAssertEqual(updatedDetail.diaryEntry, originalDetail.diaryEntry)
        XCTAssertEqual(viewModel.calendarDetailSnapshot(for: neighborDay).habitStatuses, originalNeighbor.habitStatuses)
        let updatedTimeline: [Date: [JournalViewModel.TimelineItem]] = try cached("timelineItemsCache", in: viewModel)
        let updatedTasks: [Date: [Task]] = try cached("tasksByDayCache", in: viewModel)
        XCTAssertEqual(updatedTimeline, originalTimeline)
        XCTAssertEqual(updatedTasks, originalTasks)
        XCTAssertEqual(viewModel.dataRevision, 2)
    }

    func testRapidHabitChecks_updatesEveryAffectedDateAndHabit() async {
        let day = date(month: 3, day: 10)
        let nextDay = date(month: 3, day: 11)
        let habit = makeHabit(title: "First")
        let otherHabit = makeHabit(title: "Second")
        let store = PerformanceTestStore.make()
        store.habits = [habit, otherHabit]
        let viewModel = JournalViewModel(store: store, anchorDate: day)
        _ = viewModel.calendarDetailSnapshot(for: day)
        _ = viewModel.calendarDetailSnapshot(for: nextDay)

        store.toggleHabit(habit.id, on: day)
        store.toggleHabit(otherHabit.id, on: nextDay)
        store.toggleHabit(habit.id, on: day)
        store.setHabitCompletion(habit.id, on: nextDay, completed: true)
        await nextMainQueueTurn()
        await nextMainQueueTurn()

        XCTAssertEqual(viewModel.calendarDetailSnapshot(for: day).habitStatuses.map(\.isCompleted), [false, false])
        XCTAssertEqual(viewModel.calendarDetailSnapshot(for: nextDay).habitStatuses.map(\.isCompleted), [true, true])
        XCTAssertEqual(viewModel.days.first { $0.date == day }?.habits, store.records(for: day))
        XCTAssertEqual(viewModel.days.first { $0.date == nextDay }?.habits, store.records(for: nextDay))
        XCTAssertEqual(viewModel.dataRevision, 4)
    }

    func testHabitCheckOutsideDisplayedMonth_updatesCachedMonthWithoutPublishingDays() async {
        let day = date(month: 3, day: 10)
        let distantDay = date(month: 7, day: 10)
        let habit = makeHabit(title: "Habit")
        let store = PerformanceTestStore.make()
        store.habits = [habit]
        let viewModel = JournalViewModel(store: store, anchorDate: day)
        let originalDays = viewModel.days
        _ = viewModel.calendarDays(for: distantDay)
        _ = viewModel.calendarDetailSnapshot(for: distantDay)
        var dayPublications = 0
        let subscription = viewModel.$days.dropFirst().sink { _ in dayPublications += 1 }

        store.setHabitCompletion(habit.id, on: distantDay, completed: true)
        await nextMainQueueTurn()
        await nextMainQueueTurn()

        XCTAssertEqual(dayPublications, 0)
        XCTAssertEqual(viewModel.days, originalDays)
        XCTAssertEqual(viewModel.selectedDate, day)
        XCTAssertEqual(viewModel.dataRevision, 1)
        XCTAssertEqual(viewModel.calendarDays(for: distantDay).first { $0.date == distantDay }?.habits,
                       store.records(for: distantDay))
        XCTAssertTrue(viewModel.calendarDetailSnapshot(for: distantDay).habitStatuses[0].isCompleted)
        withExtendedLifetime(subscription) {}
    }

    func testRecordReplacementThenCompletion_refreshesCurrentValuesAndRetainsSelection() async {
        let day = date(month: 3, day: 10)
        let otherDay = date(month: 3, day: 11)
        let habit = makeHabit(title: "Habit")
        let store = PerformanceTestStore.make()
        store.habits = [habit]
        let viewModel = JournalViewModel(store: store, anchorDate: day)
        viewModel.preloadMonths(around: day)
        _ = viewModel.calendarDetailSnapshot(for: day)
        _ = viewModel.calendarDetailSnapshot(for: otherDay)
        viewModel.selectedDate = date(month: 1, day: 20)
        let selectedDate = viewModel.selectedDate

        store.habitRecords = [HabitRecord(habitID: habit.id, date: day, isCompleted: true)]
        store.setHabitCompletion(habit.id, on: day, completed: false)
        store.setHabitCompletion(habit.id, on: otherDay, completed: true)
        store.habits[0].title = "Changed"
        await nextMainQueueTurn()
        await nextMainQueueTurn()

        XCTAssertEqual(viewModel.selectedDate, selectedDate)
        XCTAssertFalse(viewModel.calendarDetailSnapshot(for: day).habitStatuses[0].isCompleted)
        XCTAssertTrue(viewModel.calendarDetailSnapshot(for: otherDay).habitStatuses[0].isCompleted)
        XCTAssertEqual(viewModel.calendarDetailSnapshot(for: day).habitStatuses[0].habit.title, "Changed")
        XCTAssertEqual(viewModel.days.first { $0.date == day }?.habits, store.records(for: day))
        XCTAssertEqual(viewModel.days.first { $0.date == otherDay }?.habits, store.records(for: otherDay))
    }

    func testSelectedDetailEvictedFromCache_completionStillPublishesRevision() async throws {
        let anchor = date(month: 3, day: 10)
        let selected = date(month: 7, day: 10)
        let habit = makeHabit(title: "Habit")
        let store = PerformanceTestStore.make()
        store.habits = [habit]
        let viewModel = JournalViewModel(store: store, anchorDate: anchor)
        viewModel.selectedDate = selected
        let heldSnapshot = viewModel.calendarDetailSnapshot(for: selected)
        for offset in 100..<165 {
            let distantDay = Calendar.current.date(byAdding: .day, value: offset, to: selected)!
            _ = viewModel.calendarDetailSnapshot(for: distantDay)
        }
        let detailCache: [Date: CalendarDetailSnapshot] = try cached("detailSnapshotCache", in: viewModel)
        XCTAssertNil(detailCache[selected])
        XCTAssertFalse(heldSnapshot.habitStatuses[0].isCompleted)
        XCTAssertFalse(viewModel.days.contains { $0.date == selected })
        var revisionPublications = 0
        let subscription = viewModel.$dataRevision.dropFirst().sink { _ in revisionPublications += 1 }

        store.setHabitCompletion(habit.id, on: selected, completed: true)
        await nextMainQueueTurn()
        await nextMainQueueTurn()

        XCTAssertEqual(revisionPublications, 1)
        XCTAssertEqual(viewModel.dataRevision, 1)
        XCTAssertEqual(viewModel.selectedDate, selected)
        XCTAssertTrue(viewModel.calendarDetailSnapshot(for: selected).habitStatuses[0].isCompleted)
        withExtendedLifetime(subscription) {}
    }

    func testInjectedTimeZone_calendarGridKeepsItsDayGroupingAfterCompletion() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: Calendar.current.timeZone.secondsFromGMT() == 0 ? 9 * 3_600 : 0)!
        let day = calendar.date(from: DateComponents(year: 2030, month: 3, day: 10))!
        let earlyHabit = makeHabit(title: "Early")
        let lateHabit = makeHabit(title: "Late")
        let early = HabitRecord(habitID: earlyHabit.id, date: day.addingTimeInterval(60), isCompleted: false)
        let late = HabitRecord(habitID: lateHabit.id, date: day.addingTimeInterval(24 * 3_600 - 60), isCompleted: false)
        let store = PerformanceTestStore.make()
        store.habits = [earlyHabit, lateHabit]
        store.habitRecords = [early, late]
        let viewModel = JournalViewModel(store: store, anchorDate: day, baseCalendar: calendar)
        let originalDay = try XCTUnwrap(viewModel.calendarDays(for: day).first { $0.date == day })
        XCTAssertEqual(originalDay.habits, [early, late])
        XCTAssertNotEqual(store.records(for: day).count, originalDay.habits.count)
        let selectedDate = viewModel.selectedDate

        store.setHabitCompletion(lateHabit.id, on: late.date, completed: true)

        let updatedDay = try XCTUnwrap(viewModel.calendarDays(for: day).first { $0.date == day })
        XCTAssertEqual(updatedDay.habits.map(\.id), [early.id, late.id])
        XCTAssertEqual(updatedDay.habits.map(\.isCompleted), [false, true])
        XCTAssertEqual(viewModel.days.first { $0.date == day }?.habits, updatedDay.habits)
        XCTAssertEqual(viewModel.selectedDate, selectedDate)
        XCTAssertEqual(viewModel.dataRevision, 1)
    }

    // Observing cache contents is deliberate here: equal recomputed values alone
    // would miss the full-cache eviction that caused hidden tabs to do work.
    private func cached<Value>(_ name: String, in viewModel: JournalViewModel) throws -> Value {
        let value = Mirror(reflecting: viewModel).children.first { $0.label == name }?.value
        return try XCTUnwrap(value as? Value)
    }

    private func makeHabit(title: String) -> Habit {
        Habit(title: title, iconName: "checkmark", colorHex: "#123456", schedule: .daily,
              createdAt: date(month: 1, day: 1))
    }

    private func date(month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2030, month: month, day: day))!
    }

    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
