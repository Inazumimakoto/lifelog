import Foundation
import SwiftData

/// App Intents and widgets use the same recurrence expansion as the app (§4.2).
/// Fetch masters independently of their first occurrence so an old series can
/// still contribute events to a newly displayed month.
@MainActor
enum CalendarEventStorageQuery {
    static func events(
        in context: ModelContext,
        from rangeStart: Date,
        to rangeEndExclusive: Date,
        externalEvents: [CalendarEvent] = [],
        calendar: Calendar = .current
    ) throws -> [CalendarEvent] {
        guard rangeStart < rangeEndExclusive else { return [] }
        let storageRange = EventQuerying.storageRange(
            rangeStart: rangeStart, rangeEndExclusive: rangeEndExclusive, calendar: calendar
        )
        let storedStart = storageRange.start
        let storedEnd = storageRange.end
        let descriptor = FetchDescriptor<SDCalendarEvent>(
            predicate: #Predicate<SDCalendarEvent> {
                $0.recurrenceRuleData != nil || ($0.startDate < storedEnd && $0.endDate > storedStart)
            }
        )
        let masters = try context.fetch(descriptor).map { row in
            CalendarEvent(
                id: row.id,
                title: row.title,
                detail: row.detail ?? "",
                startDate: row.startDate,
                endDate: row.endDate,
                calendarName: row.calendarName,
                isAllDay: row.isAllDay,
                sourceCalendarIdentifier: row.sourceCalendarIdentifier,
                reminderMinutes: row.reminderMinutes,
                reminderDate: row.reminderDate,
                dateOnlyTimeZoneIdentifier: row.dateOnlyTimeZoneIdentifier,
                recurrenceRule: row.recurrenceRuleData.flatMap {
                    try? JSONDecoder().decode(EventRecurrenceRule.self, from: $0)
                },
                urlString: row.urlString
            )
        }
        // A replacement can move from an occurrence outside the requested range
        // into it. Filtering exceptions by their original date would lose it.
        let exceptions = try context.fetch(FetchDescriptor<SDCalendarEventException>())
            .map { CalendarEventException(sd: $0) }
        return EventQuerying.resolved(
            internalEvents: masters,
            exceptions: exceptions,
            externalEvents: externalEvents,
            rangeStart: rangeStart,
            rangeEndExclusive: rangeEndExclusive,
            calendar: calendar
        )
    }
}
