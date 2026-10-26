import Foundation

/// Health sleep calculations for requirements §4.8. Build complete sessions
/// before assigning their wake-up day, and count every instant only once.
nonisolated enum SleepSampleAggregation {
    nonisolated enum State: String, Hashable, Sendable {
        case inBed
        case awake
        case unspecified
        case core
        case deep
        case rem

        var isAsleep: Bool {
            self != .inBed && self != .awake
        }

        var isDetailed: Bool {
            self != .inBed && self != .unspecified
        }
    }

    nonisolated struct Sample: Hashable, Sendable {
        let start: Date
        let end: Date
        let state: State
        let sourceIdentifier: String

        init(start: Date, end: Date, state: State, sourceIdentifier: String = "") {
            self.start = start
            self.end = end
            self.state = state
            self.sourceIdentifier = sourceIdentifier
        }
    }

    nonisolated struct StageInterval: Equatable, Sendable {
        let start: Date
        let end: Date
        let state: State
    }

    nonisolated struct DailySummary: Equatable, Sendable {
        /// The longest session's first and last asleep instants, for its timeline.
        let start: Date
        let end: Date
        /// Actual sleep across all sessions on this wake-up day, including naps.
        let duration: Double
        /// Nonoverlapping stages across all sessions. Awake time is not asleep.
        let stages: [StageInterval]
        fileprivate let mainSleepDuration: Double
    }

    private nonisolated struct Session {
        var start: Date
        var end: Date
        var samples: [Sample]
    }

    private nonisolated struct Event {
        let date: Date
        let sampleIndex: Int
        let isStart: Bool
    }

    /// Context on both sides preserves the first night's pre-midnight stages
    /// and prevents a terminal session from being cut at the requested boundary.
    static func queryBounds(
        from startDate: Date,
        to endExclusive: Date,
        calendar: Calendar = .current
    ) -> DateInterval? {
        guard startDate < endExclusive,
              let start = calendar.date(byAdding: .day, value: -1, to: startDate),
              let end = calendar.date(byAdding: .day, value: 1, to: endExclusive) else { return nil }
        return DateInterval(start: start, end: end)
    }

    static func aggregate(
        _ samples: [Sample],
        from startDate: Date,
        to endExclusive: Date,
        calendar: Calendar = .current
    ) -> [Date: DailySummary] {
        guard startDate < endExclusive else { return [:] }
        let valid = samples.filter { $0.start < $0.end && $0.state != .inBed }
        let asleep = valid.filter { $0.state.isAsleep }.sorted(by: samplePrecedes)
        let awake = valid.filter { $0.state == .awake }
        var sessions: [Session] = []

        // Two hours is the app's session separation rule, not a claim that the
        // intervening time was asleep. Stage duration never includes these gaps.
        for sample in asleep {
            if let previousEnd = sessions.last?.end,
               sample.start.timeIntervalSince(previousEnd) <= 2 * 3_600 {
                sessions[sessions.count - 1].end = max(previousEnd, sample.end)
                sessions[sessions.count - 1].samples.append(sample)
            } else {
                sessions.append(Session(start: sample.start, end: sample.end, samples: [sample]))
            }
        }

        var days: [Date: DailySummary] = [:]
        for session in sessions {
            let samples = session.samples + awake.filter {
                $0.start < session.end && $0.end > session.start
            }
            let resolved = resolve(samples, within: session)
            let sleepStages = resolved.filter { $0.state.isAsleep }
            guard let first = sleepStages.first, let last = sleepStages.last else { continue }
            let stages = resolved.compactMap { interval -> StageInterval? in
                let start = max(interval.start, first.start)
                let end = min(interval.end, last.end)
                guard start < end else { return nil }
                return StageInterval(start: start, end: end, state: interval.state)
            }
            let day = calendar.startOfDay(for: last.end)
            guard day >= startDate && day < endExclusive else { continue }
            let duration = sleepStages.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 3_600

            if let existing = days[day] {
                // Prefer the longer actual sleep; a tie selects the earlier
                // session consistently, independent of HealthKit result order.
                let isMainSleep = duration > existing.mainSleepDuration
                days[day] = DailySummary(
                    start: isMainSleep ? first.start : existing.start,
                    end: isMainSleep ? last.end : existing.end,
                    duration: existing.duration + duration,
                    stages: existing.stages + stages,
                    mainSleepDuration: max(existing.mainSleepDuration, duration)
                )
            } else {
                days[day] = DailySummary(
                    start: first.start,
                    end: last.end,
                    duration: duration,
                    stages: stages,
                    mainSleepDuration: duration
                )
            }
        }
        return days
    }

    private static func samplePrecedes(_ lhs: Sample, _ rhs: Sample) -> Bool {
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        if lhs.end != rhs.end { return lhs.end < rhs.end }
        if lhs.sourceIdentifier != rhs.sourceIdentifier { return lhs.sourceIdentifier < rhs.sourceIdentifier }
        return lhs.state.rawValue < rhs.state.rawValue
    }

    private static func resolve(_ samples: [Sample], within session: Session) -> [StageInterval] {
        let clipped = samples.compactMap { sample -> Sample? in
            let start = max(sample.start, session.start)
            let end = min(sample.end, session.end)
            guard start < end else { return nil }
            return Sample(start: start, end: end, state: sample.state, sourceIdentifier: sample.sourceIdentifier)
        }
        let sourceOrder = rankedSources(in: clipped)
        let ranks = Dictionary(uniqueKeysWithValues: sourceOrder.enumerated().map { ($0.element, $0.offset) })
        let events = clipped.enumerated().flatMap { index, sample in
            [Event(date: sample.start, sampleIndex: index, isStart: true),
             Event(date: sample.end, sampleIndex: index, isStart: false)]
        }.sorted { $0.date < $1.date }
        var active: [Int: Sample] = [:]
        var intervals: [StageInterval] = []
        var eventIndex = 0

        while eventIndex < events.count {
            let instant = events[eventIndex].date
            // Apply all endpoints together: samples are half-open intervals.
            while eventIndex < events.count && events[eventIndex].date == instant {
                let event = events[eventIndex]
                if event.isStart {
                    active[event.sampleIndex] = clipped[event.sampleIndex]
                } else {
                    active.removeValue(forKey: event.sampleIndex)
                }
                eventIndex += 1
            }
            guard eventIndex < events.count, !active.isEmpty else { continue }
            let end = events[eventIndex].date
            let detailed = active.values.filter { $0.state.isDetailed }
            let state: State
            if let preferred = detailed.min(by: {
                ranks[$0.sourceIdentifier, default: .max] < ranks[$1.sourceIdentifier, default: .max]
            }) {
                let states = Set(detailed.filter {
                    $0.sourceIdentifier == preferred.sourceIdentifier
                }.map(\.state))
                // Awake overrides a contradictory asleep record from the same
                // source. Conflicting sleep stages remain unknown, not invented.
                state = states.contains(.awake) ? .awake : states.count == 1 ? preferred.state : .unspecified
            } else {
                state = .unspecified
            }
            if let previous = intervals.last, previous.end == instant, previous.state == state {
                intervals[intervals.count - 1] = StageInterval(start: previous.start, end: end, state: state)
            } else {
                intervals.append(StageInterval(start: instant, end: end, state: state))
            }
        }
        return intervals
    }

    /// Detailed stages/awake override overlapping unspecified sleep. Among
    /// detailed sources, use the widest detailed asleep coverage for the session,
    /// then total detailed coverage, then the stable source identifier. This is
    /// the app's deterministic policy; Health's user-configured order is not read.
    private static func rankedSources(in samples: [Sample]) -> [String] {
        let sources = Dictionary(grouping: samples, by: \.sourceIdentifier)
        let coverage = sources.mapValues { samples in
            (asleep: unionDuration(samples.filter { $0.state.isDetailed && $0.state.isAsleep }),
             detailed: unionDuration(samples.filter { $0.state.isDetailed }))
        }
        return sources.keys.sorted { lhs, rhs in
            let left = coverage[lhs]!
            let right = coverage[rhs]!
            if left.asleep != right.asleep { return left.asleep > right.asleep }
            if left.detailed != right.detailed { return left.detailed > right.detailed }
            return lhs < rhs
        }
    }

    private static func unionDuration(_ samples: [Sample]) -> TimeInterval {
        let sorted = samples.sorted(by: samplePrecedes)
        guard let first = sorted.first else { return 0 }
        var start = first.start
        var end = first.end
        var duration: TimeInterval = 0
        for sample in sorted.dropFirst() {
            if sample.start <= end {
                end = max(end, sample.end)
            } else {
                duration += end.timeIntervalSince(start)
                start = sample.start
                end = sample.end
            }
        }
        return duration + end.timeIntervalSince(start)
    }
}
