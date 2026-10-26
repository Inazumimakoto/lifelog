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

    struct CalendarDay: Identifiable, Equatable {
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

    struct TimelineItem: Identifiable, Equatable {
        enum ItemKind: String {
            case event
            case task
            case sleep
        }

        // Keep event/task identity tied to source data and distinguish sleep stages
        // that share the same interval across multiple health summaries.
        var id: String {
            let sourceIdentity = identitySource ?? sourceId?.uuidString
                ?? "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)"
            return "\(kind.rawValue)-\(sourceIdentity)"
        }
        let sourceId: UUID?
        let title: String
        let start: Date
        let end: Date
        let kind: ItemKind
        let detail: String?
        let eventDetail: String?
        let isAllDay: Bool
        var identitySource: String? = nil
    }

    enum DisplayMode: String, CaseIterable, Identifiable {
        case week = "週"
        case month = "月"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .week: return String(localized: "週")
            case .month: return String(localized: "月")
            }
        }
    }

    @Published private(set) var days: [CalendarDay] = []
    @Published var selectedDate: Date
    @Published private(set) var monthTitle: String = ""
    @Published var displayMode: DisplayMode = .month
    @Published private(set) var monthAnchor: Date
    @Published private(set) var calendarAccessDenied: Bool = false
    @Published private(set) var weekStart: CalendarWeekStart
    @Published private(set) var dataRevision: UInt = 0

    var displayCalendar: Calendar { weekStart.applying(to: baseCalendar) }

    private let store: AppDataStore
    private let calendarService: CalendarEventService
    private let baseCalendar: Calendar
    private var cancellables = Set<AnyCancellable>()
    private var monthCache: [Date: [CalendarDay]] = [:]
    private var tasksByDayCache: [Date: [Task]]?
    // These are implementation caches, never SwiftUI state. Populating them
    // while a page renders must not trigger another view update.
    private var detailSnapshotCache: [Date: CalendarDetailSnapshot] = [:]
    private var timelineItemsCache: [Date: [TimelineItem]] = [:]
    private struct CalendarCacheContext: Equatable {
        let displayIdentifier: Calendar.Identifier
        let displayTimeZone: TimeZone
        let currentIdentifier: Calendar.Identifier
        let currentTimeZone: TimeZone

        init(displayCalendar: Calendar, currentCalendar: Calendar) {
            displayIdentifier = displayCalendar.identifier
            displayTimeZone = TimeZone(identifier: displayCalendar.timeZone.identifier) ?? displayCalendar.timeZone
            currentIdentifier = currentCalendar.identifier
            currentTimeZone = TimeZone(identifier: currentCalendar.timeZone.identifier) ?? currentCalendar.timeZone
        }
    }
    private var calendarCacheContext: CalendarCacheContext?
    private var calendarCacheNeedsRebuild = false

    // Match AppDataStore's workaround for isolated teardown on iOS 26.1.
    nonisolated deinit {}

    init(store: AppDataStore,
         anchorDate: Date = Date(),
         calendarService: CalendarEventService? = nil,
         weekStart: CalendarWeekStart? = nil,
         baseCalendar: Calendar = .autoupdatingCurrent) {
        self.store = store
        self.calendarService = calendarService ?? CalendarEventService()
        self.baseCalendar = baseCalendar
        self.weekStart = weekStart ?? .current
        self.monthAnchor = anchorDate.startOfDay
        self.selectedDate = anchorDate.startOfDay
        bind()
        rebuild()
    }

    /// docs/ui-guidelines.md §カレンダー: keep the same date while changing the first column.
    func updateWeekStart(_ newValue: CalendarWeekStart) {
        guard weekStart != newValue else { return }
        weekStart = newValue
        monthCache.removeAll()
        tasksByDayCache = nil
        detailSnapshotCache.removeAll()
        timelineItemsCache.removeAll()
        rebuild(keepingSelection: true)
    }

    private func bind() {
        // Palette edits change presentation, not cached calendar data.
        CategoryPalette.changes
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // @Published sends its new value before storage changes. Invalidate the
        // deadline index synchronously so a redraw cannot observe an old snapshot.
        store.$tasks
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.tasksByDayCache = nil }
            .store(in: &cancellables)

        let calendarSources = store.$tasks.removeDuplicates()
            .combineLatest(store.$diaryEntries.removeDuplicates(),
                           store.$calendarEvents.removeDuplicates())
        let detailSources = store.$externalCalendarEvents.removeDuplicates()
            .combineLatest(store.$habits.removeDuplicates(), store.$healthSummaries.removeDuplicates())
        calendarSources
            .combineLatest(detailSources)
            .dropFirst() // init already builds the first month.
            .debounce(for: .zero, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.invalidateCalendarData()
            }
            .store(in: &cancellables)

        // docs/requirements.md §Today/Calendar: a checkbox changes one day.
        // The store publishes this event after updating its indexes, unlike
        // @Published's willSet emission. Do not debounce away rapid checks.
        store.habitRecordChanges
            .sink { [weak self] change in
                guard let self else { return }
                switch change {
                case .reset:
                    self.invalidateCalendarData()
                case let .completion(habitID, day):
                    self.updateHabitCompletion(habitID: habitID, on: day)
                }
            }
            .store(in: &cancellables)
    }

    private func invalidateCalendarData() {
        // Memo, shopping, letters and appState must not evict these caches.
        clearCalendarCaches()
        calendarCacheContext = CalendarCacheContext(displayCalendar: displayCalendar, currentCalendar: .current)
        calendarCacheNeedsRebuild = false
        dataRevision &+= 1
        rebuild(keepingSelection: true)
    }

    private func clearCalendarCaches() {
        monthCache.removeAll()
        tasksByDayCache = nil
        detailSnapshotCache.removeAll()
        timelineItemsCache.removeAll()
    }

    private func refreshCalendarCacheContext() {
        let context = CalendarCacheContext(displayCalendar: displayCalendar, currentCalendar: .current)
        if let previous = calendarCacheContext, previous != context {
            // Stored Date keys use the former day boundaries after a system
            // calendar/timezone change. Getter cache maintenance stays silent.
            clearCalendarCaches()
            calendarCacheNeedsRebuild = true
        }
        calendarCacheContext = context
    }

    private func sharesCurrentDayBoundaries(_ calendar: Calendar) -> Bool {
        let current = Calendar.current
        return calendar.identifier == current.identifier && calendar.timeZone == current.timeZone
    }

    private func updateHabitCompletion(habitID: UUID, on date: Date) {
        refreshCalendarCacheContext()
        // The store signal names a day in Calendar.current. An injected display
        // calendar may split that day across two grid cells, so rebuild it using
        // its original grouping semantics instead of guessing which cell changed.
        guard !calendarCacheNeedsRebuild, sharesCurrentDayBoundaries(displayCalendar) else {
            invalidateCalendarData()
            return
        }
        let day = Calendar.current.startOfDay(for: date)
        let records = store.records(for: day)
        var updatedContent = false

        // A date may also appear in the trailing/leading cells of a neighbor
        // month. Update every cached copy without rebuilding other days.
        for month in Array(monthCache.keys) {
            guard var cachedDays = monthCache[month],
                  let index = cachedDays.firstIndex(where: { $0.date.startOfDay == day }),
                  cachedDays[index].habits != records else { continue }
            cachedDays[index] = replacingHabits(in: cachedDays[index], with: records)
            monthCache[month] = cachedDays
            updatedContent = true
        }

        if let snapshot = detailSnapshotCache[day] {
            let record = store.firstHabitRecord(for: habitID, on: day)
            let statuses = snapshot.habitStatuses.map { status in
                status.habit.id == habitID
                    ? TodayViewModel.DailyHabitStatus(habit: status.habit, record: record)
                    : status
            }
            if statuses != snapshot.habitStatuses {
                detailSnapshotCache[day] = CalendarDetailSnapshot(
                    date: snapshot.date,
                    events: snapshot.events,
                    pendingTasks: snapshot.pendingTasks,
                    completedTasks: snapshot.completedTasks,
                    habitStatuses: statuses,
                    healthSummary: snapshot.healthSummary,
                    diaryEntry: snapshot.diaryEntry
                )
                updatedContent = true
            }
        }

        if let index = days.firstIndex(where: { $0.date.startOfDay == day }),
           days[index].habits != records {
            var updatedDays = days
            updatedDays[index] = replacingHabits(in: updatedDays[index], with: records)
            days = updatedDays
            updatedContent = true
        }

        // Pager pages read implementation caches directly; publish only after
        // all cached copies agree. Task and timeline indexes remain reusable.
        // The detail panel can still hold a selected snapshot after the bounded
        // cache evicts it. It must redraw even when no cached grid contains day.
        if updatedContent || selectedDate.startOfDay == day { dataRevision &+= 1 }
    }

    private func replacingHabits(in day: CalendarDay, with records: [HabitRecord]) -> CalendarDay {
        CalendarDay(date: day.date,
                    isWithinDisplayedMonth: day.isWithinDisplayedMonth,
                    tasks: day.tasks,
                    events: day.events,
                    habits: records,
                    diary: day.diary)
    }

    private func rebuild(keepingSelection: Bool = false) {
        // キャッシュはデータ変更時のみクリア（ページ切替時は保持）
        let title = DateFormatter.monthAndYear.string(from: monthAnchor)
        if monthTitle != title { monthTitle = title }
        let calendarDays = calendarDays(for: monthAnchor)
        if days != calendarDays { days = calendarDays }
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
        refreshCalendarCacheContext()
        let calendar = displayCalendar
        return indexedTasksByDay(calendar: calendar)[calendar.startOfDay(for: date)] ?? []
    }

    private func indexedTasksByDay(calendar: Calendar) -> [Date: [Task]] {
        if tasksByDayCache == nil {
            // Month preloading and weekly cells share the same deadline index.
            var grouped: [Date: [Task]] = [:]
            for task in store.tasks {
                guard let endDate = TaskPresentation.displayDate(for: task, preferring: .deadline, calendar: calendar) else { continue }
                grouped[calendar.startOfDay(for: endDate), default: []].append(task)
            }
            tasksByDayCache = grouped
        }
        return tasksByDayCache ?? [:]
    }
    
    /// 開始日〜終了日の範囲内にあるタスクを取得（詳細シート用）
    func tasksInRange(on date: Date) -> [Task] {
        let calendar = Calendar.current
        return store.tasks.filter { TaskPresentation.isScheduled($0, on: date, calendar: calendar) }
    }

    func habits(on date: Date) -> [HabitRecord] {
        store.records(for: date)
    }

    func timelineItems(for date: Date) -> [TimelineItem] {
        refreshCalendarCacheContext()
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        if let cached = timelineItemsCache[dayStart] { return cached }
        var items: [TimelineItem] = []
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        // Find all sleep stages that overlap with the given date
        for summary in store.healthSummaries {
            // 睡眠ステージを結合して表示（断片化を防ぐ）
            // Historical summaries rarely intersect this day. Avoid sorting
            // every night's stages for each of the weekly pager's day columns.
            let sortedStages = summary.sleepStages
                .filter { $0.start < dayEnd && $0.end > dayStart }
                .sorted { $0.start < $1.start }
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
            
            for (stageIndex, stage) in mergedStages.enumerated() {
                items.append(TimelineItem(sourceId: nil,
                                          title: "睡眠",
                                          start: stage.start,
                                          end: stage.end,
                                          kind: .sleep,
                                          detail: nil,
                                          eventDetail: nil,
                                          isAllDay: false,
                                          identitySource: "\(summary.id.uuidString)-\(stageIndex)"))
            }
        }

        // Find all events that overlap with the given date
        for event in store.events(on: date) {
            if EventQuerying.overlaps(event, rangeStart: dayStart, rangeEndExclusive: dayEnd, calendar: calendar) {
                items.append(TimelineItem(sourceId: event.id,
                                          title: event.title,
                                          start: event.displayStartDate(calendar: calendar),
                                          end: event.displayEndDate(calendar: calendar),
                                          kind: .event,
                                          detail: event.calendarName,
                                          eventDetail: event.detail,
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
                                      eventDetail: nil,
                                      isAllDay: false))
        }
        let result = items.sorted(by: { $0.start < $1.start })
        // Keep enough for the 17-page weekly pager while bounding long sessions.
        if timelineItemsCache.count >= 128,
           let farthest = timelineItemsCache.keys.max(by: {
               abs($0.timeIntervalSince(dayStart)) < abs($1.timeIntervalSince(dayStart))
           }) {
            timelineItemsCache.removeValue(forKey: farthest)
        }
        timelineItemsCache[dayStart] = result
        return result
    }

    func calendarDetailSnapshot(for date: Date) -> CalendarDetailSnapshot {
        refreshCalendarCacheContext()
        let day = Calendar.current.startOfDay(for: date)
        if let cached = detailSnapshotCache[day] { return cached }
        let tasks = tasksInRange(on: date).sorted { TaskPresentation.orderedBefore($0, $1, preferring: .start) }
        let records = store.firstHabitRecords(on: date)
        let statuses = store.habits
            .filter { !$0.isArchived && $0.schedule.isActive(on: date) }
            .map { TodayViewModel.DailyHabitStatus(habit: $0, record: records[$0.id]) }
        let snapshot = CalendarDetailSnapshot(
            date: date,
            events: store.events(on: date),
            pendingTasks: tasks.filter { !$0.isCompleted },
            completedTasks: tasks.filter(\.isCompleted),
            habitStatuses: statuses,
            healthSummary: store.healthSummaries.first { Calendar.current.isDate($0.date, inSameDayAs: date) },
            diaryEntry: store.entry(for: date)
        )
        if detailSnapshotCache.count >= 64,
           let farthest = detailSnapshotCache.keys.max(by: {
               abs($0.timeIntervalSince(day)) < abs($1.timeIntervalSince(day))
           }) {
            detailSnapshotCache.removeValue(forKey: farthest)
        }
        detailSnapshotCache[day] = snapshot
        return snapshot
    }

    func syncExternalCalendarsIfNeeded(
        force: Bool = false,
        anchorDate: Date? = nil,
        allowPermissionPrompt: Bool = false
    ) async {
        guard !PersistenceController.isSimulatorDemoMode else { return }
        let calendar = Calendar.current
        let anchor = anchorDate ?? monthAnchor
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
            calendarAccessDenied = true
            return
        }

        do {
            calendarService.refreshCalendarLinks(store: store)
            let ekEvents = try await calendarService.fetchEvents(from: desiredRange.start, to: desiredRange.end)
            let external = ExternalCalendarEventMapper(links: store.appState.calendarCategoryLinks).map(ekEvents)
            store.updateExternalCalendarEvents(external, range: desiredRange)
            store.updateLastCalendarSync(date: Date())
            calendarAccessDenied = false
        } catch {
            // Ignore errors
        }
    }

    var weekDates: [Date] {
        Self.weekDates(containing: selectedDate, calendar: displayCalendar)
    }

    nonisolated static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    nonisolated static func weekDates(containing date: Date, calendar: Calendar) -> [Date] {
        let start = startOfWeek(containing: date, calendar: calendar)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    nonisolated static func leadingDays(for monthStart: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
    }

    func calendarDays(for anchor: Date) -> [CalendarDay] {
        refreshCalendarCacheContext()
        let calendar = displayCalendar
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)) ?? anchor
        if let cached = monthCache[monthStart] {
            return cached
        }
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else {
            return []
        }

        let firstDay = monthStart
        var tempDays: [CalendarDay] = []
        let leadingDays = Self.leadingDays(for: firstDay, calendar: calendar)
        let totalDays = range.count
        let totalCells = leadingDays + totalDays
        let targetCells = ((totalCells + 6) / 7) * 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: firstDay) ?? firstDay
        let gridEnd = calendar.date(byAdding: .day, value: targetCells - leadingDays - 1, to: firstDay) ?? firstDay
        let gridEndNext = calendar.date(byAdding: .day, value: 1, to: gridEnd) ?? gridEnd

        var eventsByDay: [Date: [CalendarEvent]] = [:]
        let allEvents = store.calendarEvents + store.externalCalendarEvents
        if gridStart <= gridEnd {
            for event in EventQuerying.overlapping(allEvents, rangeStart: gridStart, rangeEndExclusive: gridEndNext, calendar: calendar) {
                let eventStartDay = calendar.startOfDay(for: event.displayStartDate(calendar: calendar))
                let end = event.displayEndDate(calendar: calendar)
                let adjustedEnd = calendar.date(byAdding: .second, value: -1, to: end) ?? end
                let eventEndDay = calendar.startOfDay(for: adjustedEnd)
                var day = max(eventStartDay, gridStart)
                let lastDay = min(eventEndDay, gridEnd)
                while day <= lastDay {
                    eventsByDay[day, default: []].append(event)
                    guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    day = nextDay
                }
            }
        }

        let tasksByDay = indexedTasksByDay(calendar: calendar)

        let useIndexedHabitRecords = sharesCurrentDayBoundaries(calendar)
        var habitsByDay: [Date: [HabitRecord]] = [:]
        if !useIndexedHabitRecords {
            for record in store.habitRecords {
                let day = calendar.startOfDay(for: record.date)
                if day >= gridStart && day <= gridEnd {
                    habitsByDay[day, default: []].append(record)
                }
            }
        }

        var diaryByDay: [Date: DiaryEntry] = [:]
        for entry in store.diaryEntries {
            let day = calendar.startOfDay(for: entry.date)
            if day >= gridStart && day <= gridEnd {
                diaryByDay[day] = entry
            }
        }

        for offset in 0..<targetCells {
            guard let date = calendar.date(byAdding: .day, value: offset - leadingDays, to: firstDay) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            let isWithinMonth = calendar.isDate(date, equalTo: anchor, toGranularity: .month)
            let events = eventsByDay[dayStart] ?? []
            let tasks = tasksByDay[dayStart] ?? []
            let records = useIndexedHabitRecords ? store.records(for: date) : habitsByDay[dayStart] ?? []
            let diary = diaryByDay[dayStart]
            tempDays.append(.init(date: date,
                                  isWithinDisplayedMonth: isWithinMonth,
                                  tasks: tasks,
                                  events: events,
                                  habits: records,
                                  diary: diary))
        }

        if monthCache.count >= 24,
           let farthest = monthCache.keys.max(by: {
               abs($0.timeIntervalSince(monthStart)) < abs($1.timeIntervalSince(monthStart))
           }) {
            monthCache.removeValue(forKey: farthest)
        }
        monthCache[monthStart] = tempDays
        return tempDays
    }

    func preloadMonths(around anchor: Date, radius: Int = 1) {
        let calendar = displayCalendar
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
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("yM")
        return formatter
    }()
}
