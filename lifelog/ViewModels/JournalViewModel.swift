//
//  JournalViewModel.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import Combine
import EventKit

@MainActor
final class JournalViewModel: ObservableObject {

    struct CalendarDay: Identifiable {
        var id: Date { date }
        let date: Date
        let isWithinDisplayedMonth: Bool
        let tasks: [Task]
        let events: [CalendarEvent]
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
        let sourceId: UUID?
        let title: String
        let start: Date
        let end: Date
        let kind: ItemKind
        let detail: String?
        let isAllDay: Bool
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
    @Published private(set) var calendarAccessDenied: Bool = false

    private let store: AppDataStore
    private let calendarService: CalendarEventService
    private var cancellables = Set<AnyCancellable>()
    private var monthCache: [Date: [CalendarDay]] = [:]

    init(store: AppDataStore, anchorDate: Date = Date(), calendarService: CalendarEventService? = nil) {
        self.store = store
        self.calendarService = calendarService ?? CalendarEventService()
        self.monthAnchor = anchorDate.startOfDay
        self.selectedDate = anchorDate.startOfDay
        bind()
        rebuild()
    }

    private func bind() {
        store.$tasks
            .combineLatest(store.$habitRecords, store.$diaryEntries, store.$calendarEvents)
            .combineLatest(store.$externalCalendarEvents)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuild()
            }
            .store(in: &cancellables)
    }

    private func rebuild(keepingSelection: Bool = false) {
        monthCache.removeAll()
        monthTitle = DateFormatter.monthAndYear.string(from: monthAnchor)
        let calendarDays = calendarDays(for: monthAnchor)
        days = calendarDays
        guard keepingSelection == false else { return }
        if calendarDays.contains(where: { $0.date.startOfDay == selectedDate.startOfDay }) == false {
            selectedDate = calendarDays.first(where: { $0.isWithinDisplayedMonth })?.date ?? monthAnchor
        }
    }

    func goToPreviousMonth() {
        guard let previous = Calendar.current.date(byAdding: .month, value: -1, to: monthAnchor) else { return }
        monthAnchor = previous
        rebuild(keepingSelection: true)
    }

    func goToNextMonth() {
        guard let next = Calendar.current.date(byAdding: .month, value: 1, to: monthAnchor) else { return }
        monthAnchor = next
        rebuild(keepingSelection: true)
    }

    func setMonthAnchor(_ date: Date) {
        let calendar = Calendar.current
        let newAnchor = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        if calendar.isDate(newAnchor, equalTo: monthAnchor, toGranularity: .month) == false {
            monthAnchor = newAnchor
            rebuild(keepingSelection: true)
        }
    }

    func stepBackward(displayMode: DisplayMode) {
        HapticManager.light()
        switch displayMode {
        case .month:
            goToPreviousMonth()
        case .week:
            selectedDate = Calendar.current.date(byAdding: .day, value: -7, to: selectedDate) ?? selectedDate
        }
    }

    func stepForward(displayMode: DisplayMode) {
        HapticManager.light()
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
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        // Find all sleep stages that overlap with the given date
        for summary in store.healthSummaries {
            // 睡眠ステージを結合して表示（断片化を防ぐ）
            let sortedStages = summary.sleepStages.sorted { $0.start < $1.start }
            var mergedStages: [(start: Date, end: Date)] = []
            
            for stage in sortedStages {
                // 前回の終了時間から2時間以内なら結合する
                if let last = mergedStages.last, 
                   stage.start.timeIntervalSince(last.end) < 7200,
                   stage.start < dayEnd && stage.end > dayStart {
                    mergedStages[mergedStages.count - 1].end = max(last.end, stage.end)
                } else if stage.start < dayEnd && stage.end > dayStart {
                    // 新しいブロック
                    mergedStages.append((stage.start, stage.end))
                }
            }
            
            for stage in mergedStages {
                items.append(TimelineItem(sourceId: nil,
                                          title: "睡眠",
                                          start: stage.start,
                                          end: stage.end,
                                          kind: .sleep,
                                          detail: nil,
                                          isAllDay: false))
            }
        }

        // Find all events that overlap with the given date
        for event in store.events(on: date) {
            if event.startDate < dayEnd && event.endDate > dayStart {
                items.append(TimelineItem(sourceId: event.id,
                                          title: event.title,
                                          start: event.startDate,
                                          end: event.endDate,
                                          kind: .event,
                                          detail: event.calendarName,
                                          isAllDay: event.isAllDay))
            }
        }

        for task in tasks(on: date) {
            let anchor = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
            let start = anchor.addingTimeInterval(-1800)
            items.append(TimelineItem(sourceId: task.id,
                                      title: task.title,
                                      start: start,
                                      end: anchor,
                                      kind: .task,
                                      detail: task.detail,
                                      isAllDay: false))
        }
        return items.sorted(by: { $0.start < $1.start })
    }

    func syncExternalCalendarsIfNeeded() async {
        let needsFirstLoadThisRun = calendarService.hasLoadedExternalEventsThisRun == false || store.externalCalendarEvents.isEmpty
        let today = Calendar.current.startOfDay(for: Date())
        if needsFirstLoadThisRun == false,
           let last = store.lastCalendarSyncDate,
           Calendar.current.isDate(last, inSameDayAs: today) {
            return
        }

        let granted = await calendarService.requestAccessIfNeeded()
        guard granted else {
            calendarAccessDenied = true
            return
        }

        do {
            calendarService.refreshCalendarLinks(store: store)
            let ekEvents = try await calendarService.fetchEventsForCurrentAndNextMonth()
            let external = mapExternalEvents(from: ekEvents)
            store.updateExternalCalendarEvents(external)
            store.updateLastCalendarSync(date: Date())
            calendarService.markExternalEventsLoaded()
            calendarAccessDenied = false
        } catch {
            // Ignore errors
        }
    }

    var weekDates: [Date] {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)) ?? selectedDate
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
    }

    private func isTask(_ task: Task, on date: Date, calendar: Calendar) -> Bool {
        // カレンダーでは終了日（締切）のみに表示
        let end = calendar.startOfDay(for: task.endDate ?? task.startDate ?? date)
        let target = calendar.startOfDay(for: date)
        return end == target
    }

    private func mapExternalEvents(from ekEvents: [EKEvent]) -> [CalendarEvent] {
        let links = store.appState.calendarCategoryLinks
        let linkMap = Dictionary(uniqueKeysWithValues: links.map { ($0.calendarIdentifier, $0) })
        let defaultCategory = CategoryPalette.defaultCategoryName

        return ekEvents.compactMap { event in
            let identifier = event.calendar.calendarIdentifier
            if let link = linkMap[identifier] {
                guard let category = link.categoryId else { return nil }
                return CalendarEvent(event: event, categoryName: category)
            }
            return CalendarEvent(event: event, categoryName: defaultCategory)
        }
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
            let events = store.events(on: date)
            let tasks = store.tasks.filter { isTask($0, on: date, calendar: calendar) }
            let records = store.habitRecords.filter { $0.date.startOfDay == date.startOfDay }
            let diary = store.diaryEntries.first { $0.date.startOfDay == date.startOfDay }
            tempDays.append(.init(date: date,
                                  isWithinDisplayedMonth: isWithinMonth,
                                  tasks: tasks,
                                  events: events,
                                  habits: records,
                                  diary: diary))
        }

        let trailingDays = max(0, targetCells - (leadingDays + totalDays))
        if trailingDays > 0 {
            for offset in totalDays..<(totalDays + trailingDays) {
                guard let date = calendar.date(byAdding: .day, value: offset, to: firstDay) else { continue }
                let events = store.events(on: date)
                let tasks = store.tasks.filter { isTask($0, on: date, calendar: calendar) }
                let records = store.habitRecords.filter { $0.date.startOfDay == date.startOfDay }
                let diary = store.diaryEntries.first { $0.date.startOfDay == date.startOfDay }
                tempDays.append(.init(date: date,
                                      isWithinDisplayedMonth: false,
                                      tasks: tasks,
                                      events: events,
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
