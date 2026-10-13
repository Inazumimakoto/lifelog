import XCTest
import Combine
import SwiftData
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

    func testCompletion_updatesOnlyChangedDayAndHabitWithoutRepublishingMetadata() async throws {
        let today = date(2030, 3, 15)
        let yesterday = shifted(today, by: -1)
        let habit = makeHabit(title: "Changed")
        let other = makeHabit(title: "Unchanged", schedule: .weekdays)
        let records = [HabitRecord(habitID: habit.id, date: yesterday, isCompleted: true)]
        let store = try makeStore(habits: [habit, other], records: records)
        let model = HabitsViewModel(store: store, referenceDate: today, dateProvider: { today })
        await model.awaitPendingRefresh()
        let previousSummaries = model.yearlySummaries
        let previousMini = model.miniHeatmap(for: other)
        let previousOtherStatus = model.statuses.first { $0.id == other.id }
        let publications = Publications(model: model)

        store.setHabitCompletion(habit.id, on: today, completed: true)

        XCTAssertEqual(model.summary(for: today)?.completedHabits.map(\.id), [habit.id])
        XCTAssertEqual(model.miniHeatmap(for: habit).first { $0.date == today }?.state, .completed)
        XCTAssertEqual(model.currentStreak(for: habit, asOf: today), 2)
        XCTAssertEqual(model.maxStreak(for: habit, asOf: today), 2)
        XCTAssertEqual(model.miniHeatmap(for: other), previousMini)
        XCTAssertEqual(model.statuses.first { $0.id == other.id }, previousOtherStatus)
        XCTAssertEqual(model.yearlySummaries.filter { $0.key != today }, previousSummaries.filter { $0.key != today })
        XCTAssertEqual(publications.count("statuses"), 1)
        XCTAssertEqual(publications.count("summaries"), 1)
        XCTAssertEqual(publications.count("mini"), 1)
        XCTAssertEqual(publications.count("habits"), 0)
        XCTAssertEqual(publications.count("weeks"), 0)
        XCTAssertEqual(publications.count("yearStart"), 0)
        await assertMatchesFullRebuild(model, store: store, today: today)

        // Repeated changes keep rates and longest/current streaks reversible.
        for completed in [false, true, false, true] {
            store.setHabitCompletion(habit.id, on: today, completed: completed)
            await assertMatchesFullRebuild(model, store: store, today: today)
        }
    }

    func testArchivedHabitOutsideMiniWindow_updatesHistoryAndYearRateOnly() async throws {
        let today = date(2030, 3, 15)
        let oldDay = date(2030, 1, 5)
        let habit = makeHabit(title: "Active")
        let archived = Habit(title: "Archived", iconName: "star", colorHex: "#123456", schedule: .daily,
                             isArchived: true, createdAt: date(2029, 1, 1), archivedAt: date(2030, 3, 1))
        let store = try makeStore(habits: [habit, archived])
        let model = HabitsViewModel(store: store, referenceDate: today, dateProvider: { today })
        await model.awaitPendingRefresh()
        let previousMonthlyRate = model.monthlyAverageRate
        let publications = Publications(model: model)

        store.setHabitCompletion(archived.id, on: oldDay, completed: true)

        XCTAssertEqual(model.summary(for: oldDay)?.completedHabits.map(\.id), [archived.id])
        XCTAssertEqual(model.summary(for: today)?.scheduledHabits.map(\.id), [habit.id])
        XCTAssertEqual(model.monthlyAverageRate, previousMonthlyRate)
        XCTAssertGreaterThan(model.yearlyAverageRate, 0)
        XCTAssertEqual(publications.count("statuses"), 0)
        XCTAssertEqual(publications.count("mini"), 0)
        XCTAssertEqual(publications.count("monthRate"), 0)
        XCTAssertEqual(publications.count("summaries"), 1)
        await assertMatchesFullRebuild(model, store: store, today: today)
    }

    func testDuplicateDayChangedFirstRecord_keepsLatestProjectionWithoutPublishing() async throws {
        let today = date(2030, 3, 15)
        let habit = makeHabit()
        let first = HabitRecord(habitID: habit.id, date: today, isCompleted: false)
        let latest = HabitRecord(habitID: habit.id, date: today.addingTimeInterval(3_600), isCompleted: true)
        let store = try makeStore(habits: [habit], records: [first, latest])
        // Legacy array order, rather than SwiftData fetch order, determines latest.
        store.habitRecords = [first, latest]
        let model = HabitsViewModel(store: store, referenceDate: today, dateProvider: { today })
        await model.awaitPendingRefresh()
        let publications = Publications(model: model)

        store.setHabitCompletion(habit.id, on: today, completed: true)

        XCTAssertTrue(model.statuses[0].isCompleted(on: today))
        XCTAssertEqual(model.summary(for: today)?.completedCount, 1)
        XCTAssertEqual(model.monthlyCompletionCount(for: habit, in: today), 2)
        XCTAssertEqual(publications.total, 0)
        await assertMatchesFullRebuild(model, store: store, today: today)
    }

    func testNoOpCompletion_doesNotRepublishAnyProjection() async throws {
        let today = date(2030, 3, 15)
        let habit = makeHabit()
        let store = try makeStore(habits: [habit], records: [HabitRecord(habitID: habit.id, date: today, isCompleted: true)])
        let model = HabitsViewModel(store: store, referenceDate: today, dateProvider: { today })
        await model.awaitPendingRefresh()
        let publications = Publications(model: model)

        store.setHabitCompletion(habit.id, on: today, completed: true)
        store.setHabitCompletion(habit.id, on: shifted(today, by: -3), completed: false)

        XCTAssertEqual(publications.total, 0)
    }

    func testBurstDuringInitialProjection_replaysFinalValuesWithoutLosingChecks() async throws {
        let today = date(2030, 3, 15)
        let habits = (0..<8).map { makeHabit(title: "Habit \($0)") }
        let store = try makeStore(habits: habits)
        let model = HabitsViewModel(store: store, referenceDate: today, dateProvider: { today })
        // No await: the main actor cannot apply the old worker snapshot yet.
        XCTAssertEqual(model.statuses.count, habits.count)
        for (index, habit) in habits.enumerated() {
            let day = shifted(today, by: -index)
            store.setHabitCompletion(habit.id, on: day, completed: true)
            store.setHabitCompletion(habit.id, on: day, completed: false)
            store.setHabitCompletion(habit.id, on: day, completed: true)
        }
        await model.awaitPendingRefresh()

        for (index, habit) in habits.enumerated() {
            let day = shifted(today, by: -index)
            XCTAssertEqual(model.summary(for: day)?.completedHabits.map(\.id), [habit.id])
            XCTAssertEqual(model.miniHeatmap(for: habit).first { $0.date == day }?.state, .completed)
        }
        await assertMatchesFullRebuild(model, store: store, today: today)
    }

    func testResetAndBackdatingDuringProjection_discardsStaleSnapshot() async throws {
        let today = date(2030, 3, 15)
        let earlier = shifted(today, by: -5)
        let habit = Habit(title: "New", iconName: "star", colorHex: "#123456", schedule: .daily, createdAt: today)
        let store = try makeStore(habits: [habit])
        let model = HabitsViewModel(store: store, referenceDate: today, dateProvider: { today })
        store.setHabitCompletion(habit.id, on: earlier, completed: true)
        // A reload/import replacing all records invalidates the earlier worker.
        store.habitRecords = [HabitRecord(habitID: habit.id, date: earlier, isCompleted: false)]
        store.setHabitCompletion(habit.id, on: today, completed: true)
        await model.awaitPendingRefresh()

        XCTAssertEqual(model.habits.first?.createdAt, earlier)
        XCTAssertEqual(model.summary(for: earlier)?.scheduledCount, 1)
        XCTAssertEqual(model.summary(for: earlier)?.completedCount, 0)
        XCTAssertEqual(model.summary(for: today)?.completedCount, 1)
        XCTAssertEqual(model.miniHeatmap(for: habit).first { $0.date == earlier }?.state, .pending)
        await assertMatchesFullRebuild(model, store: store, today: today)
    }

    func testDayRollover_refreshesTodayMarkerWeekAndStreaksBeforeCompletion() async throws {
        var now = date(2030, 3, 15)
        let firstDay = now
        let habit = makeHabit()
        let store = try makeStore(habits: [habit], records: [HabitRecord(habitID: habit.id, date: now, isCompleted: true)])
        let model = HabitsViewModel(store: store, referenceDate: now, dateProvider: { now })
        await model.awaitPendingRefresh()
        XCTAssertEqual(model.currentStreak(for: habit, asOf: now), 1)

        now = shifted(now, by: 7)
        model.refreshForCurrentDayIfNeeded()
        XCTAssertEqual(model.currentStreak(for: habit, asOf: now), 0)
        store.setHabitCompletion(habit.id, on: now, completed: true)
        await model.awaitPendingRefresh()

        XCTAssertFalse(model.weekDates.contains(firstDay))
        XCTAssertEqual(model.miniHeatmap(for: habit).filter(\.isToday).map(\.date), [now])
        XCTAssertEqual(model.currentStreak(for: habit, asOf: now), 1)
        await assertMatchesFullRebuild(model, store: store, today: now)
    }

    func testRecordOutsideAllVisibleWindows_onlyUpdatesTargetStatusHistory() async throws {
        let today = date(2030, 3, 15)
        let habit = makeHabit()
        let store = try makeStore(habits: [habit])
        let model = HabitsViewModel(store: store, referenceDate: today, dateProvider: { today })
        await model.awaitPendingRefresh()
        let publications = Publications(model: model)
        let oldDay = date(2029, 1, 5)

        store.setHabitCompletion(habit.id, on: oldDay, completed: true)

        XCTAssertTrue(model.statuses[0].isCompleted(on: oldDay))
        XCTAssertEqual(publications.count("statuses"), 1)
        XCTAssertEqual(publications.count("summaries"), 0)
        XCTAssertEqual(publications.count("mini"), 0)
        XCTAssertEqual(publications.count("yearRate"), 0)
        XCTAssertEqual(publications.count("monthRate"), 0)
        await assertMatchesFullRebuild(model, store: store, today: today)
    }

    func testScheduleAndArchiveEdits_rebuildScheduledDaysAndRates() async throws {
        let today = date(2030, 3, 15)
        let yesterday = shifted(today, by: -1)
        var habit = makeHabit()
        let store = try makeStore(habits: [habit], records: [HabitRecord(habitID: habit.id, date: yesterday, isCompleted: true)])
        let model = HabitsViewModel(store: store, referenceDate: today, dateProvider: { today })
        await model.awaitPendingRefresh()

        habit.schedule = .custom(days: [])
        store.updateHabit(habit)
        XCTAssertEqual(model.currentStreak(for: habit, asOf: today), 0)
        XCTAssertEqual(model.maxStreak(for: habit, asOf: today), 0)
        await model.awaitPendingRefresh()

        XCTAssertTrue(model.yearlySummaries.values.allSatisfy { $0.scheduledCount == 0 && $0.completedCount == 0 })
        XCTAssertTrue(model.miniHeatmap(for: habit).allSatisfy { $0.state == .inactive })
        XCTAssertEqual(model.currentStreak(for: habit, asOf: today), 0)
        XCTAssertEqual(model.maxStreak(for: habit, asOf: today), 0)
        XCTAssertEqual(model.yearlyAverageRate, 0)
        XCTAssertEqual(model.monthlyAverageRate, 0)

        habit.schedule = .daily
        habit.isArchived = true
        habit.archivedAt = today
        store.updateHabit(habit)
        await model.awaitPendingRefresh()

        XCTAssertTrue(model.statuses.isEmpty)
        XCTAssertTrue(model.miniHeatmaps.isEmpty)
        XCTAssertEqual(model.summary(for: yesterday)?.completedCount, 1)
        XCTAssertEqual(model.summary(for: today)?.scheduledCount, 0)
        await assertMatchesFullRebuild(model, store: store, today: today)
    }

    func testFutureCompletion_changesYearSummaryButKeepsMiniCellInactive() async throws {
        let today = date(2030, 3, 15)
        let future = shifted(today, by: 1)
        let habit = makeHabit()
        let store = try makeStore(habits: [habit])
        let model = HabitsViewModel(store: store, referenceDate: today, dateProvider: { today })
        await model.awaitPendingRefresh()
        let publications = Publications(model: model)

        store.setHabitCompletion(habit.id, on: future, completed: true)

        XCTAssertEqual(model.summary(for: future)?.completedCount, 1)
        XCTAssertEqual(model.miniHeatmap(for: habit).first { $0.date == future }?.state, .inactive)
        XCTAssertEqual(model.currentStreak(for: habit, asOf: today), 0)
        XCTAssertEqual(model.maxStreak(for: habit, asOf: today), 0)
        XCTAssertEqual(publications.count("mini"), 0)
        await assertMatchesFullRebuild(model, store: store, today: today)
    }

    private func assertMatchesFullRebuild(_ model: HabitsViewModel, store: AppDataStore, today: Date,
                                         file: StaticString = #filePath, line: UInt = #line) async {
        let rebuilt = HabitsViewModel(store: store, referenceDate: today, dateProvider: { today })
        await rebuilt.awaitPendingRefresh()
        XCTAssertEqual(model.habits, rebuilt.habits, file: file, line: line)
        XCTAssertEqual(model.statuses, rebuilt.statuses, file: file, line: line)
        XCTAssertEqual(model.yearStartDate, rebuilt.yearStartDate, file: file, line: line)
        XCTAssertEqual(model.yearlySummaries, rebuilt.yearlySummaries, file: file, line: line)
        XCTAssertEqual(model.miniHeatmaps, rebuilt.miniHeatmaps, file: file, line: line)
        XCTAssertEqual(model.yearlyAverageRate, rebuilt.yearlyAverageRate, accuracy: 0.000000000001, file: file, line: line)
        XCTAssertEqual(model.monthlyAverageRate, rebuilt.monthlyAverageRate, accuracy: 0.000000000001, file: file, line: line)
        for habit in model.habits {
            XCTAssertEqual(model.currentStreak(for: habit, asOf: today), rebuilt.currentStreak(for: habit, asOf: today), file: file, line: line)
            XCTAssertEqual(model.maxStreak(for: habit, asOf: today), rebuilt.maxStreak(for: habit, asOf: today), file: file, line: line)
        }
    }

    private func makeStore(habits: [Habit], records: [HabitRecord] = []) throws -> AppDataStore {
        let container = PersistenceController(inMemory: true).container
        for (index, habit) in habits.enumerated() {
            let stored = SDHabit(domain: habit)
            stored.orderIndex = index
            container.mainContext.insert(stored)
        }
        for record in records { container.mainContext.insert(SDHabitRecord(domain: record)) }
        try container.mainContext.save()
        return AppDataStore(container: container, startsBackgroundServices: false)
    }

    private func makeHabit(title: String = "Habit", schedule: HabitSchedule = .daily) -> Habit {
        Habit(title: title, iconName: "star", colorHex: "#123456", schedule: schedule, createdAt: date(2029, 1, 1))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func shifted(_ day: Date, by offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: day)!
    }

    @MainActor
    private final class Publications {
        private var counts: [String: Int] = [:]
        private var cancellables = Set<AnyCancellable>()

        nonisolated deinit {}

        var total: Int { counts.values.reduce(0, +) }
        func count(_ key: String) -> Int { counts[key, default: 0] }

        init(model: HabitsViewModel) {
            model.$habits.dropFirst().sink { [weak self] _ in self?.counts["habits", default: 0] += 1 }.store(in: &cancellables)
            model.$statuses.dropFirst().sink { [weak self] _ in self?.counts["statuses", default: 0] += 1 }.store(in: &cancellables)
            model.$weekDates.dropFirst().sink { [weak self] _ in self?.counts["weeks", default: 0] += 1 }.store(in: &cancellables)
            model.$yearStartDate.dropFirst().sink { [weak self] _ in self?.counts["yearStart", default: 0] += 1 }.store(in: &cancellables)
            model.$yearlySummaries.dropFirst().sink { [weak self] _ in self?.counts["summaries", default: 0] += 1 }.store(in: &cancellables)
            model.$miniHeatmaps.dropFirst().sink { [weak self] _ in self?.counts["mini", default: 0] += 1 }.store(in: &cancellables)
            model.$yearlyAverageRate.dropFirst().sink { [weak self] _ in self?.counts["yearRate", default: 0] += 1 }.store(in: &cancellables)
            model.$monthlyAverageRate.dropFirst().sink { [weak self] _ in self?.counts["monthRate", default: 0] += 1 }.store(in: &cancellables)
        }
    }
}
