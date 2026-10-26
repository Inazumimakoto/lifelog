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

    static func orderedBefore<Source: TaskPresentationSource>(_ lhs: Source, _ rhs: Source, preferring preference: DatePreference) -> Bool {
        if lhs.priority.rawValue != rhs.priority.rawValue {
            return lhs.priority.rawValue > rhs.priority.rawValue
        }
        let lhsDate = displayDate(for: lhs, preferring: preference) ?? .distantFuture
        let rhsDate = displayDate(for: rhs, preferring: preference) ?? .distantFuture
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
}
