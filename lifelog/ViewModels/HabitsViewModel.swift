//
//  HabitsViewModel.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import Combine
import SwiftUI
import UIKit

nonisolated struct HabitHeatCell: Identifiable, Hashable, Sendable {
    enum State: String, Hashable, Sendable {
        case inactive
        case pending
        case completed
    }

    let date: Date
    let state: State
    let isToday: Bool

    var id: Date { date }
}

struct HabitDaySummary: Identifiable, Hashable {
    let date: Date
    let scheduledHabits: [Habit]
    let completedHabits: [Habit]

    var scheduledCount: Int { scheduledHabits.count }
    var completedCount: Int { completedHabits.count }

    var id: Date { date }
}

@MainActor
final class HabitsViewModel: ObservableObject {

    struct HabitWeekStatus: Identifiable, Equatable {
        let habit: Habit
        let dates: [Date]
        let records: [Date: HabitRecord]

        var id: UUID { habit.id }

        func isCompleted(on date: Date) -> Bool {
            records[date.startOfDay]?.isCompleted == true
        }

        func isActive(on date: Date) -> Bool {
            habit.schedule.isActive(on: date)
        }
    }

    private struct HabitStreakSnapshot: Equatable {
        let current: Int
        let best: Int
    }

    @Published private(set) var habits: [Habit] = []
    @Published private(set) var weekDates: [Date] = []
    @Published private(set) var statuses: [HabitWeekStatus] = []
    @Published private(set) var yearlySummaries: [Date: HabitDaySummary] = [:]
    @Published private(set) var yearStartDate: Date = Calendar.current.startOfDay(for: Date())
    @Published private(set) var yearWeekCount: Int = 53
    @Published private(set) var miniHeatmaps: [UUID: [HabitHeatCell]] = [:]
    @Published private(set) var yearlyAverageRate: Double = 0
    @Published private(set) var monthlyAverageRate: Double = 0
    private var pendingAnimation: Animation?
    private var recordsLookupCache: [UUID: [Date: HabitRecord]] = [:]
    private var streakSnapshots: [UUID: HabitStreakSnapshot] = [:]
    private var allHabits: [Habit] = []
    private var projectionDay: Date?
    private var projectionCalendar = Calendar.current
    private var startOfYear = Date.distantPast
    private var startOfMonth = Date.distantPast
    private var yearlyRate = HabitAggregateProjection.Rate()
    private var monthlyRate = HabitAggregateProjection.Rate()
    private var refreshGeneration = 0
    private var refreshTask: _Concurrency.Task<Void, Never>?
    private var projectionTask: _Concurrency.Task<HabitAggregateProjection, Never>?
    private var pendingCompletionDays: [UUID: Set<Date>] = [:]

    private let store: AppDataStore
    private let dateProvider: () -> Date
    private var cancellables = Set<AnyCancellable>()

    // Match AppDataStore's workaround for Swift's isolated-deinit back-deployment crash.
    nonisolated deinit {}

    init(store: AppDataStore, referenceDate: Date = Date(), dateProvider: @escaping () -> Date = { Date() }) {
        self.store = store
        self.dateProvider = dateProvider
        self.weekDates = Self.makeWeekDates(around: referenceDate)
        bind()
        refresh()
    }

    private static func makeWeekDates(around date: Date) -> [Date] {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek)?.startOfDay }
    }

    private func bind() {
        store.$habits
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] habits in
                // @Published sends before storage changes; use its new value.
                self?.refresh(allHabits: habits)
            }
            .store(in: &cancellables)

        store.habitRecordChanges
            .sink { [weak self] change in
                switch change {
                case .reset:
                    self?.refresh()
                case .completion(let habitID, let day):
                    self?.updateCompletion(for: habitID, on: day)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .merge(with: NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification),
                   NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshForCurrentDayIfNeeded() }
            .store(in: &cancellables)
    }

    private func refresh(allHabits newHabits: [Habit]? = nil) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: dateProvider())
        if let projectionDay, projectionDay != today || projectionCalendar != calendar {
            weekDates = Self.makeWeekDates(around: today)
        }
        projectionDay = today
        projectionCalendar = calendar
        allHabits = newHabits ?? store.habits
        recordsLookupCache = store.latestHabitRecordsByHabit()
        // Metadata and day changes invalidate the meaning of the old snapshot.
        // Accessors use the fresh record cache until the worker supplies a new one.
        streakSnapshots = [:]
        let activeHabits = allHabits.filter { !$0.isArchived }
        if habits != activeHabits { habits = activeHabits }
        let newStatuses = activeHabits.map {
            HabitWeekStatus(habit: $0, dates: weekDates, records: recordsLookupCache[$0.id] ?? [:])
        }
        if statuses != newStatuses { statuses = newStatuses }

        // Only complete rebuilds need all history. Completion events below keep
        // these caches ready while the tab is hidden (docs/requirements.md §4.6).
        let snapshots = allHabits.map { snapshot(for: $0, records: recordsLookupCache[$0.id] ?? [:], calendar: calendar) }
        refreshGeneration += 1
        let generation = refreshGeneration
        pendingCompletionDays = [:]
        refreshTask?.cancel()
        projectionTask?.cancel()
        let work = _Concurrency.Task.detached(priority: .userInitiated) {
            HabitAggregateProjection.build(habits: snapshots, today: today, calendar: calendar)
        }
        projectionTask = work
        refreshTask = _Concurrency.Task { [weak self] in
            let result = await work.value
            guard !_Concurrency.Task.isCancelled, let self,
                  self.refreshGeneration == generation else { return }
            self.apply(result)
            self.projectionTask = nil
            self.refreshTask = nil

            // A checkbox can change while the full value snapshot is building.
            // Replay only those cells against the current store-backed lookup.
            let pending = self.pendingCompletionDays
            self.pendingCompletionDays = [:]
            for (habitID, days) in pending {
                for day in days { self.updateProjection(for: habitID, on: day) }
            }
        }
    }

    private func apply(_ projection: HabitAggregateProjection) {
        let habitsByID = Dictionary(uniqueKeysWithValues: allHabits.map { ($0.id, $0) })
        let newStreakSnapshots = projection.streaks.mapValues { HabitStreakSnapshot(current: $0.current, best: $0.best) }
        if streakSnapshots != newStreakSnapshots {
            objectWillChange.send()
            streakSnapshots = newStreakSnapshots
        }
        // Keep domain models on the main actor; the worker only passes habit IDs.
        var datedSummaries: [Date: HabitDaySummary] = [:]
        datedSummaries.reserveCapacity(projection.yearlySummaries.count)
        for (day, summary) in projection.yearlySummaries {
            datedSummaries[day] = HabitDaySummary(date: day,
                                                scheduledHabits: summary.scheduledIDs.compactMap { habitsByID[$0] },
                                                completedHabits: summary.completedIDs.compactMap { habitsByID[$0] })
        }
        if yearStartDate != projection.yearStartDate { yearStartDate = projection.yearStartDate }
        if yearlySummaries != datedSummaries { yearlySummaries = datedSummaries }
        if miniHeatmaps != projection.miniHeatmaps { miniHeatmaps = projection.miniHeatmaps }
        startOfYear = projection.startOfYear
        startOfMonth = projection.startOfMonth
        yearlyRate = projection.yearlyRate
        monthlyRate = projection.monthlyRate
        publishAverageRates()
    }

    private func updateCompletion(for habitID: UUID, on date: Date) {
        refreshForCurrentDayIfNeeded()
        let day = projectionCalendar.startOfDay(for: date)
        let records = store.latestHabitRecords(for: habitID)
        let previousRecords = recordsLookupCache[habitID] ?? [:]
        guard records[day] != previousRecords[day] else {
            pendingAnimation = nil
            return
        }
        recordsLookupCache[habitID] = records
        let updates = { [self] in
            if let index = statuses.firstIndex(where: { $0.id == habitID }) {
                statuses[index] = HabitWeekStatus(habit: statuses[index].habit, dates: weekDates, records: records)
            }
            updateProjection(for: habitID, on: day)
        }

        if let animation = pendingAnimation {
            withAnimation(animation) { updates() }
            pendingAnimation = nil
        } else {
            updates()
        }
        if refreshTask != nil { pendingCompletionDays[habitID, default: []].insert(day) }
    }

    private func updateProjection(for habitID: UUID, on day: Date) {
        let records = recordsLookupCache[habitID] ?? [:]
        if let habit = habits.first(where: { $0.id == habitID }) {
            let today = projectionDay ?? projectionCalendar.startOfDay(for: dateProvider())
            if let index = miniHeatmaps[habitID]?.firstIndex(where: { $0.date == day }) {
                let state: HabitHeatCell.State = day > today || !habit.schedule.isActive(on: day)
                    ? .inactive : (records[day]?.isCompleted == true ? .completed : .pending)
                let cell = HabitHeatCell(date: day, state: state, isToday: day == today)
                if miniHeatmaps[habitID]?[index] != cell { miniHeatmaps[habitID]?[index] = cell }
            }
            let current = Self.calculateCurrentStreak(for: habit, asOf: today, records: records, calendar: projectionCalendar)
            let best = calculateMaxStreak(for: habit, asOf: today, records: records, calendar: projectionCalendar)
            let snapshot = HabitStreakSnapshot(current: current, best: max(best, current))
            if streakSnapshots[habitID] != snapshot {
                objectWillChange.send()
                streakSnapshots[habitID] = snapshot
            }
        }

        guard let previous = yearlySummaries[day], previous.scheduledHabits.contains(where: { $0.id == habitID }) else { return }
        let previousIDs = Set(previous.completedHabits.map(\.id))
        let completed = previous.scheduledHabits.filter {
            $0.id == habitID ? records[day]?.isCompleted == true : previousIDs.contains($0.id)
        }
        guard completed != previous.completedHabits else { return }
        let summary = HabitDaySummary(date: day, scheduledHabits: previous.scheduledHabits, completedHabits: completed)
        yearlySummaries[day] = summary
        let delta = Double(summary.completedCount - previous.completedCount) / Double(summary.scheduledCount)
        if day >= startOfYear { yearlyRate.total += delta }
        if day >= startOfMonth { monthlyRate.total += delta }
        publishAverageRates()
    }

    private func publishAverageRates() {
        if yearlyAverageRate != yearlyRate.average { yearlyAverageRate = yearlyRate.average }
        if monthlyAverageRate != monthlyRate.average { monthlyAverageRate = monthlyRate.average }
    }

    func refreshForCurrentDayIfNeeded() {
        let calendar = Calendar.current
        guard projectionDay != calendar.startOfDay(for: dateProvider()) || projectionCalendar != calendar else { return }
        refresh()
    }

    /// Allows callers/tests that need the initial aggregate to await its publication.
    func awaitPendingRefresh() async {
        while let refreshTask { await refreshTask.value }
    }

    private func snapshot(for habit: Habit, records: [Date: HabitRecord], calendar: Calendar) -> HabitAggregateProjection.HabitSnapshot {
        let weekdays: Set<Int>
        switch habit.schedule {
        case .daily:
            weekdays = Set(1...7)
        case .weekdays:
            weekdays = Set(Self.makeWeekDates(around: dateProvider()).filter { !calendar.isDateInWeekend($0) }.map {
                calendar.component(.weekday, from: $0)
            })
        case .custom(let days):
            weekdays = Set(days.map(\.rawValue))
        }
        return HabitAggregateProjection.HabitSnapshot(id: habit.id,
                                                       createdDay: calendar.startOfDay(for: habit.createdAt),
                                                       archivedDay: habit.archivedAt.map { calendar.startOfDay(for: $0) },
                                                       isArchived: habit.isArchived,
                                                       activeWeekdays: weekdays,
                                                       completedDays: Set(records.compactMap { $0.value.isCompleted ? $0.key : nil }))
    }

    func toggle(habit: Habit, on date: Date) {
        pendingAnimation = .spring(response: 0.35, dampingFraction: 0.8)
        store.toggleHabit(habit.id, on: date)
    }

    func setHabit(_ habit: Habit, on date: Date, completed: Bool) {
        guard habit.schedule.isActive(on: date) else { return }
        store.setHabitCompletion(habit.id, on: date, completed: completed)
    }

    func addHabit(_ habit: Habit) {
        store.addHabit(habit)
    }

    func updateHabit(_ habit: Habit) {
        store.updateHabit(habit)
    }

    func deleteHabit(_ habit: Habit) {
        store.deleteHabit(habit.id)
    }
    
    func moveHabit(from source: IndexSet, to destination: Int) {
        store.moveHabit(from: source, to: destination)
    }

    func monthlyCompletionCount(for habit: Habit, in month: Date = Date()) -> Int {
        store.habitCompletionCount(for: habit.id, in: month)
    }

    func currentStreak(for habit: Habit, asOf date: Date = Date()) -> Int {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: dateProvider())
        if targetDay == today, projectionDay == today, let snapshot = streakSnapshots[habit.id] {
            return snapshot.current
        }

        let records = recordsLookupCache[habit.id] ?? [:]
        return Self.calculateCurrentStreak(for: habit, asOf: targetDay, records: records, calendar: calendar)
    }

    func maxStreak(for habit: Habit, asOf date: Date = Date()) -> Int {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: dateProvider())
        if targetDay == today, projectionDay == today, let snapshot = streakSnapshots[habit.id] {
            return snapshot.best
        }

        let records = recordsLookupCache[habit.id] ?? [:]
        let current = Self.calculateCurrentStreak(for: habit, asOf: targetDay, records: records, calendar: calendar)
        let longest = calculateMaxStreak(for: habit, asOf: targetDay, records: records, calendar: calendar)
        return max(longest, current)
    }

    func miniHeatmap(for habit: Habit) -> [HabitHeatCell] {
        miniHeatmaps[habit.id] ?? []
    }

    func summary(for date: Date) -> HabitDaySummary? {
        let day = Calendar.current.startOfDay(for: date)
        return yearlySummaries[day]
    }

    // MARK: - Streak Calculations

    static func calculateCurrentStreak(
        for habit: Habit,
        asOf day: Date,
        records: [Date: HabitRecord],
        calendar: Calendar
    ) -> Int {
        // A custom schedule without weekdays never reaches a missing active day.
        // Older/imported data can contain it even though the editor prevents it.
        if case .custom(let days) = habit.schedule, days.isEmpty {
            return 0
        }
        var streak = 0
        var cursor = day

        while true {
            if habit.schedule.isActive(on: cursor) == false {
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = previous
                continue
            }

            guard let record = records[cursor], record.isCompleted else {
                break
            }

            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return streak
    }

    private func calculateMaxStreak(
        for habit: Habit,
        asOf day: Date,
        records: [Date: HabitRecord],
        calendar: Calendar
    ) -> Int {
        guard let start = calendar.date(byAdding: .day, value: -365, to: day) else { return 0 }

        var cursor = start
        var longest = 0
        var running = 0

        while cursor <= day {
            if habit.schedule.isActive(on: cursor) {
                if records[cursor]?.isCompleted == true {
                    running += 1
                    longest = max(longest, running)
                } else {
                    running = 0
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return longest
    }

}
