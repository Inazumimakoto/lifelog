import Foundation

enum CalendarEventEditScope: Hashable {
    case occurrence
    case future
    case series
}

enum CalendarEventEditError: Error, Equatable {
    case readOnly
    case missingEvent
    case invalidScope
    case recurrenceRequiresSeries
    case invalidDates
    case stalePlan
}

/// Immutable preview; no persistence or published values change until apply.
struct CalendarEventEditPlan {
    let scope: CalendarEventEditScope
    let unmatchedExceptions: [CalendarEventException]
    let originalEvents: [CalendarEvent]
    let originalExceptions: [CalendarEventException]
    let resultingEvents: [CalendarEvent]
    let resultingExceptions: [CalendarEventException]
    let preservedStandaloneEvents: [CalendarEvent]
    let refreshReminders: Bool
}
