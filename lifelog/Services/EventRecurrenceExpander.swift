import Foundation

/// Expands only the requested window; the database retains a series and exceptions.
/// Shared by the app, Widget and wallpaper calendar. See requirements.md §4.2.
enum EventRecurrenceExpander {
    /// Resolve one original slot without expanding the surrounding duration.
    static func originalOccurrence(of event: CalendarEvent, startingAt originalStart: Date,
                                   calendar: Calendar = .current) -> CalendarEvent? {
        guard let rule = event.recurrenceRule, event.occurrenceReference == nil,
              event.endDate > event.startDate else { return nil }
        var recurrenceCalendar = Calendar(identifier: .gregorian)
        recurrenceCalendar.timeZone = TimeZone(identifier: rule.timeZoneIdentifier) ?? calendar.timeZone
        recurrenceCalendar.firstWeekday = 2
        recurrenceCalendar.minimumDaysInFirstWeek = 4
        let schedule = Schedule(event: event, rule: rule, calendar: recurrenceCalendar)
        guard schedule.start(on: recurrenceCalendar.startOfDay(for: originalStart)) == originalStart else { return nil }
        return schedule.occurrence(startingAt: originalStart, endingAt: schedule.endDate(startingAt: originalStart))
    }

    static func occurrences(
        events: [CalendarEvent],
        exceptions: [CalendarEventException],
        rangeStart: Date,
        rangeEndExclusive: Date,
        calendar: Calendar = .current,
        sortResults: Bool = true
    ) -> [CalendarEvent] {
        guard rangeStart < rangeEndExclusive else { return [] }
        let exceptionsBySeries = Dictionary(grouping: exceptions, by: \.seriesID)
        var result: [CalendarEvent] = []

        for event in events {
            guard let rule = event.recurrenceRule, event.occurrenceReference == nil else {
                if EventQuerying.overlaps(event, rangeStart: rangeStart, rangeEndExclusive: rangeEndExclusive, calendar: calendar) {
                    result.append(event)
                }
                continue
            }
            guard event.endDate > event.startDate else { continue }
            let seriesExceptions = exceptionsBySeries[event.id] ?? []
            let duration = event.endDate.timeIntervalSince(event.startDate)
            // A conservative bound avoids calendar setup for long-expired series.
            // Keep enough room for local date labels, DST and a multi-day event;
            // a replacement moved into this window must still be considered.
            if let until = rule.until,
               until.addingTimeInterval(duration + 345_600) < rangeStart,
               !seriesExceptions.contains(where: { exception in
                   guard let replacement = exception.replacement else { return false }
                   return EventQuerying.overlaps(replacement, rangeStart: rangeStart, rangeEndExclusive: rangeEndExclusive, calendar: calendar)
               }) {
                continue
            }
            var recurrenceCalendar = Calendar(identifier: .gregorian)
            recurrenceCalendar.timeZone = TimeZone(identifier: rule.timeZoneIdentifier) ?? calendar.timeZone
            // Cadence must not change when the display's week-start setting changes.
            recurrenceCalendar.firstWeekday = 2
            recurrenceCalendar.minimumDaysInFirstWeek = 4
            let schedule = Schedule(event: event, rule: rule, calendar: recurrenceCalendar)
            let overrides = seriesExceptions.reduce(into: [Date: CalendarEventException]()) {
                $0[$1.originalStartDate] = $1
            }

            // Source-zone all-day labels can project into a neighboring display day.
            // Also look back by the full duration to include multi-day occurrences.
            let lookback = duration + 172_800
            let firstDay = max(schedule.firstDay, recurrenceCalendar.startOfDay(for: rangeStart.addingTimeInterval(-lookback)))
            var end = recurrenceCalendar.startOfDay(for: rangeEndExclusive.addingTimeInterval(172_800))
            if let until = rule.until,
               let untilEnd = recurrenceCalendar.date(byAdding: .day, value: 1, to: recurrenceCalendar.startOfDay(for: until)) {
                end = min(end, untilEnd)
            }

            schedule.forEachStart(from: firstDay, to: end) { start in
                guard overrides[start] == nil else { return }
                let occurrenceEnd = schedule.endDate(startingAt: start)
                guard schedule.overlaps(start: start, end: occurrenceEnd, rangeStart: rangeStart,
                                        rangeEndExclusive: rangeEndExclusive, displayCalendar: calendar) else { return }
                // Identity hashing and reminder projection happen only after
                // the occurrence is known to belong to the requested window.
                result.append(schedule.occurrence(startingAt: start, endingAt: occurrenceEnd))
            }

            // Check replacements independently of the original window. A distant
            // original slot may be moved into this window, or a visible slot out.
            for exception in overrides.values {
                guard let replacement = exception.replacement,
                      EventQuerying.overlaps(replacement, rangeStart: rangeStart, rangeEndExclusive: rangeEndExclusive, calendar: calendar),
                      schedule.start(on: recurrenceCalendar.startOfDay(for: exception.originalStartDate)) == exception.originalStartDate else { continue }
                result.append(identified(replacement, reference: exception.occurrenceReference, rule: rule))
            }
        }

        guard sortResults else { return result }
        return result.sorted { lhs, rhs in
            let left = lhs.displayStartDate(calendar: calendar), right = rhs.displayStartDate(calendar: calendar)
            if left != right { return left < right }
            if lhs.title != rhs.title { return lhs.title < rhs.title }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func identified(_ event: CalendarEvent, reference: CalendarEventOccurrenceReference, rule: EventRecurrenceRule) -> CalendarEvent {
        CalendarEvent(id: reference.occurrenceID,
                      title: event.title,
                      detail: event.detail,
                      startDate: event.startDate,
                      endDate: event.endDate,
                      calendarName: event.calendarName,
                      isAllDay: event.isAllDay,
                      sourceCalendarIdentifier: event.sourceCalendarIdentifier,
                      reminderMinutes: event.reminderMinutes,
                      reminderDate: event.reminderDate,
                      dateOnlyTimeZoneIdentifier: event.dateOnlyTimeZoneIdentifier,
                      recurrenceRule: rule,
                      occurrenceReference: reference,
                      urlString: event.urlString)
    }

    private static func dayDistance(from start: Date, to end: Date, calendar: Calendar) -> Int {
        // A local day may start at 01:00. DateComponents(.day) between that
        // boundary and a later midnight can undercount by one calendar date.
        if calendar.component(.era, from: start) == calendar.component(.era, from: end),
           let first = calendar.ordinality(of: .day, in: .era, for: start),
           let last = calendar.ordinality(of: .day, in: .era, for: end) {
            return last - first
        }
        let firstNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: start) ?? start
        let lastNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: end) ?? end
        return calendar.dateComponents([.day], from: firstNoon, to: lastNoon).day ?? 0
    }

    private struct Schedule {
        let event: CalendarEvent
        let rule: EventRecurrenceRule
        let calendar: Calendar
        let firstDay: Date
        let cadenceDay: Date
        let firstWeek: Date
        let weekdays: Set<Int>
        let time: DateComponents
        let fractionalSecond: TimeInterval
        let allDayCount: Int
        let interval: Int
        let untilDay: Date?

        init(event: CalendarEvent, rule: EventRecurrenceRule, calendar: Calendar) {
            self.event = event
            self.rule = rule
            self.calendar = calendar
            interval = max(1, rule.interval)
            untilDay = rule.until.map { calendar.startOfDay(for: $0) }
            firstDay = calendar.startOfDay(for: event.startDate)
            cadenceDay = calendar.startOfDay(for: rule.anchorDate ?? event.startDate)
            if rule.frequency == .weekly {
                let weekday = calendar.component(.weekday, from: event.startDate)
                let daysSinceMonday = (calendar.component(.weekday, from: cadenceDay) + 5) % 7
                firstWeek = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -daysSinceMonday, to: cadenceDay) ?? cadenceDay)
                let selectedDays = Set(rule.weekdays.filter { (1...7).contains($0) })
                weekdays = selectedDays.isEmpty ? [weekday] : selectedDays
            } else {
                firstWeek = cadenceDay
                weekdays = []
            }
            time = event.isAllDay ? DateComponents() : calendar.dateComponents([.hour, .minute, .second], from: event.startDate)
            let seconds = event.startDate.timeIntervalSinceReferenceDate
            fractionalSecond = seconds - floor(seconds)
            allDayCount = event.isAllDay ? max(1, EventRecurrenceExpander.dayDistance(from: firstDay, to: event.endDate, calendar: calendar)) : 0
        }

        /// Visit scheduled dates directly: daily intervals or selected weekdays
        /// in active weeks. Querying a distant month does not walk from DTSTART.
        func forEachStart(from lowerBound: Date, to upperBound: Date, _ visit: (Date) -> Void) {
            guard lowerBound < upperBound else { return }
            switch rule.frequency {
            case .daily:
                let lowerOffset = EventRecurrenceExpander.dayDistance(from: cadenceDay, to: lowerBound, calendar: calendar)
                let endOffset = EventRecurrenceExpander.dayDistance(from: cadenceDay, to: upperBound, calendar: calendar)
                guard let offset = aligned(lowerOffset, before: endOffset),
                      var day = addingDays(offset, to: cadenceDay) else { return }
                var currentOffset = offset
                while currentOffset < endOffset {
                    if let start = startTime(on: day) { visit(start) }
                    guard interval < endOffset - currentOffset,
                          let next = addingDays(interval, to: day), next > day else { break }
                    currentOffset += interval
                    day = next
                }
            case .weekly:
                let lowerOffset = EventRecurrenceExpander.dayDistance(from: firstWeek, to: lowerBound, calendar: calendar)
                let endOffset = EventRecurrenceExpander.dayDistance(from: firstWeek, to: upperBound, calendar: calendar)
                guard let week = aligned(weekIndex(lowerOffset), before: weekIndex(endOffset - 1) + 1),
                      var weekStart = addingDays(week * 7, to: firstWeek) else { return }
                var currentWeek = week
                let lastWeek = weekIndex(endOffset - 1)
                while weekStart < upperBound {
                    guard let weekEnd = addingDays(7, to: weekStart), weekEnd > weekStart else { break }
                    let baseWeekday = calendar.component(.weekday, from: weekStart)
                    if calendar.component(.weekday, from: weekEnd) != baseWeekday {
                        // A historical date-line change can skip a whole local
                        // date. Keep the existing day-based interval semantics
                        // within that exceptional seven-day block.
                        var day = weekStart
                        while day < min(weekEnd, upperBound) {
                            if day >= lowerBound, weekdays.contains(calendar.component(.weekday, from: day)),
                               let start = startTime(on: day) { visit(start) }
                            guard let next = addingDays(1, to: day), next > day else { break }
                            day = next
                        }
                    } else {
                        let offsets = weekdays.map { ($0 - baseWeekday + 7) % 7 }.sorted()
                        for offset in offsets {
                            guard let day = addingDays(offset, to: weekStart), day >= lowerBound,
                                  day < upperBound, let start = startTime(on: day) else { continue }
                            visit(start)
                        }
                    }
                    guard interval <= lastWeek - currentWeek,
                          let next = addingDays(interval * 7, to: weekStart), next > weekStart else { break }
                    currentWeek += interval
                    weekStart = next
                }
            }
        }

        private func aligned(_ offset: Int, before end: Int) -> Int? {
            guard offset < end else { return nil }
            var remainder = offset % interval
            if remainder < 0 { remainder += interval }
            let extra = remainder == 0 ? 0 : interval - remainder
            guard extra < end - offset else { return nil }
            return offset + extra
        }

        private func weekIndex(_ days: Int) -> Int {
            days >= 0 ? days / 7 : (days - 6) / 7
        }

        private func addingDays(_ count: Int, to day: Date) -> Date? {
            guard let date = calendar.date(byAdding: .day, value: count, to: day) else { return nil }
            return calendar.startOfDay(for: date)
        }

        func start(on day: Date) -> Date? {
            guard day >= firstDay else { return nil }
            if let untilDay, day > untilDay { return nil }
            switch rule.frequency {
            case .daily:
                let days = EventRecurrenceExpander.dayDistance(from: cadenceDay, to: day, calendar: calendar)
                guard days % interval == 0 else { return nil }
            case .weekly:
                let days = EventRecurrenceExpander.dayDistance(from: firstWeek, to: day, calendar: calendar)
                guard weekdays.contains(calendar.component(.weekday, from: day)),
                      weekIndex(days) % interval == 0 else { return nil }
            }
            return startTime(on: day)
        }

        private func startTime(on day: Date) -> Date? {
            guard day >= firstDay else { return nil }
            if let untilDay, day > untilDay { return nil }
            let start: Date
            if event.isAllDay {
                start = calendar.startOfDay(for: day)
            } else {
                guard let wallTime = calendar.nextDate(after: day.addingTimeInterval(-1),
                                                       matching: time,
                                                       matchingPolicy: .nextTimePreservingSmallerComponents,
                                                       repeatedTimePolicy: .first,
                                                       direction: .forward),
                      calendar.isDate(wallTime, inSameDayAs: day) else { return nil }
                start = wallTime.addingTimeInterval(fractionalSecond)
            }
            return start >= event.startDate ? start : nil
        }

        func endDate(startingAt start: Date) -> Date {
            if event.isAllDay {
                let end = calendar.date(byAdding: .day, value: allDayCount, to: start) ?? start
                return calendar.startOfDay(for: end)
            }
            return start.addingTimeInterval(event.endDate.timeIntervalSince(event.startDate))
        }

        func overlaps(start: Date, end: Date, rangeStart: Date, rangeEndExclusive: Date, displayCalendar: Calendar) -> Bool {
            if event.isAllDay {
                return DateOnlyProjection.project(start, sourceTimeZoneIdentifier: calendar.timeZone.identifier, calendar: displayCalendar) < rangeEndExclusive
                    && DateOnlyProjection.project(end, sourceTimeZoneIdentifier: calendar.timeZone.identifier, calendar: displayCalendar) > rangeStart
            }
            return start < rangeEndExclusive && end > rangeStart
        }

        func occurrence(startingAt start: Date, endingAt end: Date) -> CalendarEvent {
            var occurrence = event
            occurrence.startDate = start
            occurrence.endDate = end
            if event.isAllDay {
                occurrence.dateOnlyTimeZoneIdentifier = calendar.timeZone.identifier
            }
            if let reminder = event.reminderDate {
                if event.isAllDay {
                    let days = EventRecurrenceExpander.dayDistance(from: firstDay, to: start, calendar: calendar)
                    occurrence.reminderDate = calendar.date(byAdding: .day, value: days, to: reminder)
                } else {
                    occurrence.reminderDate = start.addingTimeInterval(reminder.timeIntervalSince(event.startDate))
                }
            }
            let reference = CalendarEventOccurrenceReference(seriesID: event.id, originalStartDate: start)
            return EventRecurrenceExpander.identified(occurrence, reference: reference, rule: rule)
        }
    }
}
