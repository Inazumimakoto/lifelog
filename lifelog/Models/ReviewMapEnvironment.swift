import Foundation

/// A change to any date, number or language setting invalidates only the derived cache.
nonisolated struct ReviewMapEnvironment: Hashable, Codable, Sendable {
    var localeIdentifier: String
    var calendar: Calendar
    var visitCountFormat: String

    init(localeIdentifier: String, calendar: Calendar, visitCountFormat: String) {
        self.localeIdentifier = localeIdentifier
        self.calendar = calendar
        self.visitCountFormat = visitCountFormat
    }
}
