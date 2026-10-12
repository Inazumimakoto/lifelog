import Foundation

/// The historical days requested by the app plus today. Calendar arithmetic
/// keeps daily HealthKit buckets correct across daylight-saving transitions.
nonisolated struct HealthQueryWindow: Sendable {
    let start: Date
    let endExclusive: Date
    let summaryDays: [Date]

    init?(lastNDays: Int, referenceDate: Date = Date(), calendar: Calendar = .current) {
        guard lastNDays >= 0 else { return nil }
        let today = calendar.startOfDay(for: referenceDate)
        guard let start = calendar.date(byAdding: .day, value: -lastNDays, to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
        self.start = start
        endExclusive = end
        summaryDays = (0...lastNDays).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
    }
}
