import Foundation

/// Shared fetch window and daily/prefetch policy for external calendars.
enum ExternalCalendarSyncPolicy {
    private static let pastMonths = 6
    private static let futureMonths = 18
    private static let prefetchThresholdMonths = 2

    static func desiredRange(for anchor: Date, calendar: Calendar = .current) -> ExternalCalendarRange {
        let anchorMonth = monthStart(for: anchor, calendar: calendar)
        let start = calendar.date(byAdding: .month, value: -pastMonths, to: anchorMonth) ?? anchorMonth
        let endMonthStart = calendar.date(byAdding: .month, value: futureMonths + 1, to: anchorMonth) ?? anchorMonth
        let end = calendar.date(byAdding: .second, value: -1, to: endMonthStart) ?? endMonthStart
        return ExternalCalendarRange(start: start, end: end)
    }

    static func shouldSync(
        anchor: Date,
        storedRange: ExternalCalendarRange?,
        lastSyncDate: Date?,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        force: Bool = false
    ) -> Bool {
        guard !force,
              let lastSyncDate,
              calendar.isDate(lastSyncDate, inSameDayAs: referenceDate) else { return true }
        // Preserve the legacy daily throttle even when a stored range is absent.
        guard let storedRange else { return false }

        let anchorMonth = monthStart(for: anchor, calendar: calendar)
        let rangeStart = monthStart(for: storedRange.start, calendar: calendar)
        let rangeEnd = monthStart(for: storedRange.end, calendar: calendar)
        let thresholdStart = calendar.date(byAdding: .month, value: prefetchThresholdMonths, to: rangeStart) ?? rangeStart
        let thresholdEnd = calendar.date(byAdding: .month, value: -prefetchThresholdMonths, to: rangeEnd) ?? rangeEnd
        return anchorMonth < thresholdStart || anchorMonth > thresholdEnd
    }

    private static func monthStart(for date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}
