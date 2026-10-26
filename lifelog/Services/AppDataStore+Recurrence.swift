import Foundation
import SwiftData
import WidgetKit
import os

extension AppDataStore {
    /// Count the visible starts for this series, including replacements moved
    /// into the selected display week. See docs/requirements.md §4.2.
    func calendarOccurrencesInWeek(containing event: CalendarEvent, calendar displayCalendar: Calendar? = nil) -> [CalendarEvent] {
        let seriesID = event.occurrenceReference?.seriesID ?? event.id
        guard event.sourceCalendarIdentifier == nil,
              let series = calendarEvents.first(where: { $0.id == seriesID }),
              series.sourceCalendarIdentifier == nil,
              series.recurrenceRule != nil else { return [] }
        let calendar = displayCalendar ?? CalendarWeekStart.current.calendar
        guard let week = calendar.dateInterval(of: .weekOfYear, for: event.displayStartDate(calendar: calendar)) else { return [] }
        // Match the week the user sees, including a replacement moved into it.
        // Restrict by display start, excluding events carried in from last week.
        return EventRecurrenceExpander.occurrences(
            events: [series], exceptions: calendarExceptions, rangeStart: week.start, rangeEndExclusive: week.end,
            calendar: calendar
        ).filter {
            let start = $0.displayStartDate(calendar: calendar)
            return start >= week.start && start < week.end
        }
    }

    func canDeleteCalendarWeek(containing event: CalendarEvent, calendar displayCalendar: Calendar? = nil) -> Bool {
        calendarOccurrencesInWeek(containing: event, calendar: displayCalendar).count > 1
    }

    /// Only this series' occurrences in the selected display week are skipped.
    /// Display week preferences do not change the rule's fixed interval anchor.
    func skipCalendarWeek(containing event: CalendarEvent, calendar displayCalendar: Calendar? = nil) {
        let seriesID = event.occurrenceReference?.seriesID ?? event.id
        guard event.sourceCalendarIdentifier == nil,
              let series = calendarEvents.first(where: { $0.id == seriesID }),
              series.sourceCalendarIdentifier == nil, series.recurrenceRule != nil else { return }
        let occurrences = calendarOccurrencesInWeek(containing: event, calendar: displayCalendar)
        guard !occurrences.isEmpty else {
            // A previous save may still be pending even though memory already
            // hides every occurrence in this week. Retrying must save it.
            saveContext()
            return
        }
        let changes = occurrences.compactMap { occurrence -> CalendarExceptionChange? in
            guard let reference = occurrence.occurrenceReference else { return nil }
            return CalendarExceptionChange(originalStart: reference.originalStartDate, replacement: nil)
        }
        do {
            // Fetch this series once, rather than issuing one fetch/save per day.
            let rows = try modelContext.fetch(FetchDescriptor<SDCalendarEventException>(
                predicate: #Predicate { $0.seriesID == seriesID }
            ))
            applyCalendarExceptionChanges(changes, to: series, existingRows: rows, refreshReminders: true)
        } catch {
            AppLogger.data.error("Calendar week exception persistence failed: \(error)")
        }
    }

    /// Future edits create separate masters for history, but "all" includes
    /// every recurring period descended from the same schedule (§4.2).
    func deleteCalendarSeries(containing event: CalendarEvent) {
        guard event.sourceCalendarIdentifier == nil else { return }
        let seriesID = event.occurrenceReference?.seriesID ?? event.id
        let master = calendarEvents.first { $0.id == seriesID }
        guard master?.sourceCalendarIdentifier == nil else { return }
        let groupID = master?.recurrenceRule?.seriesGroupID ?? event.recurrenceRule?.seriesGroupID ?? seriesID
        let segmentIDs = Set(calendarEvents.compactMap { candidate -> UUID? in
            guard candidate.sourceCalendarIdentifier == nil, let rule = candidate.recurrenceRule,
                  (rule.seriesGroupID ?? candidate.id) == groupID else { return nil }
            return candidate.id
        })
        deleteCalendarEvents(withIDs: segmentIDs.isEmpty ? [seriesID] : segmentIDs)
    }

    /// End before this original occurrence, retaining past events and exceptions.
    func endCalendarSeries(startingAt event: CalendarEvent) {
        guard let reference = event.occurrenceReference,
              var series = calendarEvents.first(where: { $0.id == reference.seriesID }),
              var rule = series.recurrenceRule else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: rule.timeZoneIdentifier) ?? .current
        guard let finalDay = calendar.date(byAdding: .day, value: -1,
                                          to: calendar.startOfDay(for: reference.originalStartDate)) else { return }
        let cutoff = calendar.startOfDay(for: finalDay)
        rule.until = min(rule.until ?? cutoff, cutoff)
        series.recurrenceRule = rule
        updateCalendarEvent(series)
    }

    func restoreCalendarException(_ exception: CalendarEventException) {
        let exceptionID = exception.id
        do {
            let descriptor = FetchDescriptor<SDCalendarEventException>(
                predicate: #Predicate { $0.id == exceptionID }
            )
            for row in try modelContext.fetch(descriptor) { modelContext.delete(row) }
            saveContext()
            let previous = calendarExceptions.first { $0.id == exceptionID }
            let updated = calendarExceptions.filter { $0.id != exceptionID }
            guard updated != calendarExceptions else { return }
            calendarExceptions = updated
            var reminderChanged = true
            if let previous, let replacement = previous.replacement,
               let series = calendarEvents.first(where: { $0.id == previous.seriesID }),
               let original = unmodifiedCalendarOccurrence(for: series, originalStart: previous.originalStartDate) {
                reminderChanged = !hasSameCalendarReminderContent(replacement, original)
            }
            calendarRecurrenceDidChange(refreshReminders: reminderChanged)
        } catch {
            AppLogger.data.error("Calendar exception restore failed: \(error)")
        }
    }

    func saveCalendarException(seriesID: UUID, originalStart: Date, replacement: CalendarEvent?,
                               refreshReminders: Bool = true) {
        guard let series = calendarEvents.first(where: { $0.id == seriesID }),
              series.recurrenceRule != nil, series.sourceCalendarIdentifier == nil else { return }
        do {
            // Preserve the targeted retry path for one occurrence. A matching
            // memory snapshot is not evidence that its row has been saved.
            let descriptor = FetchDescriptor<SDCalendarEventException>(predicate: #Predicate {
                $0.seriesID == seriesID && $0.originalStartDate == originalStart
            })
            let rows = try modelContext.fetch(descriptor)
            let change = CalendarExceptionChange(originalStart: originalStart, replacement: replacement)
            applyCalendarExceptionChanges([change], to: series, existingRows: rows,
                                          refreshReminders: refreshReminders)
        } catch {
            AppLogger.data.error("Calendar exception persistence failed: \(error)")
        }
    }

    private struct CalendarExceptionChange {
        let originalStart: Date
        var replacement: CalendarEvent?
    }

    /// One persistence transaction and one published snapshot, including when a
    /// week contains a mixture of ordinary, changed and already skipped slots.
    private func applyCalendarExceptionChanges(_ changes: [CalendarExceptionChange], to series: CalendarEvent,
                                              existingRows: [SDCalendarEventException], refreshReminders: Bool) {
        let rowsByStart = Dictionary(grouping: existingRows, by: \.originalStartDate)
        let previousByStart = calendarExceptions
            .filter { $0.seriesID == series.id }
            .reduce(into: [Date: CalendarEventException]()) { $0[$1.originalStartDate] = $1 }
        var desiredByStart: [Date: CalendarEventException] = [:]
        var changedReminder = false

        for change in changes {
            let previous = previousByStart[change.originalStart]
            let matches = rowsByStart[change.originalStart] ?? []
            let existing = matches.first { $0.id == previous?.id }
                ?? matches.min { $0.id.uuidString < $1.id.uuidString }
            var replacement = change.replacement
            // Store values only; resolved identity and rule come from the series.
            replacement?.occurrenceReference = nil
            replacement?.recurrenceRule = nil
            let desired = CalendarEventException(id: existing?.id ?? previous?.id ?? UUID(), seriesID: series.id,
                                                 originalStartDate: change.originalStart, replacement: replacement)
            desiredByStart[change.originalStart] = desired
            if let existing {
                if CalendarEventException(sd: existing) != desired { existing.update(from: desired) }
                // The logical identity is series + original slot. Reconcile any
                // duplicate rows without creating another exception on retry.
                for duplicate in matches where duplicate.id != existing.id { modelContext.delete(duplicate) }
            } else {
                modelContext.insert(SDCalendarEventException(domain: desired))
            }
            if previous != desired {
                changedReminder = changedReminder || calendarExceptionChangesReminder(
                    from: previous, to: desired, series: series
                )
            }
        }
        saveContext()

        // Retain unaffected order and entries, replacing each logical slot once.
        var updated: [CalendarEventException] = []
        var includedStarts: Set<Date> = []
        for exception in calendarExceptions {
            if exception.seriesID == series.id, let desired = desiredByStart[exception.originalStartDate] {
                if includedStarts.insert(exception.originalStartDate).inserted { updated.append(desired) }
            } else {
                updated.append(exception)
            }
        }
        for change in changes where includedStarts.insert(change.originalStart).inserted {
            if let desired = desiredByStart[change.originalStart] { updated.append(desired) }
        }
        guard updated != calendarExceptions else { return }
        calendarExceptions = updated
        if refreshReminders { calendarRecurrenceDidChange(refreshReminders: changedReminder) }
    }

    private func calendarExceptionChangesReminder(from previous: CalendarEventException?,
                                                 to desired: CalendarEventException,
                                                 series: CalendarEvent) -> Bool {
        guard let replacement = desired.replacement else {
            // An already skipped slot has no reminder to change.
            return previous == nil || previous?.replacement != nil
        }
        if let previous {
            guard let previousReplacement = previous.replacement else { return true }
            return !hasSameCalendarReminderContent(previousReplacement, replacement)
        }
        guard let original = unmodifiedCalendarOccurrence(for: series, originalStart: desired.originalStartDate) else {
            return true
        }
        return !hasSameCalendarReminderContent(original, replacement)
    }

    /// Comparing a new override to its one original slot avoids expanding the
    /// notification horizon for URL/detail-only edits, including absolute alarms.
    private func unmodifiedCalendarOccurrence(for series: CalendarEvent, originalStart: Date) -> CalendarEvent? {
        EventRecurrenceExpander.originalOccurrence(of: series, startingAt: originalStart)
    }

    func calendarRecurrenceDidChange(refreshReminders: Bool = true) {
        eventsCache.removeAll()
        if refreshReminders {
            rescheduleExternalEventNotifications()
            rescheduleTodayOverviewReminderIfNeeded()
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
    }

    /// Top up bounded, one-time notifications when the app becomes active.
    func refreshCalendarRemindersIfNeeded(referenceDate: Date = Date()) {
        if ExternalReminderRefreshTiming.shouldRefresh(nextFireDate: nextExternalReminderRefreshDate,
                                                       at: referenceDate) {
            rescheduleExternalEventNotifications(referenceDate: referenceDate)
        }
    }
}
