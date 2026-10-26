import Foundation

/// Local recurring schedules. See docs/requirements.md §4.2.
struct EventRecurrenceRule: Hashable, Codable {
    enum Frequency: String, CaseIterable, Codable {
        case daily
        case weekly
    }

    var frequency: Frequency
    var interval: Int
    /// Foundation weekday numbers: Sunday = 1 ... Saturday = 7.
    var weekdays: [Int]
    /// Inclusive calendar date in `timeZoneIdentifier`.
    var until: Date?
    var timeZoneIdentifier: String
    /// Cadence survives a future-only split even when its first template moves.
    var anchorDate: Date?
    /// Physical segments created by future edits still belong to one schedule.
    /// Nil preserves the original master's ID as the identity of legacy rules.
    var seriesGroupID: UUID?

    init(frequency: Frequency,
         interval: Int = 1,
         weekdays: [Int] = [],
         until: Date? = nil,
         timeZoneIdentifier: String = TimeZone.current.identifier,
         anchorDate: Date? = nil,
         seriesGroupID: UUID? = nil) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.weekdays = Array(Set(weekdays.filter { (1...7).contains($0) })).sorted()
        self.until = until
        self.timeZoneIdentifier = timeZoneIdentifier
        self.anchorDate = anchorDate
        self.seriesGroupID = seriesGroupID
    }
}
