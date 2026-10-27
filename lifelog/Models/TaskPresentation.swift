import Foundation

/// Task lists prioritize the deadline, while calendar surfaces prioritize the
/// start date. Both share priority/date/title ordering and inclusive day ranges.
enum TaskPresentation {
    enum DatePreference {
        case start
        case deadline
    }

    static func displayDate(for task: some TaskPresentationSource, preferring preference: DatePreference, calendar: Calendar = .current) -> Date? {
        let date: Date?
        switch preference {
        case .start: date = task.startDate ?? task.endDate
        case .deadline: date = task.endDate ?? task.startDate
        }
        return DateOnlyProjection.project(date, sourceTimeZoneIdentifier: task.dateOnlyTimeZoneIdentifier, calendar: calendar)
    }

    static func orderedBefore<Source: TaskPresentationSource>(_ lhs: Source, _ rhs: Source, preferring preference: DatePreference, calendar: Calendar = .current) -> Bool {
        if lhs.priority.rawValue != rhs.priority.rawValue {
            return lhs.priority.rawValue > rhs.priority.rawValue
        }
        let lhsDate = displayDate(for: lhs, preferring: preference, calendar: calendar) ?? .distantFuture
        let rhsDate = displayDate(for: rhs, preferring: preference, calendar: calendar) ?? .distantFuture
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        return lhs.title < rhs.title
    }

    static func isScheduled(_ task: some TaskPresentationSource, on date: Date, calendar: Calendar = .current) -> Bool {
        guard let start = displayDate(for: task, preferring: .start, calendar: calendar),
              let end = displayDate(for: task, preferring: .deadline, calendar: calendar) else { return false }
        let normalizedStart = calendar.startOfDay(for: start)
        let normalizedEnd = calendar.startOfDay(for: end)
        let target = calendar.startOfDay(for: date)
        return normalizedStart...normalizedEnd ~= target
    }

    /// Keep unfinished tasks visible after their final scheduled day (§4.1/§4.3).
    static func isOverdue(_ task: some TaskPresentationSource, on date: Date, calendar: Calendar = .current) -> Bool {
        guard !task.isCompleted,
              let deadline = displayDate(for: task, preferring: .deadline, calendar: calendar) else { return false }
        return calendar.startOfDay(for: deadline) < calendar.startOfDay(for: date)
    }

    static func isPending(_ task: some TaskPresentationSource, on date: Date, calendar: Calendar = .current) -> Bool {
        !task.isCompleted && (isScheduled(task, on: date, calendar: calendar) || isOverdue(task, on: date, calendar: calendar))
    }

    /// Today's scheduled tasks lead the overdue group, matching the Home card.
    static func orderedForToday<Source: TaskPresentationSource>(_ lhs: Source, _ rhs: Source, on date: Date, calendar: Calendar = .current) -> Bool {
        let lhsIsOverdue = isOverdue(lhs, on: date, calendar: calendar)
        let rhsIsOverdue = isOverdue(rhs, on: date, calendar: calendar)
        if lhsIsOverdue != rhsIsOverdue { return !lhsIsOverdue }
        return orderedBefore(lhs, rhs, preferring: lhsIsOverdue ? .deadline : .start, calendar: calendar)
    }
}
