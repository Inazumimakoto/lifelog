import Foundation

/// Calendar navigation retains the original day, even when an intermediate month
/// clamps it to its last day. Changing scale keeps the displayed ending day.
struct HealthHistoryPosition {
    private(set) var period: HealthHistoryPeriod
    private(set) var referenceDate: Date
    private(set) var offset: Int = 0

    init(period: HealthHistoryPeriod = .week,
         endingOn date: Date,
         calendar: Calendar = .current) {
        self.period = period
        self.referenceDate = calendar.startOfDay(for: date)
    }

    func endingOn(calendar: Calendar = .current) -> Date {
        period.shiftedEndDate(from: referenceDate, by: offset, calendar: calendar)
    }

    mutating func move(by direction: Int,
                       latestDate: Date,
                       calendar: Calendar = .current) {
        let nextOffset = offset + direction
        let candidate = period.shiftedEndDate(from: referenceDate, by: nextOffset, calendar: calendar)
        let latest = calendar.startOfDay(for: latestDate)
        if candidate > latest {
            resetToLatest(latest, calendar: calendar)
        } else {
            offset = nextOffset
        }
    }

    mutating func changePeriod(to newPeriod: HealthHistoryPeriod,
                              calendar: Calendar = .current) {
        guard newPeriod != period else { return }
        referenceDate = endingOn(calendar: calendar)
        offset = 0
        period = newPeriod
    }

    mutating func resetToLatest(_ date: Date, calendar: Calendar = .current) {
        referenceDate = calendar.startOfDay(for: date)
        offset = 0
    }
}
