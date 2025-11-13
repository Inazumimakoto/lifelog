//
//  TodayViewModel.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import Combine

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
    @Published private(set) var habitStatuses: [DailyHabitStatus] = []
    @Published private(set) var healthSummary: HealthSummary?
    @Published private(set) var diaryEntry: DiaryEntry?
    @Published private(set) var timelineItems: [JournalViewModel.TimelineItem] = []

    private let store: AppDataStore
    private var cancellables = Set<AnyCancellable>()

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
        events = store.events(on: date)
        tasksDueToday = store.tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            let calendar = Calendar.current
            let dueStart = dueDate.startOfDay
            let targetStart = date.startOfDay
            return dueStart <= targetStart && task.isCompleted == false
        }
        .sorted { lhs, rhs in
            if lhs.priority.rawValue != rhs.priority.rawValue {
                return lhs.priority.rawValue > rhs.priority.rawValue
            }
            return (lhs.dueDate ?? Date.distantPast) < (rhs.dueDate ?? Date.distantPast)
        }

        habitStatuses = store.habits
            .filter { $0.schedule.isActive(on: date) }
            .map { habit in
                DailyHabitStatus(habit: habit,
                                 record: store.habitRecords.first {
                                    $0.habitID == habit.id && Calendar.current.isDate($0.date, inSameDayAs: date)
                                 })
        }

        healthSummary = store.healthSummaries.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
        diaryEntry = store.entry(for: date)
        timelineItems = buildTimelineItems()
    }

    // MARK: - Actions

    func toggleTask(_ task: Task) {
        store.toggleTaskCompletion(task.id)
    }

    func toggleHabit(_ habit: Habit) {
        store.toggleHabit(habit.id, on: date)
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

    private func buildTimelineItems() -> [JournalViewModel.TimelineItem] {
        var items: [JournalViewModel.TimelineItem] = []
        items.append(contentsOf: events.map {
            JournalViewModel.TimelineItem(title: $0.title,
                                          start: $0.startDate,
                                          end: $0.endDate,
                                          kind: .event,
                                          detail: $0.calendarName)
        })

        for task in tasksDueToday {
            guard let due = task.dueDate ?? Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) else { continue }
            let start = due.addingTimeInterval(-900)
            items.append(JournalViewModel.TimelineItem(title: task.title,
                                                       start: start,
                                                       end: due,
                                                       kind: .task,
                                                       detail: task.detail))
        }
        return items.sorted(by: { $0.start < $1.start })
    }
}
