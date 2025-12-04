//
//  HabitsViewModel.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import Combine
import SwiftUI

struct HabitHeatCell: Identifiable, Hashable {
    enum State: String, Hashable {
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

    struct HabitWeekStatus: Identifiable {
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

    private let store: AppDataStore
    private var cancellables = Set<AnyCancellable>()

    init(store: AppDataStore, referenceDate: Date = Date()) {
        self.store = store
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
            .combineLatest(store.$habitRecords)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    private func refresh() {
        let updates = { [self] in
            self.habits = self.store.habits
            self.statuses = self.habits.map { habit in
                let recordsDictionary = store.habitRecords.reduce(into: [Date: HabitRecord]()) { partialResult, record in
                    guard record.habitID == habit.id else { return }
                    partialResult[record.date.startOfDay] = record
                }
                return HabitWeekStatus(habit: habit, dates: weekDates, records: recordsDictionary)
            }
            self.rebuildHeatmaps()
        }

        if let animation = pendingAnimation {
            withAnimation(animation) {
                updates()
            }
            pendingAnimation = nil
        } else {
            updates()
        }
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

    func monthlyCompletionCount(for habit: Habit, in month: Date = Date()) -> Int {
        let calendar = Calendar.current
        return store.habitRecords.filter {
            $0.habitID == habit.id &&
            $0.isCompleted &&
            calendar.isDate($0.date, equalTo: month, toGranularity: .month)
        }.count
    }

    func currentStreak(for habit: Habit, asOf date: Date = Date()) -> Int {
        let calendar = Calendar.current
        let records = store.habitRecords
            .filter { $0.habitID == habit.id }
            .reduce(into: [Date: HabitRecord]()) { result, record in
                result[record.date.startOfDay] = record
            }

        var streak = 0
        var cursor = calendar.startOfDay(for: date)

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

    func maxStreak(for habit: Habit, asOf date: Date = Date()) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        guard let start = calendar.date(byAdding: .day, value: -365, to: today) else { return 0 }
        
        let records = store.habitRecords
            .filter { $0.habitID == habit.id }
            .reduce(into: [Date: HabitRecord]()) { result, record in
                result[record.date.startOfDay] = record
            }
        
        var cursor = start
        var longest = 0
        var running = 0
        
        while cursor <= today {
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
        
        return max(longest, currentStreak(for: habit, asOf: date))
    }

    func miniHeatmap(for habit: Habit) -> [HabitHeatCell] {
        miniHeatmaps[habit.id] ?? []
    }

    func summary(for date: Date) -> HabitDaySummary? {
        let day = Calendar.current.startOfDay(for: date)
        return yearlySummaries[day]
    }

    // MARK: - Heatmap Builders

    private func rebuildHeatmaps() {
        let recordsLookup = store.habitRecords.reduce(into: [UUID: [Date: HabitRecord]]()) { partialResult, record in
            var habitMap = partialResult[record.habitID] ?? [:]
            habitMap[record.date.startOfDay] = record
            partialResult[record.habitID] = habitMap
        }
        computeYearlyHeatmap(with: recordsLookup)
        computeMiniHeatmaps(with: recordsLookup)
        computeAverageRates()
    }

    private func computeYearlyHeatmap(with recordsLookup: [UUID: [Date: HabitRecord]]) {
        let calendar = Calendar.current
        let startOfCurrentWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? calendar.startOfDay(for: Date())
        let weeks = 53
        guard let start = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: startOfCurrentWeek) else { return }

        var map: [Date: HabitDaySummary] = [:]
        for offset in 0..<(weeks * 7) {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let day = calendar.startOfDay(for: date)
            let scheduled = habits.filter { $0.schedule.isActive(on: day) }
            let completed = scheduled.filter { recordsLookup[$0.id]?[day]?.isCompleted == true }
            map[day] = HabitDaySummary(date: day,
                                       scheduledHabits: scheduled,
                                       completedHabits: completed)
        }

        yearStartDate = start
        yearWeekCount = weeks
        yearlySummaries = map
    }

    private func computeMiniHeatmaps(with recordsLookup: [UUID: [Date: HabitRecord]]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weeksToShow = 10
        let startOfCurrentWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
        guard let start = calendar.date(byAdding: .weekOfYear, value: -(weeksToShow - 1), to: startOfCurrentWeek) else { return }
        let totalDays = weeksToShow * 7

        var map: [UUID: [HabitHeatCell]] = [:]

        for habit in habits {
            var cells: [HabitHeatCell] = []
            for offset in 0..<totalDays {
                guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
                let day = calendar.startOfDay(for: date)
                let isFuture = day > today
                let isActive = habit.schedule.isActive(on: day)
                if isActive == false || isFuture {
                    cells.append(HabitHeatCell(date: day, state: .inactive, isToday: calendar.isDate(day, inSameDayAs: today)))
                    continue
                }

                let isDone = recordsLookup[habit.id]?[day]?.isCompleted == true
                cells.append(HabitHeatCell(date: day,
                                           state: isDone ? .completed : .pending,
                                           isToday: calendar.isDate(day, inSameDayAs: today)))
            }
            map[habit.id] = cells
        }

        miniHeatmaps = map
    }

    private func computeAverageRates() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: today)) ?? today
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today

        let summaries = yearlySummaries.values
        func averageRate(from collection: [HabitDaySummary]) -> Double {
            let eligible = collection.filter { $0.scheduledCount > 0 }
            guard eligible.isEmpty == false else { return 0 }
            let total = eligible.reduce(0.0) { partial, summary in
                partial + Double(summary.completedCount) / Double(summary.scheduledCount)
            }
            return total / Double(eligible.count)
        }

        yearlyAverageRate = averageRate(from: summaries.filter { $0.date >= startOfYear })
        monthlyAverageRate = averageRate(from: summaries.filter { $0.date >= startOfMonth })
    }
}
