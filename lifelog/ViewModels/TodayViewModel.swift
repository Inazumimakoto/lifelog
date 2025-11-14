//
//  TodayViewModel.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class TodayViewModel: ObservableObject {

    struct DailyHabitStatus: Identifiable {
        let habit: Habit
        let record: HabitRecord?

        var id: UUID { habit.id }

        var isCompleted: Bool {
            record?.isCompleted == true
        }
    }

    @Published var date: Date
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var tasksDueToday: [Task] = []
    @Published private(set) var completedTasksToday: [Task] = []
    @Published private(set) var habitStatuses: [DailyHabitStatus] = []
    @Published private(set) var healthSummary: HealthSummary?
    @Published private(set) var diaryEntry: DiaryEntry?
    @Published private(set) var timelineItems: [JournalViewModel.TimelineItem] = []

    private let store: AppDataStore
    private var cancellables = Set<AnyCancellable>()
    private var pendingAnimation: Animation?

    init(store: AppDataStore, date: Date = Date()) {
        self.store = store
        self.date = date
        bind()
        refreshAll()
    }

    // MARK: - Bindings

    private func bind() {
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshAll()
            }
            .store(in: &cancellables)
    }

    private func refreshAll() {
        let updates = {
            self.events = self.store.events(on: self.date)
            let todaysTasks = self.store.tasks
                .filter { self.isTask($0, scheduledOn: self.date) }
                .sorted(by: self.sortTasks)
            self.tasksDueToday = todaysTasks.filter { !$0.isCompleted }
            self.completedTasksToday = todaysTasks.filter(\.isCompleted)

            self.habitStatuses = self.store.habits
                .filter { $0.schedule.isActive(on: self.date) }
                .map { habit in
                    DailyHabitStatus(habit: habit,
                                     record: self.store.habitRecords.first {
                                        $0.habitID == habit.id && Calendar.current.isDate($0.date, inSameDayAs: self.date)
                                     })
                }

            self.healthSummary = self.store.healthSummaries.first { Calendar.current.isDate($0.date, inSameDayAs: self.date) }
            self.diaryEntry = self.store.entry(for: self.date)
            self.timelineItems = self.buildTimelineItems()
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

    // MARK: - Actions

    func toggleTask(_ task: Task) {
        pendingAnimation = .spring(response: 0.35, dampingFraction: 0.8)
        store.toggleTaskCompletion(task.id)
    }

    func toggleHabit(_ habit: Habit) {
        store.toggleHabit(habit.id, on: date)
    }

    func deleteTask(_ task: Task) {
        store.deleteTasks(withIDs: [task.id])
    }

    func ensureDiaryEntry() -> DiaryEntry {
        if let diaryEntry {
            return diaryEntry
        }
        let newEntry = DiaryEntry(date: date, text: "")
        store.upsert(entry: newEntry)
        return newEntry
    }

    func updateDiary(_ entry: DiaryEntry) {
        store.upsert(entry: entry)
    }

    func deleteEvent(_ event: CalendarEvent) {
        store.deleteCalendarEvent(event.id)
    }

    private func buildTimelineItems() -> [JournalViewModel.TimelineItem] {
        var items: [JournalViewModel.TimelineItem] = []
        items.append(contentsOf: events.map {
            JournalViewModel.TimelineItem(title: $0.title,
                                          start: $0.startDate,
                                          end: $0.endDate,
                                          kind: .event,
                                          detail: $0.calendarName)
        })

        let completedTimeline = completedTasksToday.map { task -> JournalViewModel.TimelineItem in
            JournalViewModel.TimelineItem(title: task.title,
                                          start: task.startDate ?? date,
                                          end: task.endDate ?? date,
                                          kind: .task,
                                          detail: "__completed__")
        }
        let pendingTimeline = tasksDueToday.map { task -> JournalViewModel.TimelineItem in
            JournalViewModel.TimelineItem(title: task.title,
                                          start: task.startDate ?? date,
                                          end: task.endDate ?? date,
                                          kind: .task,
                                          detail: task.detail)
        }
        (pendingTimeline + completedTimeline).forEach { task in
            let anchorDate = timelineAnchor(for: task, defaultingTo: date)
            let start = anchorDate.addingTimeInterval(-900)
            items.append(JournalViewModel.TimelineItem(title: task.title,
                                                       start: start,
                                                       end: anchorDate,
                                                       kind: task.kind,
                                                       detail: task.detail))
        }
        return items.sorted(by: { $0.start < $1.start })
    }

    private func isTask(_ task: Task, scheduledOn date: Date) -> Bool {
        let calendar = Calendar.current
        let start = task.startDate ?? task.endDate
        let end = task.endDate ?? task.startDate
        guard let anchor = start ?? end else { return false }
        let normalizedStart = calendar.startOfDay(for: start ?? anchor)
        let normalizedEnd = calendar.startOfDay(for: end ?? anchor)
        let target = calendar.startOfDay(for: date)
        return normalizedStart...normalizedEnd ~= target
    }

    private func sortTasks(_ lhs: Task, _ rhs: Task) -> Bool {
        if lhs.priority.rawValue != rhs.priority.rawValue {
            return lhs.priority.rawValue > rhs.priority.rawValue
        }
        let lhsDate = displayDate(for: lhs) ?? .distantFuture
        let rhsDate = displayDate(for: rhs) ?? .distantFuture
        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }
        return lhs.title < rhs.title
    }

    private func displayDate(for task: Task) -> Date? {
        task.startDate ?? task.endDate
    }

    private func timelineAnchor(for task: JournalViewModel.TimelineItem, defaultingTo date: Date) -> Date {
        task.start ?? Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }
}
