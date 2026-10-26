import Foundation

/// Clock coordinates for the sleep chart (§4.8). Each segment has a constant
/// UTC offset, so its drawn height exactly matches its elapsed duration.
nonisolated enum HealthSleepTimelineLayout {
    nonisolated enum Lane: Equatable, Sendable {
        case full
        case beforeClockChange
        case afterClockChange

        var fractions: ClosedRange<Double> {
            switch self {
            case .full: return 0...1
            case .beforeClockChange: return 0...0.47
            case .afterClockChange: return 0.53...1
            }
        }
    }

    nonisolated struct Segment: Equatable, Sendable {
        let startDate: Date
        let endDate: Date
        let startHour: Double
        let endHour: Double
        let lane: Lane
    }

    nonisolated struct Axis: Equatable, Sendable {
        let lowerHour: Double
        let upperHour: Double
        let tickHours: [Double]

        var yDomain: ClosedRange<Double> { -upperHour ... -lowerHour }
    }

    nonisolated struct ClockComponents: Equatable, Sendable {
        let dayOffset: Int
        let hour: Int
        let minute: Int
    }

    static func segments(
        from start: Date,
        to end: Date,
        relativeTo day: Date,
        calendar: Calendar = .current
    ) -> [Segment] {
        guard start < end else { return [] }
        let day = calendar.startOfDay(for: day)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let changes = transitions(from: min(start, day), to: max(end, nextDay), timeZone: calendar.timeZone)
        let rollback = changes.first {
            calendar.timeZone.secondsFromGMT(for: $0) < calendar.timeZone.secondsFromGMT(for: $0.addingTimeInterval(-1))
        }
        let boundaries = [start] + changes.filter { $0 > start && $0 < end } + [end]
        return zip(boundaries, boundaries.dropFirst()).map { lower, upper in
            let startHour = localHour(lower, relativeTo: day, calendar: calendar)
            // Use the pre-change clock at an open endpoint. For example, a fall
            // segment ends at 02:00 in the left lane; the next begins at 01:00
            // in the right lane. Its real final 01:10 is never shifted to 02:10.
            let endHour = startHour + upper.timeIntervalSince(lower) / 3_600
            let lane: Lane
            if let rollback {
                lane = lower < rollback ? .beforeClockChange : .afterClockChange
            } else {
                lane = .full
            }
            return Segment(startDate: lower, endDate: upper,
                           startHour: startHour, endHour: endHour, lane: lane)
        }
    }

    static func axis(for segments: [Segment]) -> Axis {
        guard let earliest = segments.map(\.startHour).min(),
              let latest = segments.map(\.endHour).max() else {
            return Axis(lowerHour: -6, upperHour: 18, tickHours: [-6, 0, 6, 12, 18])
        }
        let lower = earliest - 0.5
        let upper = latest + 0.5
        let span = upper - lower
        let step = [1.0, 2, 3, 4, 6, 12, 24].first { span / $0 <= 6 } ?? ceil(span / 6 / 24) * 24
        let minimum = floor(lower / step) * step
        let maximum = ceil(upper / step) * step
        return Axis(lowerHour: minimum, upperHour: maximum,
                    tickHours: Array(stride(from: minimum, through: maximum, by: step)))
    }

    static func clockComponents(for hour: Double) -> ClockComponents {
        let minutes = Int((hour * 60).rounded())
        let dayOffset = Int(floor(Double(minutes) / 1_440))
        let minuteOfDay = minutes - dayOffset * 1_440
        return ClockComponents(dayOffset: dayOffset, hour: minuteOfDay / 60, minute: minuteOfDay % 60)
    }

    /// Format a nominal clock time on a date without DST. Setting 02:00 on a
    /// spring-change date would silently turn that axis label into 03:00.
    static func clockText(for hour: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let components = clockComponents(for: hour)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        let date = Date(timeIntervalSince1970: Double(components.hour * 3_600 + components.minute * 60))
        return formatter.string(from: date)
    }

    private static func localHour(_ date: Date, relativeTo day: Date, calendar: Calendar) -> Double {
        let offset = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: date)).day ?? 0
        let clock = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        return Double(offset * 24 + (clock.hour ?? 0))
            + Double(clock.minute ?? 0) / 60
            + Double(clock.second ?? 0) / 3_600
            + Double(clock.nanosecond ?? 0) / 3_600_000_000_000
    }

    private static func transitions(from start: Date, to end: Date, timeZone: TimeZone) -> [Date] {
        var changes: [Date] = []
        var cursor = start.addingTimeInterval(-1)
        while let change = timeZone.nextDaylightSavingTimeTransition(after: cursor), change < end {
            guard change > cursor else { break }
            if change >= start,
               timeZone.secondsFromGMT(for: change) != timeZone.secondsFromGMT(for: change.addingTimeInterval(-1)) {
                changes.append(change)
            }
            cursor = change
        }
        return changes
    }
}
