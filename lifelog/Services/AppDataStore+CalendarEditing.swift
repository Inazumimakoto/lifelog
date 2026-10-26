import Foundation
import SwiftData

extension AppDataStore {
    /// Stage a bounded edit of stored masters and explicit exceptions (§4.2).
    func prepareCalendarEventEdit(original: CalendarEvent, edited: CalendarEvent,
                                  scope: CalendarEventEditScope) throws -> CalendarEventEditPlan {
        guard original.sourceCalendarIdentifier == nil, edited.sourceCalendarIdentifier == nil else { throw CalendarEventEditError.readOnly }
        guard edited.endDate > edited.startDate else { throw CalendarEventEditError.invalidDates }
        let seriesID = original.occurrenceReference?.seriesID ?? original.id
        guard let master = calendarEvents.first(where: { $0.id == seriesID }), master.sourceCalendarIdentifier == nil else { throw CalendarEventEditError.missingEvent }
        if original.occurrenceReference == nil && scope != .series { throw CalendarEventEditError.invalidScope }
        let sourceExceptions = calendarExceptions.filter { $0.seriesID == seriesID }
        let selectedStart = original.occurrenceReference?.originalStartDate
        let selectedOriginal: CalendarEvent
        if let selectedStart {
            guard let slot = EventRecurrenceExpander.originalOccurrence(of: master, startingAt: selectedStart) else { throw CalendarEventEditError.stalePlan }
            let exception = sourceExceptions.last { $0.originalStartDate == selectedStart }
            guard exception == nil || exception?.replacement != nil else { throw CalendarEventEditError.stalePlan }
            let current = exception?.replacement.map { CalendarEditValues.identified($0, as: slot) } ?? slot
            guard current == original else { throw CalendarEventEditError.stalePlan }
            selectedOriginal = slot
        } else {
            guard master == original else { throw CalendarEventEditError.stalePlan }
            selectedOriginal = master
        }
        let ruleChanged = original.recurrenceRule != edited.recurrenceRule
        if scope == .occurrence && ruleChanged { throw CalendarEventEditError.recurrenceRequiresSeries }
        var events = calendarEvents
        var exceptions = calendarExceptions
        var unmatched: [CalendarEventException] = []
        var standalone: [CalendarEvent] = []
        var exceptionReminderChanged = false
        let sourceCalendar = CalendarEditValues.calendar(for: master)
        let changes = CalendarEditValues(original: original, edited: edited, calendar: sourceCalendar)
        if edited == original {
            return CalendarEventEditPlan(scope: scope, unmatchedExceptions: [], originalEvents: calendarEvents,
                                         originalExceptions: calendarExceptions, resultingEvents: calendarEvents,
                                         resultingExceptions: calendarExceptions, preservedStandaloneEvents: [], refreshReminders: false)
        }

        if scope == .occurrence {
            guard let selectedStart else { throw CalendarEventEditError.invalidScope }
            let previous = sourceExceptions.last { $0.originalStartDate == selectedStart }
            let replacement = CalendarEditValues.stored(edited, id: edited.id, rule: nil)
            let exception = CalendarEventException(id: previous?.id ?? UUID(), seriesID: seriesID,
                                                   originalStartDate: selectedStart, replacement: replacement)
            exceptions.removeAll { $0.seriesID == seriesID && $0.originalStartDate == selectedStart }
            exceptions.append(exception)
            return CalendarEventEditPlan(scope: scope, unmatchedExceptions: [], originalEvents: calendarEvents,
                                         originalExceptions: calendarExceptions, resultingEvents: events,
                                         resultingExceptions: exceptions, preservedStandaloneEvents: [],
                                         refreshReminders: !hasSameCalendarReminderContent(original, edited))
        }

        var updated = changes.applying(to: scope == .future ? selectedOriginal : master)
        var rule = ruleChanged ? edited.recurrenceRule : master.recurrenceRule
        if var value = rule {
            // A new period has its own occurrence IDs, while deleting the whole
            // schedule must still reach every period created from this master.
            value.seriesGroupID = master.recurrenceRule?.seriesGroupID ?? master.id
            if !ruleChanged, value.frequency == .weekly, value.weekdays.isEmpty,
               sourceCalendar.component(.weekday, from: updated.startDate) != sourceCalendar.component(.weekday, from: master.startDate) {
                // Legacy empty weekday lists mean the original template's day;
                // a date edit must not silently change that selected weekday.
                value.weekdays = [sourceCalendar.component(.weekday, from: master.startDate)]
            }
            let sameCadence = master.recurrenceRule?.frequency == value.frequency && master.recurrenceRule?.interval == value.interval
            if sameCadence {
                if scope == .future || master.recurrenceRule?.anchorDate != nil {
                    value.anchorDate = changes.shift(master.recurrenceRule?.anchorDate ?? master.startDate)
                } else {
                    value.anchorDate = nil
                }
            } else {
                value.anchorDate = scope == .future ? updated.startDate : nil
            }
            rule = value
        }
        let targetID = scope == .future ? UUID() : master.id
        updated = CalendarEditValues.stored(updated, id: targetID, rule: rule)
        let affected = sourceExceptions.filter { scope == .series || $0.originalStartDate >= (selectedStart ?? master.startDate) }
        exceptions.removeAll { $0.seriesID == seriesID && (scope == .series || $0.originalStartDate >= (selectedStart ?? master.startDate)) }

        if scope == .future {
            guard let selectedStart, var oldRule = master.recurrenceRule,
                  let previousDay = sourceCalendar.date(byAdding: .day, value: -1, to: sourceCalendar.startOfDay(for: selectedStart)) else { throw CalendarEventEditError.invalidScope }
            var past = master
            oldRule.seriesGroupID = master.recurrenceRule?.seriesGroupID ?? master.id
            let cutoff = sourceCalendar.startOfDay(for: previousDay)
            oldRule.until = min(oldRule.until ?? cutoff, cutoff)
            past.recurrenceRule = oldRule
            events = events.map { $0.id == master.id ? past : $0 }
        }

        if rule == nil {
            // The chosen visible occurrence is already the requested standalone;
            // never preserve its old override a second time.
            updated = CalendarEditValues.stored(edited, id: targetID, rule: nil)
            for exception in affected where exception.originalStartDate != selectedStart { unmatched.append(exception) }
        } else {
            var migratedStarts: Set<Date> = []
            for exception in affected.sorted(by: { $0.originalStartDate < $1.originalStartDate }) {
                guard let oldSlot = EventRecurrenceExpander.originalOccurrence(of: master, startingAt: exception.originalStartDate),
                      let newSlot = changes.mappedSlot(oldSlot, in: updated),
                      migratedStarts.insert(newSlot.startDate).inserted else {
                    if exception.originalStartDate == selectedStart, exception.replacement != nil {
                        var selected = exception
                        selected.replacement = CalendarEditValues.stored(edited, id: edited.id, rule: nil)
                        unmatched.append(selected)
                    } else { unmatched.append(exception) }
                    continue
                }
                var replacement: CalendarEvent?
                if let oldReplacement = exception.replacement {
                    let overrides = CalendarEditValues(original: oldSlot, edited: oldReplacement, calendar: sourceCalendar)
                    var migrated = overrides.applying(to: newSlot, absoluteStart: true)
                    if exception.originalStartDate == selectedStart {
                        migrated = changes.applying(to: migrated, absoluteStart: true)
                    }
                    replacement = CalendarEditValues.stored(migrated, id: newSlot.id, rule: nil)
                    exceptionReminderChanged = exceptionReminderChanged || !hasSameCalendarReminderContent(oldReplacement, migrated)
                }
                exceptions.append(CalendarEventException(id: exception.id, seriesID: targetID,
                                                         originalStartDate: newSlot.startDate, replacement: replacement))
            }
        }
        if scope == .future { events.append(updated) }
        else { events = events.map { $0.id == master.id ? updated : $0 } }
        for exception in unmatched {
            guard let replacement = exception.replacement else { continue }
            // It is a new independent record. Reusing the old slot UUID could
            // collide with an earlier standalone retained from the same slot.
            standalone.append(CalendarEditValues.stored(replacement, id: UUID(), rule: nil))
        }
        let reminderChanged = scope == .future || ruleChanged || !unmatched.isEmpty || exceptionReminderChanged || !hasSameCalendarReminderContent(master, updated)
        return CalendarEventEditPlan(scope: scope,
                                     unmatchedExceptions: unmatched.sorted { $0.originalStartDate < $1.originalStartDate },
                                     originalEvents: calendarEvents, originalExceptions: calendarExceptions,
                                     resultingEvents: events, resultingExceptions: exceptions,
                                     preservedStandaloneEvents: standalone, refreshReminders: reminderChanged)
    }

    func applyCalendarEventEdit(_ plan: CalendarEventEditPlan, preservingUnmatchedChanges: Bool = true) throws {
        try applyCalendarEventEdit(plan, preservingUnmatchedChanges: preservingUnmatchedChanges, save: { try $0.save() })
    }

    /// The injectable save boundary also lets tests prove that failed saves do
    /// not publish partial edits or roll back unrelated main-context changes.
    func applyCalendarEventEdit(_ plan: CalendarEventEditPlan, preservingUnmatchedChanges: Bool = true,
                               save: (ModelContext) throws -> Void) throws {
        guard calendarEvents == plan.originalEvents, calendarExceptions == plan.originalExceptions else { throw CalendarEventEditError.stalePlan }
        var resultingEvents = plan.resultingEvents
        if preservingUnmatchedChanges { resultingEvents.append(contentsOf: plan.preservedStandaloneEvents) }
        guard resultingEvents != plan.originalEvents || plan.resultingExceptions != plan.originalExceptions else { return }
        let context = ModelContext(modelContext.container)
        context.autosaveEnabled = false
        let eventRows = try context.fetch(FetchDescriptor<SDCalendarEvent>())
        let exceptionRows = try context.fetch(FetchDescriptor<SDCalendarEventException>())
        guard Set(eventRows.map { CalendarEvent(sd: $0) }) == Set(plan.originalEvents),
              Set(exceptionRows.map { CalendarEventException(sd: $0) }) == Set(plan.originalExceptions) else { throw CalendarEventEditError.stalePlan }
        let desiredEvents = Dictionary(uniqueKeysWithValues: resultingEvents.map { ($0.id, $0) })
        let desiredExceptions = Dictionary(uniqueKeysWithValues: plan.resultingExceptions.map { ($0.id, $0) })
        let existingIDs = Set(eventRows.map(\.id)), existingExceptionIDs = Set(exceptionRows.map(\.id))
        for row in eventRows {
            if let desired = desiredEvents[row.id] {
                if CalendarEvent(sd: row) != desired { row.update(from: desired) }
            } else { context.delete(row) }
        }
        for event in resultingEvents where !existingIDs.contains(event.id) { context.insert(SDCalendarEvent(domain: event)) }
        for row in exceptionRows {
            if let desired = desiredExceptions[row.id] {
                if CalendarEventException(sd: row) != desired { row.update(from: desired) }
            } else { context.delete(row) }
        }
        for exception in plan.resultingExceptions where !existingExceptionIDs.contains(exception.id) {
            context.insert(SDCalendarEventException(domain: exception))
        }
        do { try save(context) }
        catch { context.rollback(); throw error }

        if calendarEvents != resultingEvents { calendarEvents = resultingEvents }
        if calendarExceptions != plan.resultingExceptions { calendarExceptions = plan.resultingExceptions }
        let previousByID = Dictionary(uniqueKeysWithValues: plan.originalEvents.map { ($0.id, $0) })
        for previous in plan.originalEvents where previous.recurrenceRule == nil && (desiredEvents[previous.id] == nil || desiredEvents[previous.id]?.recurrenceRule != nil) {
            calendarNotificationService.cancelEventReminder(eventId: previous.id)
        }
        for event in resultingEvents where event.recurrenceRule == nil {
            if let previous = previousByID[event.id], hasSameCalendarReminderContent(previous, event) { continue }
            scheduleEventNotification(event)
        }
        calendarRecurrenceDidChange(refreshReminders: plan.refreshReminders)
    }
}

/// Session deltas and exception deltas share the same field inheritance policy.
private struct CalendarEditValues {
    let original: CalendarEvent
    let edited: CalendarEvent
    let calendar: Calendar

    var startChanged: Bool { original.startDate != edited.startDate }
    var durationChanged: Bool {
        original.isAllDay != edited.isAllDay || duration(original) != duration(edited)
    }

    func shift(_ date: Date) -> Date {
        guard startChanged else { return date }
        let delta = calendar.dateComponents([.day, .hour, .minute, .second, .nanosecond], from: original.startDate, to: edited.startDate)
        return calendar.date(byAdding: delta, to: date) ?? date
    }

    func applying(to base: CalendarEvent, absoluteStart: Bool = false) -> CalendarEvent {
        var value = base
        if original.title != edited.title { value.title = edited.title }
        if original.detail != edited.detail { value.detail = edited.detail }
        if original.urlString != edited.urlString { value.urlString = edited.urlString }
        if original.calendarName != edited.calendarName { value.calendarName = edited.calendarName }
        if original.isAllDay != edited.isAllDay { value.isAllDay = edited.isAllDay }
        if original.dateOnlyTimeZoneIdentifier != edited.dateOnlyTimeZoneIdentifier { value.dateOnlyTimeZoneIdentifier = edited.dateOnlyTimeZoneIdentifier }
        if startChanged { value.startDate = absoluteStart ? edited.startDate : shift(base.startDate) }
        if startChanged || durationChanged {
            let length = durationChanged ? duration(edited) : duration(base)
            value.endDate = value.isAllDay
                ? calendar.startOfDay(for: calendar.date(byAdding: .day, value: Int(length), to: calendar.startOfDay(for: value.startDate)) ?? value.startDate)
                : value.startDate.addingTimeInterval(length)
        }
        if original.reminderMinutes != edited.reminderMinutes || original.reminderDate != edited.reminderDate {
            value.reminderMinutes = edited.reminderMinutes
            if let reminder = edited.reminderDate, !absoluteStart {
                let offset = calendar.dateComponents([.day, .hour, .minute, .second, .nanosecond], from: edited.startDate, to: reminder)
                value.reminderDate = calendar.date(byAdding: offset, to: value.startDate)
            } else { value.reminderDate = edited.reminderDate }
        }
        return value
    }

    func mappedSlot(_ old: CalendarEvent, in master: CalendarEvent) -> CalendarEvent? {
        let targetCalendar = Self.calendar(for: master)
        let moved = shift(old.startDate)
        var day = calendar.dateComponents([.year, .month, .day], from: moved)
        day.timeZone = targetCalendar.timeZone
        guard let localDay = targetCalendar.date(from: day) else { return nil }
        let start: Date
        if master.isAllDay { start = targetCalendar.startOfDay(for: localDay) }
        else {
            let time = targetCalendar.dateComponents([.hour, .minute, .second], from: master.startDate)
            guard let match = targetCalendar.nextDate(after: targetCalendar.startOfDay(for: localDay).addingTimeInterval(-1),
                                                      matching: time, matchingPolicy: .nextTimePreservingSmallerComponents,
                                                      repeatedTimePolicy: .first, direction: .forward),
                  targetCalendar.isDate(match, inSameDayAs: localDay) else { return nil }
            let seconds = master.startDate.timeIntervalSinceReferenceDate
            start = match.addingTimeInterval(seconds - floor(seconds))
        }
        return EventRecurrenceExpander.originalOccurrence(of: master, startingAt: start, calendar: targetCalendar)
    }

    private func duration(_ event: CalendarEvent) -> TimeInterval {
        guard event.isAllDay else { return event.endDate.timeIntervalSince(event.startDate) }
        let source = Self.calendar(for: event)
        let first = source.ordinality(of: .day, in: .era, for: event.startDate) ?? 0
        let end = source.ordinality(of: .day, in: .era, for: event.endDate) ?? first + 1
        return Double(max(1, end - first))
    }

    static func calendar(for event: CalendarEvent) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: event.recurrenceRule?.timeZoneIdentifier ?? event.dateOnlyTimeZoneIdentifier ?? "") ?? .current
        return value
    }

    static func identified(_ value: CalendarEvent, as slot: CalendarEvent) -> CalendarEvent {
        var result = stored(value, id: slot.id, rule: slot.recurrenceRule)
        result.occurrenceReference = slot.occurrenceReference
        return result
    }

    static func stored(_ value: CalendarEvent, id: UUID, rule: EventRecurrenceRule?) -> CalendarEvent {
        CalendarEvent(id: id, title: value.title, detail: value.detail, startDate: value.startDate, endDate: value.endDate,
                      calendarName: value.calendarName, isAllDay: value.isAllDay, sourceCalendarIdentifier: nil,
                      reminderMinutes: value.reminderMinutes, reminderDate: value.reminderDate,
                      dateOnlyTimeZoneIdentifier: value.dateOnlyTimeZoneIdentifier, recurrenceRule: rule,
                      urlString: value.urlString)
    }
}
