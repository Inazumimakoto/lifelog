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
        let calendar = Calendar.autoupdatingCurrent
        return CalendarPreviewLayout.isMultiDayEvent(start: startDate, end: endDate, calendar: calendar)
    }

    func displayTitle(privacyMode: WallpaperCalendarPrivacyMode) -> String {
        switch privacyMode {
        case .details:
            return title
        case .categoryOnly:
            if kind == .task {
                return String(localized: "タスク")
            }
            return categoryName?.isEmpty == false ? CategoryPalette.displayName(for: categoryName!) : String(localized: "予定")
        case .hidden:
            return kind == .task ? String(localized: "タスクあり") : String(localized: "予定あり")
        }
    }
}

typealias WallpaperCalendarCellRowContent = CalendarPreviewLayout.Row<WallpaperCalendarItem>


typealias WallpaperCalendarWeekMultiDaySegment = CalendarWeekMultiDaySegment
typealias WallpaperCalendarWeekMultiDayLayout = CalendarWeekMultiDayLayout

extension CalendarWeekMultiDaySegment {
    func displayTitle(privacyMode: WallpaperCalendarPrivacyMode) -> String {
        switch privacyMode {
        case .details:
            return title
        case .categoryOnly:
            return categoryName.isEmpty ? String(localized: "予定") : CategoryPalette.displayName(for: categoryName)
        case .hidden:
            return String(localized: "予定あり")
        }
    }
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
    let firstWeekday: Int
    let events: [Event]
    let tasks: [TaskItem]
}

@MainActor
final class WallpaperCalendarDataProvider {
    static let itemLimit = 4

    static var calendar: Calendar {
        var calendar = CalendarWeekStart.current.calendar
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
            weekdaySymbols: weekdaySymbols(calendar: calendar),
            weeks: weeks,
            fingerprintPayload: makeFingerprintPayload(
                rangeStart: rangeStart,
                rangeEndExclusive: rangeEndExclusive,
                firstWeekday: calendar.firstWeekday,
                events: events,
                tasks: tasks
            )
        )
    }

    private func fetchEvents(from rangeStart: Date, to rangeEndExclusive: Date) -> [CalendarEvent] {
        // マージ・重複排除・整列は共有 EventQuerying に一本化する。
        let internalEvents = fetchInternalEvents(from: rangeStart, to: rangeEndExclusive)
        let externalEvents = fetchExternalEvents(from: rangeStart, to: rangeEndExclusive)
        return EventQuerying.mergedDedupedSorted(
            internalEvents: internalEvents,
            externalEvents: externalEvents
        )
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
                    detail: $0.detail ?? "",
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
        // 外部イベントの読み出しとデコードは共有 EventQuerying に集約。
        let defaults = UserDefaults(suiteName: PersistenceController.appGroupIdentifier)
        let events = EventQuerying.loadExternalEvents(from: defaults)
        return EventQuerying.overlapping(events, rangeStart: rangeStart, rangeEndExclusive: rangeEndExclusive)
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
                                         multiDayState: CalendarDayMultiDayState) -> [WallpaperCalendarCellRowContent] {
        let regularItems = previews.filter { !($0.kind == .event && $0.isMultiDayEvent) }
        return CalendarPreviewLayout.rows(regularItems: regularItems,
                                          itemLimit: itemLimit,
                                          multiDayState: multiDayState)
    }

    private func buildWeekMultiDayLayout(weekDates: [Date],
                                         events: [CalendarEvent],
                                         itemLimit: Int,
                                         calendar: Calendar) -> WallpaperCalendarWeekMultiDayLayout {
        let layout = CalendarPreviewLayout.week(dates: weekDates, events: events,
                                                itemLimit: itemLimit, calendar: calendar)
        return CalendarWeekMultiDayLayout(layout: layout)
    }

    private func makeFingerprintPayload(rangeStart: Date,
                                        rangeEndExclusive: Date,
                                        firstWeekday: Int,
                                        events: [CalendarEvent],
                                        tasks: [Task]) -> WallpaperCalendarFingerprintPayload {
        WallpaperCalendarFingerprintPayload(
            rangeStart: rangeStart.timeIntervalSince1970,
            rangeEndExclusive: rangeEndExclusive.timeIntervalSince1970,
            firstWeekday: firstWeekday,
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

    private func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let sundayFirst = symbols.count == 7 ? symbols : ["日", "月", "火", "水", "木", "金", "土"]
        let firstIndex = calendar.firstWeekday - 1
        return (0..<7).map { sundayFirst[(firstIndex + $0) % 7] }
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
        TaskPresentation.orderedBefore(lhs, rhs, preferring: .deadline)
    }

    private func isMultiDayEvent(_ event: CalendarEvent) -> Bool {
        let calendar = Self.calendar
        return CalendarPreviewLayout.isMultiDayEvent(start: event.startDate, end: event.endDate, calendar: calendar)
    }
}
