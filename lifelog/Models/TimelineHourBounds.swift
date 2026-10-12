import Foundation

/// Padding and minimum span shared by both ends of the Today timeline axis.
struct TimelineHourBounds: Equatable {
    struct ItemHours {
        let start: Double
        let end: Double
        let isSleep: Bool
    }

    let start: Double
    let end: Double

    init(items: [ItemHours]) {
        let hours = items.flatMap { [$0.start, $0.end] }
        let minDataHour = hours.min() ?? 0
        let maxDataHour = hours.max() ?? 24
        var paddedStart = minDataHour - 2
        var paddedEnd = maxDataHour + 2

        if paddedEnd - paddedStart < 12 {
            let midpoint = (paddedStart + paddedEnd) / 2
            paddedStart = midpoint - 6
            paddedEnd = midpoint + 6
        }
        let hasOvernightSleep = items.contains { $0.isSleep && $0.end < $0.start }
        if hasOvernightSleep && paddedEnd - paddedStart < 24 {
            let midpoint = (paddedStart + paddedEnd) / 2
            paddedStart = midpoint - 12
            paddedEnd = midpoint + 12
        }
        start = max(0, paddedStart)
        end = max(paddedEnd, maxDataHour)
    }
}
