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
    @Published private(set) var memoPad: MemoPad = MemoPad()
    @Published private(set) var calendarAccessDenied: Bool = false

    private let store: AppDataStore
    private let calendarService: CalendarEventService
    private var cancellables = Set<AnyCancellable>()
    private var pendingAnimation: Animation?

    init(store: AppDataStore, date: Date = Date(), calendarService: CalendarEventService? = nil) {
        self.store = store
        self.date = date
        self.calendarService = calendarService ?? CalendarEventService()
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
            self.memoPad = self.store.memoPad
            self.events = self.mergedEvents(on: self.date)
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

    func syncExternalCalendarsIfNeeded() async {
        let today = Calendar.current.startOfDay(for: Date())
        if let last = store.lastCalendarSyncDate,
           Calendar.current.isDate(last, inSameDayAs: today) {
            return
        }

        let granted = await calendarService.requestAccessIfNeeded()
        guard granted else {
            await MainActor.run {
                self.calendarAccessDenied = true
            }
            return
        }

        do {
            let ekEvents = try await calendarService.fetchEventsForCurrentAndNextMonth()
            let external = ekEvents.map { CalendarEvent(event: $0) }
            await MainActor.run {
                self.calendarAccessDenied = false
                self.store.updateExternalCalendarEvents(external)
                self.store.updateLastCalendarSync(date: Date())
                self.refreshAll()
            }
        } catch {
            // Ignore errors for now; keep existing events
        }
    }

    private func buildTimelineItems() -> [JournalViewModel.TimelineItem] {
        var items: [JournalViewModel.TimelineItem] = []

        if let sleepStart = healthSummary?.sleepStart, let sleepEnd = healthSummary?.sleepEnd {
            items.append(.init(sourceId: nil,
                               title: "睡眠",
                               start: sleepStart,
                               end: sleepEnd,
                               kind: .sleep,
                               detail: nil))
        }

        items.append(contentsOf: events.map {
            JournalViewModel.TimelineItem(sourceId: $0.id,
                                          title: $0.title,
                                          start: $0.startDate,
                                          end: $0.endDate,
                                          kind: .event,
                                          detail: $0.calendarName)
        })

        let allTasks = completedTasksToday + tasksDueToday
        let taskItems = allTasks.map { task -> JournalViewModel.TimelineItem in
            let anchorDate = timelineAnchor(for: task, defaultingTo: date)
            let start = anchorDate.addingTimeInterval(-900)
            let detail = task.isCompleted ? "__completed__" : task.detail
            return JournalViewModel.TimelineItem(sourceId: task.id,
                                                 title: task.title,
                                                 start: start,
                                                 end: anchorDate,
                                                 kind: .task,
                                                 detail: detail)
        }
        items.append(contentsOf: taskItems)
        
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

    private func timelineAnchor(for task: Task, defaultingTo date: Date) -> Date {
        return task.startDate ?? task.endDate ?? date
    }

    private func mergedEvents(on date: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        let internalEvents = store.calendarEvents
            .filter { $0.startDate < dayEnd && $0.endDate > dayStart }
        let externalEvents = store.externalCalendarEvents
            .filter { $0.startDate < dayEnd && $0.endDate > dayStart }

        return (internalEvents + externalEvents)
            .sorted(by: { $0.startDate < $1.startDate })
    }
}
