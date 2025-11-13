//
//  HabitsViewModel.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import Combine

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
    }

    @Published private(set) var habits: [Habit] = []
    @Published private(set) var weekDates: [Date] = []
    @Published private(set) var statuses: [HabitWeekStatus] = []

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
        habits = store.habits
        statuses = habits.map { habit in
            let recordsDictionary = store.habitRecords.reduce(into: [Date: HabitRecord]()) { partialResult, record in
                guard record.habitID == habit.id else { return }
                partialResult[record.date.startOfDay] = record
            }
            return HabitWeekStatus(habit: habit, dates: weekDates, records: recordsDictionary)
        }
    }

    func toggle(habit: Habit, on date: Date) {
        store.toggleHabit(habit.id, on: date)
    }

    func addHabit(_ habit: Habit) {
        store.addHabit(habit)
    }

    func updateHabit(_ habit: Habit) {
        store.updateHabit(habit)
    }
}
