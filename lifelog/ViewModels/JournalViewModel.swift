//
//  JournalViewModel.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import Combine

@MainActor
final class JournalViewModel: ObservableObject {

    struct CalendarDay: Identifiable {
        var id: Date { date }
        let date: Date
        let isWithinDisplayedMonth: Bool
        let tasks: [Task]
        let habits: [HabitRecord]
        let diary: DiaryEntry?

        var isToday: Bool {
            Calendar.current.isDateInToday(date)
        }
    }

    struct TimelineItem: Identifiable {
        enum ItemKind {
            case event
            case task
            case sleep
        }

        let id = UUID()
        let title: String
        let start: Date
        let end: Date
        let kind: ItemKind
        let detail: String?
    }

    enum DisplayMode: String, CaseIterable, Identifiable {
        case week = "週"
        case month = "月"

        var id: String { rawValue }
    }

    @Published private(set) var days: [CalendarDay] = []
    @Published var selectedDate: Date
    @Published private(set) var monthTitle: String = ""
    @Published var displayMode: DisplayMode = .month
    @Published private(set) var monthAnchor: Date

    private let store: AppDataStore
    private var cancellables = Set<AnyCancellable>()
    private var monthCache: [Date: [CalendarDay]] = [:]

    init(store: AppDataStore, anchorDate: Date = Date()) {
        self.store = store
        self.monthAnchor = anchorDate.startOfDay
        self.selectedDate = anchorDate.startOfDay
        bind()
        rebuild()
    }

    private func bind() {
        store.$tasks
            .combineLatest(store.$habitRecords, store.$diaryEntries, store.$calendarEvents)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _, _ in
                self?.rebuild()
            }
            .store(in: &cancellables)
    }

    private func rebuild() {
        monthCache.removeAll()
        monthTitle = DateFormatter.monthAndYear.string(from: monthAnchor)
        let calendarDays = calendarDays(for: monthAnchor)
        days = calendarDays
        if calendarDays.contains(where: { $0.date.startOfDay == selectedDate.startOfDay }) == false {
            selectedDate = calendarDays.first(where: { $0.isWithinDisplayedMonth })?.date ?? monthAnchor
        }
    }

    func goToPreviousMonth() {
        guard let previous = Calendar.current.date(byAdding: .month, value: -1, to: monthAnchor) else { return }
        monthAnchor = previous
        rebuild()
    }

    func goToNextMonth() {
        guard let next = Calendar.current.date(byAdding: .month, value: 1, to: monthAnchor) else { return }
        monthAnchor = next
        rebuild()
    }

    func stepBackward(displayMode: DisplayMode) {
        switch displayMode {
        case .month:
            goToPreviousMonth()
        case .week:
            selectedDate = Calendar.current.date(byAdding: .day, value: -7, to: selectedDate) ?? selectedDate
        }
    }

    func stepForward(displayMode: DisplayMode) {
        switch displayMode {
        case .month:
            goToNextMonth()
        case .week:
            selectedDate = Calendar.current.date(byAdding: .day, value: 7, to: selectedDate) ?? selectedDate
        }
    }

    func jumpToToday() {
        let today = Date().startOfDay
        selectedDate = today
        monthAnchor = today
        rebuild()
    }

    func alignAnchorIfNeeded(for mode: DisplayMode) {
        if mode == .month {
            monthAnchor = selectedDate.startOfDay
            rebuild()
        }
    }

    func tasks(on date: Date) -> [Task] {
        let calendar = Calendar.current
        return store.tasks.filter { isTask($0, on: date, calendar: calendar) }
    }

    func habits(on date: Date) -> [HabitRecord] {
        store.habitRecords.filter { $0.date.startOfDay == date.startOfDay }
    }

    func timelineItems(for date: Date) -> [TimelineItem] {
        var items: [TimelineItem] = []

        // Add sleep item if it exists for this day
        if let summary = store.healthSummaries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }),
           let sleepStart = summary.sleepStart,
           let sleepEnd = summary.sleepEnd {
            items.append(TimelineItem(title: "睡眠",
                                      start: sleepStart,
                                      end: sleepEnd,
                                      kind: .sleep,
                                      detail: nil))
        }

        let events = store.events(on: date)
        items.append(contentsOf: events.map {
            TimelineItem(title: $0.title,
                         start: $0.startDate,
                         end: $0.endDate,
                         kind: .event,
                         detail: $0.calendarName)
        })

        for task in tasks(on: date) {
            let anchor = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
            let start = anchor.addingTimeInterval(-1800)
            items.append(TimelineItem(title: task.title,
                                      start: start,
                                      end: anchor,
                                      kind: .task,
                                      detail: task.detail))
        }
        return items.sorted(by: { $0.start < $1.start })
    }

    var weekDates: [Date] {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)) ?? selectedDate
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
    }

    private func isTask(_ task: Task, on date: Date, calendar: Calendar) -> Bool {
        let start = calendar.startOfDay(for: task.startDate ?? task.endDate ?? date)
        let end = calendar.startOfDay(for: task.endDate ?? task.startDate ?? date)
        let target = calendar.startOfDay(for: date)
        return start...end ~= target
    }

    func calendarDays(for anchor: Date) -> [CalendarDay] {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)) ?? anchor
        if let cached = monthCache[monthStart] {
            return cached
        }
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else {
            return []
        }

        let firstDay = monthStart
        var tempDays: [CalendarDay] = []
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingDays = (firstWeekday + 6) % 7
        let totalDays = range.count
        let totalCells = leadingDays + totalDays
        let targetCells = ((totalCells + 6) / 7) * 7

        for offset in -leadingDays..<totalDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstDay) else { continue }
            let isWithinMonth = calendar.isDate(date, equalTo: anchor, toGranularity: .month)
            let tasks = store.tasks.filter { isTask($0, on: date, calendar: calendar) }
            let records = store.habitRecords.filter { $0.date.startOfDay == date.startOfDay }
            let diary = store.diaryEntries.first { $0.date.startOfDay == date.startOfDay }
            tempDays.append(.init(date: date,
                                  isWithinDisplayedMonth: isWithinMonth,
                                  tasks: tasks,
                                  habits: records,
                                  diary: diary))
        }

        let trailingDays = max(0, targetCells - (leadingDays + totalDays))
        if trailingDays > 0 {
            for offset in totalDays..<(totalDays + trailingDays) {
                guard let date = calendar.date(byAdding: .day, value: offset, to: firstDay) else { continue }
                let tasks = store.tasks.filter { isTask($0, on: date, calendar: calendar) }
                let records = store.habitRecords.filter { $0.date.startOfDay == date.startOfDay }
                let diary = store.diaryEntries.first { $0.date.startOfDay == date.startOfDay }
                tempDays.append(.init(date: date,
                                      isWithinDisplayedMonth: false,
                                      tasks: tasks,
                                      habits: records,
                                      diary: diary))
            }
        }

        monthCache[monthStart] = tempDays
        return tempDays
    }

    func preloadMonths(around anchor: Date, radius: Int = 1) {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)) ?? anchor
        for offset in -radius...radius {
            guard let date = calendar.date(byAdding: .month, value: offset, to: monthStart) else { continue }
            _ = calendarDays(for: date)
        }
    }
}

private extension DateFormatter {
    static let monthAndYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }()
}
