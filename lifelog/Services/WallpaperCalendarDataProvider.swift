//
//  WallpaperCalendarDataProvider.swift
//  lifelog
//
//  Created by Codex on 2026/04/27.
//

import Foundation
import SwiftData
import SwiftUI

struct WallpaperCalendarSnapshot {
    let generatedAt: Date
    let rangeStart: Date
    let rangeEndExclusive: Date
    let weekdaySymbols: [String]
    let weeks: [WallpaperCalendarWeek]
    let fingerprintPayload: WallpaperCalendarFingerprintPayload

    var dayCount: Int {
        weeks.reduce(0) { $0 + $1.days.count }
    }
}

struct WallpaperCalendarWeek: Identifiable {
    let id: Date
    let days: [WallpaperCalendarDay]
    let multiDayLayout: WallpaperCalendarWeekMultiDayLayout
}

struct WallpaperCalendarDay: Identifiable {
    var id: Date { date }
    let date: Date
    let previews: [WallpaperCalendarItem]
    let rowContents: [WallpaperCalendarCellRowContent]
}

struct WallpaperCalendarItem: Identifiable {
    enum Kind: String, Codable {
        case event
        case task
    }

    let id: String
    let sourceID: UUID
    let title: String
    let categoryName: String?
    let color: Color
    let kind: Kind
    let startDate: Date?
    let endDate: Date?
    let isAllDay: Bool
    let priority: TaskPriority?

    var isMultiDayEvent: Bool {
        guard kind == .event,
              let startDate,
              let endDate
        else {
            return false
        }
        let calendar = WallpaperCalendarDataProvider.calendar
        let adjustedEnd = calendar.date(byAdding: .second, value: -1, to: endDate) ?? endDate
        return calendar.isDate(startDate, inSameDayAs: adjustedEnd) == false
    }

    func displayTitle(privacyMode: WallpaperCalendarPrivacyMode) -> String {
        switch privacyMode {
        case .details:
            return title
        case .categoryOnly:
            if kind == .task {
                return "タスク"
            }
            return categoryName?.isEmpty == false ? categoryName! : "予定"
        case .hidden:
            return kind == .task ? "タスクあり" : "予定あり"
        }
    }
}

enum WallpaperCalendarCellRowContent {
    case empty
    case multiDayPlaceholder
    case item(WallpaperCalendarItem)
    case overflow(Int)
}

struct WallpaperCalendarDayMultiDayState {
    let visibleLaneCount: Int
    let occupiedVisibleLanes: Set<Int>
    let hiddenMultiDayCount: Int

    static let empty = WallpaperCalendarDayMultiDayState(
        visibleLaneCount: 0,
        occupiedVisibleLanes: [],
        hiddenMultiDayCount: 0
    )
}

struct WallpaperCalendarWeekMultiDaySegment: Identifiable {
    let id: String
    let eventID: UUID
    let title: String
    let categoryName: String
    let color: Color
    let lane: Int
    let startColumn: Int
    let endColumn: Int
    let continuesBeforeWeek: Bool
    let continuesAfterWeek: Bool

    func displayTitle(privacyMode: WallpaperCalendarPrivacyMode) -> String {
        switch privacyMode {
        case .details:
            return title
        case .categoryOnly:
            return categoryName.isEmpty ? "予定" : categoryName
        case .hidden:
            return "予定あり"
        }
    }
}

struct WallpaperCalendarWeekMultiDayLayout {
    let visibleLaneCount: Int
    let dayStates: [WallpaperCalendarDayMultiDayState]
    let segments: [WallpaperCalendarWeekMultiDaySegment]

    static let empty = WallpaperCalendarWeekMultiDayLayout(
        visibleLaneCount: 0,
        dayStates: Array(repeating: .empty, count: 7),
        segments: []
    )
}

struct WallpaperCalendarFingerprintPayload: Codable {
    struct Event: Codable {
        let id: UUID
        let title: String
        let start: TimeInterval
        let end: TimeInterval
        let categoryName: String
        let isAllDay: Bool
    }

    struct TaskItem: Codable {
        let id: UUID
        let title: String
        let start: TimeInterval?
        let end: TimeInterval?
        let priority: Int
        let isCompleted: Bool
    }

    let rangeStart: TimeInterval
    let rangeEndExclusive: TimeInterval
    let events: [Event]
    let tasks: [TaskItem]
}

@MainActor
final class WallpaperCalendarDataProvider {
    static let itemLimit = 4
    static let externalCalendarEventsDefaultsKey = "ExternalCalendarEvents_Storage_V1"

    nonisolated static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.firstWeekday = 1
        calendar.timeZone = .current
        return calendar
    }

    func makeSnapshot(settings: WallpaperCalendarSettings,
                      now: Date = Date()) -> WallpaperCalendarSnapshot {
        let calendar = Self.calendar
        let rangeStart = startOfWeek(containing: now, calendar: calendar)
        let weekCount = settings.effectiveWeekCount.rawValue
        let rangeEndExclusive = calendar.date(
            byAdding: .day,
            value: weekCount * 7,
            to: rangeStart
        ) ?? rangeStart

        let events = fetchEvents(from: rangeStart, to: rangeEndExclusive)
        let tasks = fetchTasks(from: rangeStart, to: rangeEndExclusive)
        let eventsByDay = eventsByDay(events, rangeStart: rangeStart, rangeEndExclusive: rangeEndExclusive, calendar: calendar)
        let tasksByDay = tasksByDay(tasks, rangeStart: rangeStart, rangeEndExclusive: rangeEndExclusive, calendar: calendar)
        let dates = dates(from: rangeStart, count: weekCount * 7, calendar: calendar)
        let weeks = buildWeeks(dates: dates, eventsByDay: eventsByDay, tasksByDay: tasksByDay, calendar: calendar)

        return WallpaperCalendarSnapshot(
            generatedAt: now,
            rangeStart: rangeStart,
            rangeEndExclusive: rangeEndExclusive,
            weekdaySymbols: sundayFirstWeekdaySymbols(calendar: calendar),
            weeks: weeks,
            fingerprintPayload: makeFingerprintPayload(
                rangeStart: rangeStart,
                rangeEndExclusive: rangeEndExclusive,
                events: events,
                tasks: tasks
            )
        )
    }

    private func fetchEvents(from rangeStart: Date, to rangeEndExclusive: Date) -> [CalendarEvent] {
        let internalEvents = fetchInternalEvents(from: rangeStart, to: rangeEndExclusive)
        let externalEvents = fetchExternalEvents(from: rangeStart, to: rangeEndExclusive)
        return (internalEvents + externalEvents)
            .reduce(into: [UUID: CalendarEvent]()) { result, event in
                if let existing = result[event.id] {
                    result[event.id] = existing.startDate <= event.startDate ? existing : event
                } else {
                    result[event.id] = event
                }
            }
            .values
            .sorted(by: sortEvents)
    }

    private func fetchInternalEvents(from rangeStart: Date, to rangeEndExclusive: Date) -> [CalendarEvent] {
        do {
            let context = PersistenceController.shared.container.mainContext
            let descriptor = FetchDescriptor<SDCalendarEvent>(
                predicate: #Predicate<SDCalendarEvent> { $0.startDate < rangeEndExclusive && $0.endDate > rangeStart },
                sortBy: [SortDescriptor(\.startDate)]
            )
            return try context.fetch(descriptor).map {
                CalendarEvent(
                    id: $0.id,
                    title: $0.title,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    calendarName: $0.calendarName,
                    isAllDay: $0.isAllDay,
                    sourceCalendarIdentifier: $0.sourceCalendarIdentifier,
                    reminderMinutes: $0.reminderMinutes,
                    reminderDate: $0.reminderDate
                )
            }
        } catch {
            return []
        }
    }

    private func fetchExternalEvents(from rangeStart: Date, to rangeEndExclusive: Date) -> [CalendarEvent] {
        let defaults = UserDefaults(suiteName: PersistenceController.appGroupIdentifier) ?? .standard
        guard let data = defaults.data(forKey: Self.externalCalendarEventsDefaultsKey),
              let events = try? JSONDecoder().decode([CalendarEvent].self, from: data)
        else {
            return []
        }
        return events
            .filter { $0.startDate < rangeEndExclusive && $0.endDate > rangeStart }
            .sorted(by: sortEvents)
    }

    private func fetchTasks(from rangeStart: Date, to rangeEndExclusive: Date) -> [Task] {
        do {
            let context = PersistenceController.shared.container.mainContext
            let descriptor = FetchDescriptor<SDTask>()
            return try context.fetch(descriptor)
                .map {
                    Task(
                        id: $0.id,
                        title: $0.title,
                        detail: $0.detail,
                        startDate: $0.startDate,
                        endDate: $0.endDate,
                        priority: $0.priority,
                        isCompleted: $0.isCompleted,
                        reminderDate: $0.reminderDate,
                        completedAt: $0.completedAt
                    )
                }
                .filter { task in
                    guard let displayDate = task.endDate ?? task.startDate else { return false }
                    let day = Self.calendar.startOfDay(for: displayDate)
                    return day >= rangeStart && day < rangeEndExclusive
                }
        } catch {
            return []
        }
    }

    private func eventsByDay(_ events: [CalendarEvent],
                             rangeStart: Date,
                             rangeEndExclusive: Date,
                             calendar: Calendar) -> [Date: [CalendarEvent]] {
        guard let rangeLastDay = calendar.date(byAdding: .day, value: -1, to: rangeEndExclusive) else {
            return [:]
        }

        var result: [Date: [CalendarEvent]] = [:]
        for event in events where event.startDate < rangeEndExclusive && event.endDate > rangeStart {
            let eventStartDay = calendar.startOfDay(for: event.startDate)
            let adjustedEnd = calendar.date(byAdding: .second, value: -1, to: event.endDate) ?? event.endDate
            let eventEndDay = max(calendar.startOfDay(for: adjustedEnd), eventStartDay)
            var day = max(eventStartDay, rangeStart)
            let lastDay = min(eventEndDay, rangeLastDay)
            while day <= lastDay {
                result[day, default: []].append(event)
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = nextDay
            }
        }
        return result
    }

    private func tasksByDay(_ tasks: [Task],
                            rangeStart: Date,
                            rangeEndExclusive: Date,
                            calendar: Calendar) -> [Date: [Task]] {
        var result: [Date: [Task]] = [:]
        for task in tasks {
            guard let displayDate = task.endDate ?? task.startDate else { continue }
            let day = calendar.startOfDay(for: displayDate)
            guard day >= rangeStart && day < rangeEndExclusive else { continue }
            result[day, default: []].append(task)
        }
        return result
    }

    private func buildWeeks(dates: [Date],
                            eventsByDay: [Date: [CalendarEvent]],
                            tasksByDay: [Date: [Task]],
                            calendar: Calendar) -> [WallpaperCalendarWeek] {
        stride(from: 0, to: dates.count, by: 7).compactMap { startIndex in
            let endIndex = min(startIndex + 7, dates.count)
            guard endIndex - startIndex == 7 else { return nil }
            let weekDates = Array(dates[startIndex..<endIndex])
            let uniqueMultiDayEvents = uniqueMultiDayEvents(weekDates: weekDates, eventsByDay: eventsByDay)
            let multiDayLayout = buildWeekMultiDayLayout(
                weekDates: weekDates,
                events: uniqueMultiDayEvents,
                itemLimit: Self.itemLimit,
                calendar: calendar
            )

            let days = weekDates.enumerated().map { index, date in
                let dayStart = calendar.startOfDay(for: date)
                let previews = dayPreviewItems(
                    events: eventsByDay[dayStart] ?? [],
                    tasks: tasksByDay[dayStart] ?? [],
                    on: dayStart
                )
                let state = multiDayLayout.dayStates.indices.contains(index) ? multiDayLayout.dayStates[index] : .empty
                let rows = calendarCellRowContents(
                    previews: previews,
                    itemLimit: Self.itemLimit,
                    multiDayState: state
                )
                return WallpaperCalendarDay(date: dayStart, previews: previews, rowContents: rows)
            }

            return WallpaperCalendarWeek(id: weekDates[0], days: days, multiDayLayout: multiDayLayout)
        }
    }

    private func uniqueMultiDayEvents(weekDates: [Date],
                                      eventsByDay: [Date: [CalendarEvent]]) -> [CalendarEvent] {
        var uniqueEvents: [UUID: CalendarEvent] = [:]
        for date in weekDates {
            let dayStart = Self.calendar.startOfDay(for: date)
            for event in eventsByDay[dayStart] ?? [] where isMultiDayEvent(event) {
                uniqueEvents[event.id] = event
            }
        }
        return Array(uniqueEvents.values)
    }

    private func dayPreviewItems(events: [CalendarEvent], tasks: [Task], on date: Date) -> [WallpaperCalendarItem] {
        let sortedEvents = events.sorted(by: sortEventsForPreview)
        let sortedTasks = tasks.sorted(by: sortTasks)

        let eventItems = sortedEvents.map {
            WallpaperCalendarItem(
                id: $0.id.uuidString,
                sourceID: $0.id,
                title: $0.title,
                categoryName: $0.calendarName,
                color: CategoryPalette.color(for: $0.calendarName),
                kind: .event,
                startDate: $0.startDate,
                endDate: $0.endDate,
                isAllDay: $0.isAllDay,
                priority: nil
            )
        }
        let taskItems = sortedTasks.map {
            WallpaperCalendarItem(
                id: $0.id.uuidString,
                sourceID: $0.id,
                title: $0.title,
                categoryName: nil,
                color: $0.priority.color,
                kind: .task,
                startDate: $0.startDate,
                endDate: $0.endDate,
                isAllDay: false,
                priority: $0.priority
            )
        }
        return eventItems + taskItems
    }

    private func calendarCellRowContents(previews: [WallpaperCalendarItem],
                                         itemLimit: Int,
                                         multiDayState: WallpaperCalendarDayMultiDayState) -> [WallpaperCalendarCellRowContent] {
        guard itemLimit > 0 else { return [] }

        let regularItems = previews.filter { item in
            !(item.kind == .event && item.isMultiDayEvent)
        }

        var rows = Array(repeating: WallpaperCalendarCellRowContent.empty, count: itemLimit)
        var availableRows: [Int] = []

        for rowIndex in 0..<itemLimit {
            let isOccupiedByVisibleMultiDay = rowIndex < multiDayState.visibleLaneCount &&
                multiDayState.occupiedVisibleLanes.contains(rowIndex)
            if isOccupiedByVisibleMultiDay {
                rows[rowIndex] = .multiDayPlaceholder
            } else {
                availableRows.append(rowIndex)
            }
        }

        guard availableRows.isEmpty == false else { return rows }

        let needsOverflowRow = multiDayState.hiddenMultiDayCount > 0 || regularItems.count > availableRows.count
        let displayedRegularCount: Int
        let overflowCount: Int

        if needsOverflowRow {
            let regularCapacity = max(0, availableRows.count - 1)
            displayedRegularCount = min(regularItems.count, regularCapacity)
            overflowCount = multiDayState.hiddenMultiDayCount + max(0, regularItems.count - displayedRegularCount)
        } else {
            displayedRegularCount = regularItems.count
            overflowCount = 0
        }

        for (offset, item) in regularItems.prefix(displayedRegularCount).enumerated() {
            rows[availableRows[offset]] = .item(item)
        }

        if overflowCount > 0, availableRows.indices.contains(displayedRegularCount) {
            rows[availableRows[displayedRegularCount]] = .overflow(overflowCount)
        }

        return rows
    }

    private func buildWeekMultiDayLayout(weekDates: [Date],
                                         events: [CalendarEvent],
                                         itemLimit: Int,
                                         calendar: Calendar) -> WallpaperCalendarWeekMultiDayLayout {
        guard weekDates.count == 7,
              let firstWeekDate = weekDates.first,
              let lastWeekDate = weekDates.last
        else {
            return .empty
        }

        let weekStart = calendar.startOfDay(for: firstWeekDate)
        let weekLastDay = calendar.startOfDay(for: lastWeekDate)
        guard let weekEndExclusive = calendar.date(byAdding: .day, value: 1, to: weekLastDay) else {
            return .empty
        }

        struct Candidate {
            let event: CalendarEvent
            let startColumn: Int
            let endColumn: Int
            let continuesBeforeWeek: Bool
            let continuesAfterWeek: Bool
        }

        var candidates: [Candidate] = []
        for event in events {
            guard event.startDate < weekEndExclusive, event.endDate > weekStart else { continue }

            let adjustedEnd = calendar.date(byAdding: .second, value: -1, to: event.endDate) ?? event.endDate
            let eventStartDay = calendar.startOfDay(for: event.startDate)
            let rawEventEndDay = calendar.startOfDay(for: adjustedEnd)
            let eventEndDay = max(rawEventEndDay, eventStartDay)
            let visibleStartDay = max(eventStartDay, weekStart)
            let visibleEndDay = min(eventEndDay, weekLastDay)

            guard visibleStartDay <= visibleEndDay else { continue }

            let startColumn = calendar.dateComponents([.day], from: weekStart, to: visibleStartDay).day ?? 0
            let endColumn = calendar.dateComponents([.day], from: weekStart, to: visibleEndDay).day ?? 0
            guard (0..<7).contains(startColumn), (0..<7).contains(endColumn), startColumn <= endColumn else { continue }

            candidates.append(
                Candidate(
                    event: event,
                    startColumn: startColumn,
                    endColumn: endColumn,
                    continuesBeforeWeek: eventStartDay < weekStart,
                    continuesAfterWeek: eventEndDay > weekLastDay
                )
            )
        }

        if candidates.isEmpty {
            return .empty
        }

        let sortedCandidates = candidates.sorted { lhs, rhs in
            if lhs.startColumn != rhs.startColumn {
                return lhs.startColumn < rhs.startColumn
            }
            let lhsSpan = lhs.endColumn - lhs.startColumn
            let rhsSpan = rhs.endColumn - rhs.startColumn
            if lhsSpan != rhsSpan {
                return lhsSpan > rhsSpan
            }
            if lhs.event.isAllDay != rhs.event.isAllDay {
                return lhs.event.isAllDay && rhs.event.isAllDay == false
            }
            if lhs.event.startDate != rhs.event.startDate {
                return lhs.event.startDate < rhs.event.startDate
            }
            return lhs.event.title < rhs.event.title
        }

        let maxVisibleLanes = max(0, itemLimit - 1)
        var laneEndColumns: [Int] = []
        var visibleSegments: [WallpaperCalendarWeekMultiDaySegment] = []
        var occupiedVisibleLanesByDay = Array(repeating: Set<Int>(), count: 7)
        var hiddenCountByDay = Array(repeating: 0, count: 7)

        for candidate in sortedCandidates {
            let assignedLane: Int
            if let lane = laneEndColumns.firstIndex(where: { candidate.startColumn > $0 }) {
                assignedLane = lane
                laneEndColumns[lane] = candidate.endColumn
            } else {
                assignedLane = laneEndColumns.count
                laneEndColumns.append(candidate.endColumn)
            }

            if assignedLane < maxVisibleLanes {
                for dayIndex in candidate.startColumn...candidate.endColumn {
                    occupiedVisibleLanesByDay[dayIndex].insert(assignedLane)
                }
                visibleSegments.append(
                    WallpaperCalendarWeekMultiDaySegment(
                        id: "\(weekStart.timeIntervalSince1970)-\(candidate.event.id.uuidString)-\(assignedLane)",
                        eventID: candidate.event.id,
                        title: candidate.event.title,
                        categoryName: candidate.event.calendarName,
                        color: CategoryPalette.color(for: candidate.event.calendarName),
                        lane: assignedLane,
                        startColumn: candidate.startColumn,
                        endColumn: candidate.endColumn,
                        continuesBeforeWeek: candidate.continuesBeforeWeek,
                        continuesAfterWeek: candidate.continuesAfterWeek
                    )
                )
            } else {
                for dayIndex in candidate.startColumn...candidate.endColumn {
                    hiddenCountByDay[dayIndex] += 1
                }
            }
        }

        let visibleLaneCount = min(laneEndColumns.count, maxVisibleLanes)
        let dayStates = (0..<7).map { index in
            WallpaperCalendarDayMultiDayState(
                visibleLaneCount: visibleLaneCount,
                occupiedVisibleLanes: occupiedVisibleLanesByDay[index],
                hiddenMultiDayCount: hiddenCountByDay[index]
            )
        }

        return WallpaperCalendarWeekMultiDayLayout(
            visibleLaneCount: visibleLaneCount,
            dayStates: dayStates,
            segments: visibleSegments
        )
    }

    private func makeFingerprintPayload(rangeStart: Date,
                                        rangeEndExclusive: Date,
                                        events: [CalendarEvent],
                                        tasks: [Task]) -> WallpaperCalendarFingerprintPayload {
        WallpaperCalendarFingerprintPayload(
            rangeStart: rangeStart.timeIntervalSince1970,
            rangeEndExclusive: rangeEndExclusive.timeIntervalSince1970,
            events: events.map {
                WallpaperCalendarFingerprintPayload.Event(
                    id: $0.id,
                    title: $0.title,
                    start: $0.startDate.timeIntervalSince1970,
                    end: $0.endDate.timeIntervalSince1970,
                    categoryName: $0.calendarName,
                    isAllDay: $0.isAllDay
                )
            },
            tasks: tasks.map {
                WallpaperCalendarFingerprintPayload.TaskItem(
                    id: $0.id,
                    title: $0.title,
                    start: $0.startDate?.timeIntervalSince1970,
                    end: $0.endDate?.timeIntervalSince1970,
                    priority: $0.priority.rawValue,
                    isCompleted: $0.isCompleted
                )
            }
        )
    }

    private func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day) ?? day
    }

    private func dates(from startDate: Date, count: Int, calendar: Calendar) -> [Date] {
        (0..<count).compactMap {
            calendar.date(byAdding: .day, value: $0, to: startDate).map { calendar.startOfDay(for: $0) }
        }
    }

    private func sundayFirstWeekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return ["日", "月", "火", "水", "木", "金", "土"] }
        return symbols
    }

    private func sortEvents(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }
        return lhs.title < rhs.title
    }

    private func sortEventsForPreview(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        let lhsMulti = isMultiDayEvent(lhs)
        let rhsMulti = isMultiDayEvent(rhs)
        if lhsMulti != rhsMulti {
            return lhsMulti && rhsMulti == false
        }
        if lhs.isAllDay != rhs.isAllDay {
            return lhs.isAllDay && rhs.isAllDay == false
        }
        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }
        return lhs.title < rhs.title
    }

    private func sortTasks(_ lhs: Task, _ rhs: Task) -> Bool {
        if lhs.priority.rawValue != rhs.priority.rawValue {
            return lhs.priority.rawValue > rhs.priority.rawValue
        }
        let lhsDate = lhs.endDate ?? lhs.startDate ?? .distantFuture
        let rhsDate = rhs.endDate ?? rhs.startDate ?? .distantFuture
        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }
        return lhs.title < rhs.title
    }

    private func isMultiDayEvent(_ event: CalendarEvent) -> Bool {
        let calendar = Self.calendar
        let adjustedEnd = calendar.date(byAdding: .second, value: -1, to: event.endDate) ?? event.endDate
        return calendar.isDate(event.startDate, inSameDayAs: adjustedEnd) == false
    }
}
