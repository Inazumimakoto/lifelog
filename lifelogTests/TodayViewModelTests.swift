import Combine
import XCTest
@testable import lifelify

@MainActor
final class TodayViewModelTests: XCTestCase {
    func testTimezoneChange_completionReevaluatesScheduledRows() {
        let previousTimeZone = NSTimeZone.default
        defer { NSTimeZone.default = previousTimeZone }
        NSTimeZone.default = TimeZone(identifier: "Asia/Tokyo")!
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 1))!
        let store = PerformanceTestStore.make()
        let monday = Habit(title: "Monday", iconName: "star", colorHex: "#000000", schedule: .custom(days: [.monday]),
                           createdAt: date.addingTimeInterval(-7 * 86_400))
        let tuesday = Habit(title: "Tuesday", iconName: "star", colorHex: "#000000", schedule: .custom(days: [.tuesday]),
                            createdAt: monday.createdAt)
        store.habits = [monday, tuesday]
        let viewModel = TodayViewModel(store: store, date: date)
        XCTAssertEqual(viewModel.habitStatuses.map { $0.habit.id }, [tuesday.id])

        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        store.setHabitCompletion(monday.id, on: date, completed: true)

        XCTAssertEqual(viewModel.habitStatuses.map { $0.habit.id }, [monday.id])
        XCTAssertTrue(viewModel.habitStatuses[0].isCompleted)
    }

    func testHabitCompletion_updatesOnlyCurrentDayRowImmediately() {
        let store = PerformanceTestStore.make()
        let day = Calendar.current.startOfDay(for: Date())
        let habit = Habit(title: "Habit", iconName: "star", colorHex: "#000000", schedule: .daily,
                          createdAt: day.addingTimeInterval(-86_400))
        let other = Habit(title: "Other", iconName: "star", colorHex: "#000000", schedule: .daily,
                          createdAt: habit.createdAt)
        store.habits = [habit, other]
        let viewModel = TodayViewModel(store: store, date: day)
        var habitPublications = 0
        var timelinePublications = 0
        var cancellables = Set<AnyCancellable>()
        viewModel.$habitStatuses.dropFirst().sink { _ in habitPublications += 1 }.store(in: &cancellables)
        viewModel.$timelineItems.dropFirst().sink { _ in timelinePublications += 1 }.store(in: &cancellables)

        store.setHabitCompletion(habit.id, on: day.addingTimeInterval(-86_400), completed: true)
        XCTAssertEqual(habitPublications, 0)
        store.setHabitCompletion(habit.id, on: day, completed: true)
        XCTAssertTrue(viewModel.habitStatuses[0].isCompleted)
        XCTAssertEqual(viewModel.habitStatuses[0].currentStreak, 2)
        XCTAssertNil(viewModel.habitStatuses[1].record)
        store.setHabitCompletion(habit.id, on: day, completed: false)
        XCTAssertFalse(viewModel.habitStatuses[0].isCompleted)
        XCTAssertEqual(viewModel.habitStatuses[0].currentStreak, 0)
        XCTAssertEqual(habitPublications, 2)
        XCTAssertEqual(timelinePublications, 0)
        withExtendedLifetime(cancellables) {}
    }

    func testDuplicateHabitCompletion_usesFirstRecordForHome() {
        let store = PerformanceTestStore.make()
        let day = Calendar.current.startOfDay(for: Date())
        let habit = Habit(title: "Habit", iconName: "star", colorHex: "#000000", schedule: .daily,
                          createdAt: day)
        let first = HabitRecord(habitID: habit.id, date: day, isCompleted: false)
        let last = HabitRecord(habitID: habit.id, date: day.addingTimeInterval(3_600), isCompleted: true)
        store.habits = [habit]
        store.habitRecords = [first, last]
        let viewModel = TodayViewModel(store: store, date: day)
        XCTAssertFalse(viewModel.habitStatuses[0].isCompleted)
        XCTAssertEqual(viewModel.habitStatuses[0].currentStreak, 1)

        store.setHabitCompletion(habit.id, on: day, completed: true)

        XCTAssertEqual(viewModel.habitStatuses[0].record?.id, first.id)
        XCTAssertTrue(viewModel.habitStatuses[0].isCompleted)
        XCTAssertEqual(viewModel.habitStatuses[0].currentStreak, 1)
        XCTAssertEqual(store.latestHabitRecords(for: habit.id)[day], last)
    }

    func testCustomSchedule_streakSkipsRestDaysAndEndsAtMissingScheduledDay() {
        let store = PerformanceTestStore.make()
        let wednesday = date(2030, 3, 13)
        let monday = shifted(wednesday, by: -2)
        let habit = Habit(title: "Routine", iconName: "star", colorHex: "#000000",
                          schedule: .custom(days: [.monday, .wednesday]), createdAt: shifted(monday, by: -7))
        store.habits = [habit]
        store.habitRecords = [
            HabitRecord(habitID: habit.id, date: monday, isCompleted: true),
            HabitRecord(habitID: habit.id, date: shifted(wednesday, by: -1), isCompleted: false),
            HabitRecord(habitID: habit.id, date: wednesday, isCompleted: true)
        ]
        let viewModel = TodayViewModel(store: store, date: wednesday.addingTimeInterval(12 * 3_600))

        XCTAssertEqual(viewModel.habitStatuses[0].currentStreak, 2)
        XCTAssertEqual(viewModel.habitStatuses[0].currentStreak,
                       HabitsViewModel.calculateCurrentStreak(for: habit, asOf: wednesday,
                                                              records: store.latestHabitRecords(for: habit.id),
                                                              calendar: .current))

        store.setHabitCompletion(habit.id, on: monday, completed: false)
        XCTAssertEqual(viewModel.habitStatuses[0].currentStreak, 1)
        XCTAssertTrue(viewModel.habitStatuses[0].isCompleted)
        store.setHabitCompletion(habit.id, on: wednesday, completed: false)
        XCTAssertEqual(viewModel.habitStatuses[0].currentStreak, 0)
    }

    func testWeekdaySchedule_initialStreakSkipsWeekend() {
        let store = PerformanceTestStore.make()
        let monday = date(2030, 3, 18)
        let habit = Habit(title: "Weekday", iconName: "star", colorHex: "#000000", schedule: .weekdays,
                          createdAt: shifted(monday, by: -7))
        store.habits = [habit]
        store.habitRecords = [
            HabitRecord(habitID: habit.id, date: shifted(monday, by: -3), isCompleted: true),
            HabitRecord(habitID: habit.id, date: monday, isCompleted: true)
        ]
        let viewModel = TodayViewModel(store: store, date: monday)

        XCTAssertEqual(viewModel.habitStatuses[0].currentStreak, 2)
    }

    func testPastCompletion_updatesOnlyTargetStreakWithoutChangingDisplayedCheckbox() {
        let store = PerformanceTestStore.make()
        let today = date(2030, 3, 15)
        let yesterday = shifted(today, by: -1)
        let earlier = shifted(today, by: -2)
        let habit = Habit(title: "Changed", iconName: "star", colorHex: "#000000", schedule: .daily,
                          createdAt: shifted(today, by: -30))
        let other = Habit(title: "Other", iconName: "star", colorHex: "#000000", schedule: .daily,
                          createdAt: habit.createdAt)
        store.habits = [habit, other]
        store.habitRecords = [
            HabitRecord(habitID: habit.id, date: yesterday, isCompleted: true),
            HabitRecord(habitID: habit.id, date: today, isCompleted: true),
            HabitRecord(habitID: other.id, date: today, isCompleted: true)
        ]
        let viewModel = TodayViewModel(store: store, date: today)
        let displayedRecord = viewModel.habitStatuses[0].record
        let otherStatus = viewModel.habitStatuses[1]
        var publications = 0
        let subscription = viewModel.$habitStatuses.dropFirst().sink { _ in publications += 1 }

        store.setHabitCompletion(habit.id, on: earlier, completed: true)
        XCTAssertEqual(viewModel.habitStatuses[0].currentStreak, 3)
        XCTAssertEqual(viewModel.habitStatuses[0].record, displayedRecord)
        XCTAssertEqual(viewModel.habitStatuses[1], otherStatus)
        store.setHabitCompletion(habit.id, on: yesterday, completed: false)
        XCTAssertEqual(viewModel.habitStatuses[0].currentStreak, 1)
        XCTAssertEqual(viewModel.habitStatuses[0].record, displayedRecord)
        XCTAssertEqual(viewModel.habitStatuses[1], otherStatus)

        // Days beyond the first gap and future records leave the visible value unchanged.
        store.setHabitCompletion(habit.id, on: shifted(today, by: -10), completed: true)
        store.setHabitCompletion(habit.id, on: shifted(today, by: 1), completed: true)
        XCTAssertEqual(publications, 2)
        withExtendedLifetime(subscription) {}
    }

    func testDuplicateLatestIncomplete_streakMatchesHabitsWhileCheckboxUsesFirstRecord() {
        let store = PerformanceTestStore.make()
        let today = date(2030, 3, 15)
        let habit = Habit(title: "Duplicate", iconName: "star", colorHex: "#000000", schedule: .daily,
                          createdAt: shifted(today, by: -7))
        let first = HabitRecord(habitID: habit.id, date: today, isCompleted: true)
        let latest = HabitRecord(habitID: habit.id, date: today.addingTimeInterval(3_600), isCompleted: false)
        store.habits = [habit]
        store.habitRecords = [first, latest]
        let viewModel = TodayViewModel(store: store, date: today)

        XCTAssertTrue(viewModel.habitStatuses[0].isCompleted)
        XCTAssertEqual(viewModel.habitStatuses[0].currentStreak, 0)
        store.setHabitCompletion(habit.id, on: today, completed: false)
        XCTAssertFalse(viewModel.habitStatuses[0].isCompleted)
        XCTAssertEqual(viewModel.habitStatuses[0].currentStreak, 0)
        XCTAssertEqual(store.latestHabitRecords(for: habit.id)[today], latest)
    }

    func testDateChangeAndRecordReset_refreshDisplayedStreak() async {
        let store = PerformanceTestStore.make()
        let today = date(2030, 3, 15)
        let tomorrow = shifted(today, by: 1)
        let habit = Habit(title: "Habit", iconName: "star", colorHex: "#000000", schedule: .daily,
                          createdAt: shifted(today, by: -7))
        store.habits = [habit]
        let todayRecord = HabitRecord(habitID: habit.id, date: today, isCompleted: true)
        let tomorrowRecord = HabitRecord(habitID: habit.id, date: tomorrow, isCompleted: true)
        store.habitRecords = [todayRecord, tomorrowRecord]
        let viewModel = TodayViewModel(store: store, date: today)
        XCTAssertEqual(viewModel.habitStatuses[0].currentStreak, 1)
        let changedDate = expectation(description: "New display day's streak published")
        let dateSubscription = viewModel.$habitStatuses.dropFirst().sink { statuses in
            if statuses.first?.record?.id == tomorrowRecord.id, statuses.first?.currentStreak == 2 {
                changedDate.fulfill()
            }
        }

        viewModel.date = tomorrow
        await fulfillment(of: [changedDate], timeout: 2)
        dateSubscription.cancel()
        XCTAssertEqual(viewModel.habitStatuses[0].currentStreak, 2)

        let reloaded = expectation(description: "Replaced record history reflected in streak")
        let resetSubscription = viewModel.$habitStatuses.dropFirst().sink { statuses in
            if statuses.first?.currentStreak == 1 { reloaded.fulfill() }
        }
        store.habitRecords = [tomorrowRecord]
        await fulfillment(of: [reloaded], timeout: 2)
        XCTAssertEqual(viewModel.habitStatuses[0].record?.id, tomorrowRecord.id)
        XCTAssertEqual(viewModel.habitStatuses[0].currentStreak, 1)
        withExtendedLifetime(resetSubscription) {}
    }

    func testScheduleMetadataChange_refreshesStreakUsingUpdatedScheduledDays() async {
        let store = PerformanceTestStore.make()
        let wednesday = date(2030, 3, 13)
        let monday = shifted(wednesday, by: -2)
        var habit = Habit(title: "Routine", iconName: "star", colorHex: "#000000", schedule: .daily,
                          createdAt: shifted(monday, by: -7))
        store.habits = [habit]
        store.habitRecords = [monday, wednesday].map { HabitRecord(habitID: habit.id, date: $0, isCompleted: true) }
        let viewModel = TodayViewModel(store: store, date: wednesday)
        XCTAssertEqual(viewModel.habitStatuses[0].currentStreak, 1)
        let updated = expectation(description: "Updated schedule used for current streak")
        let subscription = viewModel.$habitStatuses.dropFirst().sink { statuses in
            if statuses.first?.currentStreak == 2 { updated.fulfill() }
        }

        habit.schedule = .custom(days: [.monday, .wednesday])
        store.updateHabit(habit)
        await fulfillment(of: [updated], timeout: 2)
        XCTAssertEqual(viewModel.habitStatuses[0].habit.schedule, habit.schedule)
        XCTAssertEqual(viewModel.habitStatuses[0].currentStreak, 2)
        withExtendedLifetime(subscription) {}
    }

    func testMemoEdits_updateMemoOnceWithoutRepublishingOtherSections() async {
        let store = PerformanceTestStore.make()
        let day = Calendar.current.startOfDay(for: Date())
        store.tasks = [Task(title: "Task", endDate: day)]
        let viewModel = TodayViewModel(store: store, date: day)
        var cancellables = Set<AnyCancellable>()
        var timelinePublications = 0
        var taskPublications = 0
        var habitPublications = 0
        var memoPublications = 0
        viewModel.$timelineItems.dropFirst().sink { _ in timelinePublications += 1 }.store(in: &cancellables)
        viewModel.$tasksDueToday.dropFirst().sink { _ in taskPublications += 1 }.store(in: &cancellables)
        viewModel.$habitStatuses.dropFirst().sink { _ in habitPublications += 1 }.store(in: &cancellables)
        let updated = expectation(description: "Latest memo snapshot published")
        viewModel.$memoPad.dropFirst().sink { memo in
            memoPublications += 1
            if memo.text == "Latest" { updated.fulfill() }
        }.store(in: &cancellables)

        store.memoPad = MemoPad(text: "L")
        store.memoPad = MemoPad(text: "La")
        store.memoPad = MemoPad(text: "Latest")
        await fulfillment(of: [updated], timeout: 2)

        XCTAssertEqual(viewModel.memoPad.text, "Latest")
        XCTAssertEqual(memoPublications, 1)
        XCTAssertEqual(timelinePublications, 0)
        XCTAssertEqual(taskPublications, 0)
        XCTAssertEqual(habitPublications, 0)
        XCTAssertEqual(viewModel.timelineItems.map(\.sourceId), store.tasks.map { Optional($0.id) })
        withExtendedLifetime(cancellables) {}
    }

    func testTaskAndEventBurst_publishesOneFinalTimeline() async {
        let store = PerformanceTestStore.make()
        let day = Calendar.current.startOfDay(for: Date())
        let viewModel = TodayViewModel(store: store, date: day)
        var timelines: [[JournalViewModel.TimelineItem]] = []
        let updated = expectation(description: "Combined inputs applied")
        let subscription = viewModel.$timelineItems.dropFirst().sink {
            timelines.append($0)
            if $0.count == 2 { updated.fulfill() }
        }
        store.tasks = [Task(title: "Task", endDate: day.addingTimeInterval(12 * 3_600))]
        store.calendarEvents = [CalendarEvent(title: "Event", startDate: day.addingTimeInterval(9 * 3_600),
                                             endDate: day.addingTimeInterval(10 * 3_600), calendarName: "Work")]
        await fulfillment(of: [updated], timeout: 2)
        XCTAssertEqual(timelines.count, 1)
        XCTAssertEqual(Set(viewModel.timelineItems.map(\.title)), Set(["Task", "Event"]))
        withExtendedLifetime(subscription) {}
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func shifted(_ date: Date, by days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: date)!
    }
}
