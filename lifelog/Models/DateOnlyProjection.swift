import Foundation

/// Date-only records retain their source-zone civil day while presentation follows
/// the current calendar. Their original stored dates remain unchanged.
enum DateOnlyProjection {
    static func project(_ date: Date, sourceTimeZoneIdentifier: String?, calendar: Calendar = .current) -> Date {
        guard let identifier = sourceTimeZoneIdentifier, let sourceZone = TimeZone(identifier: identifier) else { return date }
        return civilDate(date, from: sourceZone, to: calendar.timeZone) ?? date
    }

    static func project(_ date: Date?, sourceTimeZoneIdentifier: String?, calendar: Calendar = .current) -> Date? {
        date.map { project($0, sourceTimeZoneIdentifier: sourceTimeZoneIdentifier, calendar: calendar) }
    }

    /// Date pickers use display-zone days; saving converts their label back to
    /// the original source zone instead of changing the meaning after travel.
    static func sourceDate(fromDisplay date: Date, sourceTimeZoneIdentifier: String?, calendar: Calendar = .current) -> Date {
        guard let identifier = sourceTimeZoneIdentifier, let sourceZone = TimeZone(identifier: identifier) else {
            return calendar.startOfDay(for: date)
        }
        return civilDate(date, from: calendar.timeZone, to: sourceZone) ?? date
    }

    private static func civilDate(_ date: Date, from sourceZone: TimeZone, to targetZone: TimeZone) -> Date? {
        var source = Calendar(identifier: .gregorian); source.timeZone = sourceZone
        var target = Calendar(identifier: .gregorian); target.timeZone = targetZone
        let components = source.dateComponents([.year, .month, .day], from: date)
        guard let candidate = target.date(from: components) else { return nil }
        let start = target.startOfDay(for: candidate)
        guard target.dateComponents([.year, .month, .day], from: start) == components else { return nil }
        return start
    }
}
