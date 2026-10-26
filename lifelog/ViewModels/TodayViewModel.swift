//
//  TodayViewModel.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import Combine
import SwiftUI
import EventKit

@MainActor
final class TodayViewModel: ObservableObject {

    struct DailyHabitStatus: Identifiable, Equatable {
        let habit: Habit
        let record: HabitRecord?
        let currentStreak: Int

        init(habit: Habit, record: HabitRecord?, currentStreak: Int = 0) {
            self.habit = habit
            self.record = record
            self.currentStreak = currentStreak
        }

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
    private struct RefreshScope: OptionSet {
        let rawValue: Int
        static let tasks = Self(rawValue: 1 << 0)
        static let events = Self(rawValue: 1 << 1)
        static let habits = Self(rawValue: 1 << 2)
        static let health = Self(rawValue: 1 << 3)
        static let diary = Self(rawValue: 1 << 4)
        static let memo = Self(rawValue: 1 << 5)
        static let all: Self = [.tasks, .events, .habits, .health, .diary, .memo]
    }
    private var pendingRefresh: RefreshScope = []
    private var refreshIsScheduled = false
    private var calendarAtLastHabitRefresh = Calendar.current

    // Match AppDataStore's workaround for isolated teardown on iOS 26.1.
    nonisolated deinit {}

    init(store: AppDataStore, date: Date = Date(), calendarService: CalendarEventService? = nil) {
        self.store = store
        self.date = date
        self.calendarService = calendarService ?? CalendarEventService()
        bind()
        refreshAll(scope: .all)
    }

    // MARK: - Bindings

    private func bind() {
        // docs/requirements.md §Today: update only sections whose inputs changed.
        // In particular, typing in Memo must not rebuild tasks, habit history or
        // the timeline. @Published emits before assignment, so defer store reads.
        observe(store.$tasks, refreshing: .tasks)
        observe(store.$calendarEvents, refreshing: .events)
        observe(store.$externalCalendarEvents, refreshing: .events)
        observe(store.$habits, refreshing: .habits)
        store.habitRecordChanges
            .sink { [weak self] change in
                guard let self else { return }
                switch change {
                case .reset:
                    self.scheduleRefresh(for: .habits)
                case let .completion(habitID, day):
                    self.refreshHabit(habitID, on: day)
                }
            }
            .store(in: &cancellables)
        observe(store.$healthSummaries, refreshing: .health)
        observe(store.$diaryEntries, refreshing: .diary)
        observe(store.$memoPad, refreshing: .memo)
        observe($date, refreshing: .all)
        CategoryPalette.changes
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private func observe<P: Publisher>(_ publisher: P, refreshing scope: RefreshScope)
    where P.Output: Equatable, P.Failure == Never {
        publisher
            .removeDuplicates()
            .dropFirst() // init supplies the first snapshot synchronously.
            .sink { [weak self] _ in self?.scheduleRefresh(for: scope) }
            .store(in: &cancellables)
    }

    private func scheduleRefresh(for scope: RefreshScope) {
        pendingRefresh.formUnion(scope)
        guard !refreshIsScheduled else { return }
        refreshIsScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let scope = self.pendingRefresh
            self.pendingRefresh = []
            self.refreshIsScheduled = false
            self.refreshAll(scope: scope)
        }
    }

    private func refreshAll(scope: RefreshScope) {
        let updates = {
            var timelineChanged = false
            if scope.contains(.memo), self.memoPad != self.store.memoPad {
                self.memoPad = self.store.memoPad
            }
            if scope.contains(.events) {
                let events = self.mergedEvents(on: self.date)
                if self.events != events {
                    self.events = events
                    timelineChanged = true
                }
            }
            if scope.contains(.tasks) {
                let pending = self.store.tasks
                    .filter { !$0.isCompleted && TaskPresentation.isScheduled($0, on: self.date) }
                    .sorted(by: self.sortTasks)
                // Completion date falls back to the deadline for legacy tasks.
                let today = Calendar.current.startOfDay(for: self.date)
                let completed = self.store.tasks.filter { task in
                    guard task.isCompleted else { return false }
                    let completionDate = task.completedAt ?? task.endDate ?? Date()
                    return Calendar.current.startOfDay(for: completionDate) == today
                }.sorted(by: self.sortTasks)
                if self.tasksDueToday != pending {
                    self.tasksDueToday = pending
                    timelineChanged = true
                }
                if self.completedTasksToday != completed {
                    self.completedTasksToday = completed
                    timelineChanged = true
                }
            }
            if scope.contains(.habits) {
                self.calendarAtLastHabitRefresh = .current
                let records = self.store.firstHabitRecords(on: self.date)
                let statuses = self.store.habits
                    .filter { !$0.isArchived && $0.schedule.isActive(on: self.date) }
                    .map { self.habitStatus(for: $0, record: records[$0.id], calendar: self.calendarAtLastHabitRefresh) }
                if self.habitStatuses != statuses { self.habitStatuses = statuses }
            }
            if scope.contains(.health) {
                let summary = self.store.healthSummaries.first { Calendar.current.isDate($0.date, inSameDayAs: self.date) }
                if self.healthSummary != summary {
                    self.healthSummary = summary
                    timelineChanged = true
                }
            }
            if scope.contains(.diary) {
                let entry = self.store.entry(for: self.date)
                if self.diaryEntry != entry { self.diaryEntry = entry }
            }
            if timelineChanged || scope == .all {
                let items = self.buildTimelineItems()
                if self.timelineItems != items { self.timelineItems = items }
            }
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

    /// Home checkbox feedback stays local to the changed row (§4.1/§6).
    private func refreshHabit(_ habitID: UUID, on day: Date) {
        let calendar = Calendar.current
        // A timezone/calendar change can add or remove scheduled rows.
        guard calendarAtLastHabitRefresh == calendar else {
            refreshAll(scope: .habits)
            return
        }
        // Earlier edits can extend or break the displayed day's streak, while
        // the checkbox still represents the displayed day (§4.1/§4.6).
        guard calendar.startOfDay(for: day) <= calendar.startOfDay(for: date),
              let index = habitStatuses.firstIndex(where: { $0.habit.id == habitID }) else { return }
        let habit = store.habits.first { $0.id == habitID } ?? habitStatuses[index].habit
        let updated = habitStatus(for: habit,
                                  record: store.firstHabitRecord(for: habitID, on: date),
                                  calendar: calendar)
        if habitStatuses[index] != updated { habitStatuses[index] = updated }
    }

    private func habitStatus(for habit: Habit, record: HabitRecord?, calendar: Calendar) -> DailyHabitStatus {
        // Reuse the shared day index and the Habits tab's schedule-aware rule.
        // Each checkbox edit recalculates only its own habit's current streak.
        let streak = HabitsViewModel.calculateCurrentStreak(
            for: habit,
            asOf: calendar.startOfDay(for: date),
            records: store.latestHabitRecords(for: habit.id),
            calendar: calendar
        )
        return DailyHabitStatus(habit: habit, record: record, currentStreak: streak)
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

    func syncExternalCalendarsIfNeeded(
        force: Bool = false,
        anchorDate: Date? = nil,
        allowPermissionPrompt: Bool = false
    ) async {
        guard !PersistenceController.isSimulatorDemoMode else { return }
        let calendar = Calendar.current
        let anchor = anchorDate ?? date
        guard ExternalCalendarSyncPolicy.shouldSync(anchor: anchor,
                                                    storedRange: store.currentExternalCalendarRange(),
                                                    lastSyncDate: store.lastCalendarSyncDate,
                                                    calendar: calendar,
                                                    force: force) else { return }
        let desiredRange = ExternalCalendarSyncPolicy.desiredRange(for: anchor, calendar: calendar)

        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined && allowPermissionPrompt == false {
            return
        }

        let granted = await calendarService.requestAccessIfNeeded(shouldPrompt: allowPermissionPrompt)
        guard granted else {
            await MainActor.run {
                self.calendarAccessDenied = true
            }
            return
        }

        do {
            calendarService.refreshCalendarLinks(store: store)
            let ekEvents = try await calendarService.fetchEvents(from: desiredRange.start, to: desiredRange.end)
            let external = ExternalCalendarEventMapper(links: store.appState.calendarCategoryLinks).map(ekEvents)
            await MainActor.run {
                self.calendarAccessDenied = false
                self.store.updateExternalCalendarEvents(external, range: desiredRange)
                self.store.updateLastCalendarSync(date: Date())
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
                               detail: nil,
                               eventDetail: nil,
                               isAllDay: false))
        }

        items.append(contentsOf: events.map {
            JournalViewModel.TimelineItem(sourceId: $0.id,
                                          title: $0.title,
                                          start: $0.displayStartDate(),
                                          end: $0.displayEndDate(),
                                          kind: .event,
                                          detail: $0.calendarName,
                                          eventDetail: $0.detail,
                                          isAllDay: $0.isAllDay)
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
                                                 detail: detail,
                                                 eventDetail: nil,
                                                 isAllDay: false)
        }
        items.append(contentsOf: taskItems)
        
        return items.sorted(by: { $0.start < $1.start })
    }

    private func sortTasks(_ lhs: Task, _ rhs: Task) -> Bool {
        TaskPresentation.orderedBefore(lhs, rhs, preferring: .start)
    }

    private func timelineAnchor(for task: Task, defaultingTo date: Date) -> Date {
        TaskPresentation.displayDate(for: task, preferring: .start) ?? date
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
