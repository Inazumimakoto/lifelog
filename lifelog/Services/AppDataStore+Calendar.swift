//
//  AppDataStore+Calendar.swift
//  lifelog
//

import Foundation
import EventKit
import UserNotifications
import SwiftData
import WidgetKit
import os

extension AppDataStore {

    // MARK: - Calendar

    func events(on date: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        if eventsCacheCalendar != calendar {
            eventsCache.removeAll()
            eventsCacheCalendar = calendar
        }
        let dayStart = calendar.startOfDay(for: date)

        // キャッシュチェック
        if let cached = eventsCache[dayStart] {
            return cached
        }

        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        // マージ・重複排除・整列の方針は共有の EventQuerying に一本化する。
        // 内部/外部それぞれ当日と重なるものに絞ってからマージする。
        let result = events(from: dayStart, to: dayEnd, calendar: calendar)

        // キャッシュに保存
        eventsCache[dayStart] = result
        return result
    }

    /// All schedule consumers resolve rules and exceptions over a bounded range (§4.2).
    func events(from start: Date, to end: Date, calendar: Calendar = .current) -> [CalendarEvent] {
        EventQuerying.resolved(internalEvents: calendarEvents, exceptions: calendarExceptions,
                              externalEvents: externalCalendarEvents,
                              rangeStart: start, rangeEndExclusive: end, calendar: calendar)
    }

    func addCalendarEvent(_ event: CalendarEvent) {
        guard event.sourceCalendarIdentifier == nil, event.occurrenceReference == nil else { return }
        // Retrying an add after a failed fetch/save must not duplicate its ID.
        let changed: Bool
        if let index = calendarEvents.firstIndex(where: { $0.id == event.id }) {
            changed = calendarEvents[index] != event
            if changed {
                eventsCache.removeAll()
                calendarEvents[index] = event
            }
        } else {
            changed = true
            eventsCache.removeAll()
            calendarEvents.append(event)
        }
        persistCalendarEvent(event)
        guard changed else { return }
        scheduleEventNotification(event)
        rescheduleTodayOverviewReminderIfNeeded()
        WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
    }

    func updateCalendarEvent(_ event: CalendarEvent) {
        guard event.sourceCalendarIdentifier == nil else { return }
        if let reference = event.occurrenceReference {
            saveCalendarException(seriesID: reference.seriesID, originalStart: reference.originalStartDate,
                                  replacement: event)
            return
        }
        guard let index = calendarEvents.firstIndex(where: { $0.id == event.id }) else { return }
        let previous = calendarEvents[index]
        let wasRecurring = previous.recurrenceRule != nil
        let changed = previous != event
        let reminderChanged = previous.recurrenceRule != event.recurrenceRule ||
            !hasSameCalendarReminderContent(previous, event)
        if changed {
            eventsCache.removeAll()
            calendarEvents[index] = event
        }
        // Even an equal memory snapshot can have an earlier unsaved change or
        // failed fetch. Retry just this row without publishing it a second time.
        persistCalendarEvent(event)
        guard changed else { return }
        if reminderChanged {
            scheduleEventNotification(event)
            if wasRecurring && event.recurrenceRule == nil { rescheduleExternalEventNotifications() }
            rescheduleTodayOverviewReminderIfNeeded()
            WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
        }
    }

    /// Identity/rule changes are handled by callers. Memo and URL edits do not
    /// change reminder requests and must not expand eighteen months of a series.
    func hasSameCalendarReminderContent(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        lhs.title == rhs.title && lhs.startDate == rhs.startDate && lhs.endDate == rhs.endDate &&
            lhs.calendarName == rhs.calendarName && lhs.isAllDay == rhs.isAllDay &&
            lhs.sourceCalendarIdentifier == rhs.sourceCalendarIdentifier &&
            lhs.reminderMinutes == rhs.reminderMinutes && lhs.reminderDate == rhs.reminderDate &&
            lhs.dateOnlyTimeZoneIdentifier == rhs.dateOnlyTimeZoneIdentifier
    }

    /// Generated occurrence IDs must never be interpreted as stored series IDs.
    func deleteCalendarEvent(_ event: CalendarEvent) {
        guard event.sourceCalendarIdentifier == nil else { return }
        if let reference = event.occurrenceReference {
            saveCalendarException(seriesID: reference.seriesID, originalStart: reference.originalStartDate,
                                  replacement: nil)
        } else {
            deleteCalendarEvent(event.id)
        }
    }

    func deleteCalendarEvent(_ eventID: UUID) {
        deleteCalendarEvents(withIDs: [eventID])
    }

    /// Split segments are committed together, then removed from published state.
    /// A fresh context sees rows inserted by scoped edits immediately (§4.2).
    func deleteCalendarEvents(withIDs eventIDs: Set<UUID>) {
        do {
            try deleteCalendarEvents(withIDs: eventIDs, save: { try $0.save() })
        } catch {
            AppLogger.data.error("Calendar event deletion failed: \(error)")
        }
    }

    /// The save hook verifies failure/retry behavior without touching user stores.
    func deleteCalendarEvents(withIDs eventIDs: Set<UUID>, save: (ModelContext) throws -> Void) throws {
        guard !eventIDs.isEmpty else { return }
        let context = ModelContext(modelContext.container)
        context.autosaveEnabled = false
        let requestedIDs = Array(eventIDs)
        let eventRows = try context.fetch(FetchDescriptor<SDCalendarEvent>(predicate: #Predicate {
            requestedIDs.contains($0.id)
        }))
        let pendingModels = modelContext.insertedModelsArray + modelContext.changedModelsArray
        let pendingEvents = pendingModels.compactMap { $0 as? SDCalendarEvent }
            .filter { eventIDs.contains($0.id) }
        let protectedIDs = Set(eventRows.filter { $0.sourceCalendarIdentifier != nil }.map(\.id))
            .union(calendarEvents.filter { eventIDs.contains($0.id) && $0.sourceCalendarIdentifier != nil }.map(\.id))
            .union(pendingEvents.filter { $0.sourceCalendarIdentifier != nil }.map(\.id))
        let deletableIDs = eventIDs.subtracting(protectedIDs)
        guard !deletableIDs.isEmpty else { return }
        let seriesIDs = Array(deletableIDs)
        let exceptionRows = try context.fetch(FetchDescriptor<SDCalendarEventException>(predicate: #Predicate {
            seriesIDs.contains($0.seriesID)
        }))
        for row in eventRows where deletableIDs.contains(row.id) { context.delete(row) }
        for row in exceptionRows { context.delete(row) }
        let persistedChange = context.hasChanges
        if persistedChange {
            do { try save(context) }
            catch { context.rollback(); throw error }
        }
        let remainingEvents = calendarEvents.filter { !deletableIDs.contains($0.id) }
        let remainingExceptions = calendarExceptions.filter { !deletableIDs.contains($0.seriesID) }
        let pendingTargets = pendingEvents.filter { deletableIDs.contains($0.id) }
        let deletedExceptionIDs = Set(exceptionRows.map(\.id))
        let pendingExceptions = pendingModels.compactMap { $0 as? SDCalendarEventException }
            .filter { deletableIDs.contains($0.seriesID) || deletedExceptionIDs.contains($0.id) }
        let memoryChanged = remainingEvents != calendarEvents || remainingExceptions != calendarExceptions
        guard persistedChange || memoryChanged || !pendingTargets.isEmpty || !pendingExceptions.isEmpty else { return }
        // A failed earlier save can leave an inserted/dirty target only in the
        // main context. Cancel just those rows so its later autosave cannot
        // recreate a successfully deleted segment; unrelated edits stay pending.
        for pending in pendingTargets { modelContext.delete(pending) }
        for pending in pendingExceptions { modelContext.delete(pending) }
        if remainingEvents != calendarEvents { calendarEvents = remainingEvents }
        if remainingExceptions != calendarExceptions { calendarExceptions = remainingExceptions }
        eventsCache.removeAll()
        for eventID in deletableIDs { calendarNotificationService.cancelEventReminder(eventId: eventID) }
        rescheduleExternalEventNotifications()
        rescheduleTodayOverviewReminderIfNeeded()
        WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
    }

    func updateExternalCalendarEvents(
        _ events: [CalendarEvent],
        range: ExternalCalendarRange? = nil,
        referenceDate: Date = Date()
    ) {
        let sortedEvents = EventQuerying.mergedDedupedSorted(internalEvents: [], externalEvents: events)
        if let range, range != externalCalendarRange {
            externalCalendarRange = range
            persistExternalCalendarRange()
        }
        // Unchanged calendar refreshes should not invalidate every timeline,
        // rewrite the shared JSON cache, or recreate all external reminders.
        guard sortedEvents != externalCalendarEvents else {
            // The next 48 reminders form a moving window. Once its first
            // reminder fires, replenish it even if EventKit data is identical.
            if ExternalReminderRefreshTiming.shouldRefresh(
                nextFireDate: nextExternalReminderRefreshDate, at: referenceDate
            ) {
                rescheduleExternalEventNotifications(referenceDate: referenceDate)
                rescheduleTodayOverviewReminderIfNeeded(referenceDate: referenceDate)
            }
            return
        }
        eventsCache.removeAll()
        externalCalendarEvents = sortedEvents
        persistExternalCalendarEvents()
        rescheduleExternalEventNotifications(referenceDate: referenceDate)
        rescheduleTodayOverviewReminderIfNeeded(referenceDate: referenceDate)
    }

    func currentExternalCalendarRange() -> ExternalCalendarRange? {
        externalCalendarRange
    }

    @discardableResult
    func syncExternalCalendarsIfAuthorized(
        requestPermissionIfNeeded: Bool = false,
        anchorDate: Date = Date()
    ) async -> Bool {
        guard !PersistenceController.isSimulatorDemoMode else { return false }
        let calendarService = CalendarEventService()
        let granted = await calendarService.requestAccessIfNeeded(shouldPrompt: requestPermissionIfNeeded)
        guard granted else { return false }

        calendarService.refreshCalendarLinks(store: self)
        let range = currentExternalCalendarRange() ?? ExternalCalendarSyncPolicy.desiredRange(for: anchorDate)

        do {
            let ekEvents = try await calendarService.fetchEvents(from: range.start, to: range.end)
            let external = ExternalCalendarEventMapper(links: appState.calendarCategoryLinks).map(ekEvents)
            updateExternalCalendarEvents(external, range: range)
            updateLastCalendarSync(date: Date())
            return true
        } catch {
            return false
        }
    }

    var lastCalendarSyncDate: Date? {
        appState.lastCalendarSyncDate
    }

    func updateLastCalendarSync(date: Date) {
        appState.lastCalendarSyncDate = date
        persistAppState()
    }

    func updateCalendarLinks(with calendars: [EKCalendar]) {
        // docs/requirements.md §Settings: list only calendars still on this
        // device, while preserving each calendar's chosen category and order.
        let availableIdentifiers = Set(calendars.map { $0.calendarIdentifier as String })
        var seenIdentifiers = Set<String>()
        var links = appState.calendarCategoryLinks.filter {
            availableIdentifiers.contains($0.calendarIdentifier) &&
                seenIdentifiers.insert($0.calendarIdentifier).inserted
        }
        for calendar in calendars {
            let colorHex = calendar.cgColor?.hexString
            if let index = links.firstIndex(where: { $0.calendarIdentifier == calendar.calendarIdentifier }) {
                links[index].calendarTitle = calendar.title
                links[index].colorHex = colorHex
            } else {
                // Auto-map category based on calendar name
                let autoCategory = autoMapCategory(for: calendar.title)
                let link = CalendarCategoryLink(calendarIdentifier: calendar.calendarIdentifier,
                                                calendarTitle: calendar.title,
                                                categoryId: autoCategory,
                                                colorHex: colorHex)
                links.append(link)
            }
        }
        guard links != appState.calendarCategoryLinks else { return }
        appState.calendarCategoryLinks = links
        persistAppState()
    }

    /// Auto-map calendar name to category based on keywords
    private func autoMapCategory(for calendarName: String) -> String? {
        let name = calendarName.lowercased()

        // Hide holidays
        if name.contains("祝日") || name.contains("holiday") {
            return nil
        }

        // Work-related keywords
        let workKeywords = ["仕事", "work", "業務", "会社", "office", "ビジネス", "business", "ミーティング", "meeting"]
        for keyword in workKeywords {
            if name.contains(keyword) {
                return "仕事"
            }
        }

        // Travel-related keywords
        let travelKeywords = ["旅行", "travel", "trip", "vacation", "休暇"]
        for keyword in travelKeywords {
            if name.contains(keyword) {
                return "旅行"
            }
        }

        // Hobby-related keywords
        let hobbyKeywords = ["趣味", "hobby", "プライベート", "private", "個人", "personal"]
        for keyword in hobbyKeywords {
            if name.contains(keyword) {
                return "趣味"
            }
        }

        // Default: use the default category
        return CategoryPalette.defaultCategoryName
    }

    func updateCalendarLinkCategory(calendarIdentifier: String, categoryName: String?) {
        guard let index = appState.calendarCategoryLinks.firstIndex(where: { $0.calendarIdentifier == calendarIdentifier }) else {
            return
        }
        guard appState.calendarCategoryLinks[index].categoryId != categoryName else { return }
        appState.calendarCategoryLinks[index].categoryId = categoryName
        persistAppState()

        // Apply selection changes immediately to the cached source events.
        // EventKit refresh can restore events when a hidden calendar is shown.
        let updatedEvents = externalCalendarEvents.compactMap { event -> CalendarEvent? in
            guard event.sourceCalendarIdentifier == calendarIdentifier else { return event }
            guard let categoryName else { return nil }
            var updated = event
            updated.calendarName = categoryName
            return updated
        }
        updateExternalCalendarEvents(updatedEvents)
    }

    func renameCalendarCategory(from oldName: String, to newName: String) {
        let source = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard source.isEmpty == false, target.isEmpty == false, source != target else { return }

        eventsCache.removeAll()

        var hasInternalChanges = false
        for index in calendarEvents.indices where calendarEvents[index].calendarName == source {
            calendarEvents[index].calendarName = target
            hasInternalChanges = true
        }
        if hasInternalChanges {
            persistCalendarEvents()
        }

        for exception in calendarExceptions {
            guard var replacement = exception.replacement, replacement.calendarName == source else { continue }
            replacement.calendarName = target
            saveCalendarException(seriesID: exception.seriesID, originalStart: exception.originalStartDate,
                                  replacement: replacement, refreshReminders: false)
        }

        var hasExternalChanges = false
        for index in externalCalendarEvents.indices where externalCalendarEvents[index].calendarName == source {
            externalCalendarEvents[index].calendarName = target
            hasExternalChanges = true
        }
        if hasExternalChanges {
            persistExternalCalendarEvents()
        }

        var hasLinkChanges = false
        for index in appState.calendarCategoryLinks.indices where appState.calendarCategoryLinks[index].categoryId == source {
            appState.calendarCategoryLinks[index].categoryId = target
            hasLinkChanges = true
        }
        if hasLinkChanges {
            persistAppState()
        }

        NotificationSettingsManager.shared.renameCategorySetting(oldName: source, newName: target)
        reapplyEventCategoryNotificationSettings()
    }

    func reapplyEventCategoryNotificationSettings() {
        let categories = Set((calendarEvents + externalCalendarEvents).map(\.calendarName))
        let manager = NotificationSettingsManager.shared
        let settings = manager.ensureCategorySettings(for: Array(categories))
        let settingsByCategory = Dictionary(uniqueKeysWithValues: settings.map { ($0.categoryName, $0) })
        let parentEnabled = manager.isEventCategoryNotificationEnabled

        for event in calendarEvents {
            if event.recurrenceRule != nil {
                calendarNotificationService.cancelEventReminder(eventId: event.id)
                continue
            }
            let defaultStrategy = parentEnabled
                ? eventCategoryDefaultReminderStrategy(for: event, setting: settingsByCategory[event.calendarName])
                : nil
            scheduleEventNotification(event, strategy: explicitReminderStrategy(for: event) ?? defaultStrategy)
        }
        rescheduleExternalEventNotifications()
    }

    func reapplyEventCategoryNotificationSettings(
        previousSettings: [CategoryNotificationSetting],
        currentSettings: [CategoryNotificationSetting],
        previousParentEnabled: Bool,
        parentEnabled: Bool
    ) {
        let previousMap = Dictionary(uniqueKeysWithValues: previousSettings.map { ($0.categoryName, $0) })
        let currentMap = Dictionary(uniqueKeysWithValues: currentSettings.map { ($0.categoryName, $0) })

        var hasEventChanges = false

        for index in calendarEvents.indices {
            let event = calendarEvents[index]
            let previousSetting = previousMap[event.calendarName]
            let currentSetting = currentMap[event.calendarName]
            let previousDefault = previousParentEnabled
                ? eventCategoryDefaultReminderStrategy(for: event, setting: previousSetting)
                : nil
            let currentDefault = parentEnabled
                ? eventCategoryDefaultReminderStrategy(for: event, setting: currentSetting)
                : nil

            let explicitStrategy = explicitReminderStrategy(for: event)

            // 旧デフォルト由来の通知だけを追従更新し、個別変更は維持する
            guard reminderStrategy(explicitStrategy, matches: previousDefault) else {
                continue
            }

            if reminderStrategy(explicitStrategy, matches: currentDefault) {
                continue
            }

            applyReminderStrategy(currentDefault, to: &calendarEvents[index])
            hasEventChanges = true
        }

        if hasEventChanges {
            persistCalendarEvents()
        }

        reapplyEventCategoryNotificationSettings()
    }

    func reapplyTaskPriorityNotificationSettings(
        previousSettings: [PriorityNotificationSetting],
        currentSettings: [PriorityNotificationSetting],
        previousParentEnabled: Bool,
        parentEnabled: Bool
    ) {
        let previousMap = Dictionary(uniqueKeysWithValues: previousSettings.map { ($0.priority, $0) })
        let currentMap = Dictionary(uniqueKeysWithValues: currentSettings.map { ($0.priority, $0) })

        var changedTaskIDs: [UUID] = []

        for index in tasks.indices {
            let task = tasks[index]
            let priorityKey = task.priority.rawValue
            let previousSetting = previousMap[priorityKey]
            let currentSetting = currentMap[priorityKey]

            let previousDefault = previousParentEnabled
                ? taskPriorityDefaultReminderDate(for: task, setting: previousSetting)
                : nil
            let currentDefault = parentEnabled
                ? taskPriorityDefaultReminderDate(for: task, setting: currentSetting)
                : nil

            // 旧デフォルト由来の通知だけを追従更新し、個別変更は維持する
            guard reminderDate(tasks[index].reminderDate, matches: previousDefault) else {
                continue
            }

            if reminderDate(tasks[index].reminderDate, matches: currentDefault) {
                continue
            }

            tasks[index].reminderDate = currentDefault
            changedTaskIDs.append(tasks[index].id)
            scheduleTaskNotification(tasks[index])
        }

        guard changedTaskIDs.isEmpty == false else { return }

        for taskID in changedTaskIDs {
            let descriptor = FetchDescriptor<SDTask>(predicate: #Predicate { $0.id == taskID })
            if let existing = try? modelContext.fetch(descriptor).first,
               let task = tasks.first(where: { $0.id == taskID }) {
                existing.reminderDate = task.reminderDate
            }
        }
        saveContext()
    }

    // MARK: - Calendar Notification Helpers

    enum EventReminderStrategy {
        case relative(minutesBefore: Int)
        case absolute(reminderDate: Date)
    }

    func effectiveReminderStrategy(for event: CalendarEvent) -> EventReminderStrategy? {
        if let explicit = explicitReminderStrategy(for: event) {
            return explicit
        }

        guard NotificationSettingsManager.shared.isEventCategoryNotificationEnabled else {
            return nil
        }

        let setting = NotificationSettingsManager.shared.getOrCreateSetting(for: event.calendarName)
        return eventCategoryDefaultReminderStrategy(for: event, setting: setting)
    }

    func explicitReminderStrategy(for event: CalendarEvent) -> EventReminderStrategy? {
        if let minutes = event.reminderMinutes, minutes >= 0 {
            return .relative(minutesBefore: minutes)
        }
        if let reminderDate = event.reminderDate {
            return .absolute(reminderDate: reminderDate)
        }
        return nil
    }

    func eventCategoryDefaultReminderStrategy(for event: CalendarEvent, setting: CategoryNotificationSetting?) -> EventReminderStrategy? {
        guard let setting, setting.enabled else { return nil }
        if setting.useRelativeTime {
            return .relative(minutesBefore: setting.minutesBefore)
        }

        var calendar = Calendar.current
        if event.isAllDay, let identifier = event.dateOnlyTimeZoneIdentifier, let zone = TimeZone(identifier: identifier) {
            calendar.timeZone = zone
        }
        let reminderDate = calendar.date(
            bySettingHour: setting.hour,
            minute: setting.minute,
            second: 0,
            of: event.startDate
        ) ?? event.startDate
        return .absolute(reminderDate: reminderDate)
    }

    func applyReminderStrategy(_ strategy: EventReminderStrategy?, to event: inout CalendarEvent) {
        switch strategy {
        case .relative(let minutesBefore):
            event.reminderMinutes = minutesBefore
            event.reminderDate = nil
        case .absolute(let reminderDate):
            event.reminderMinutes = nil
            event.reminderDate = reminderDate
        case nil:
            event.reminderMinutes = nil
            event.reminderDate = nil
        }
    }

    func reminderStrategy(_ lhs: EventReminderStrategy?, matches rhs: EventReminderStrategy?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (.relative(lhsMinutes), .relative(rhsMinutes)):
            return lhsMinutes == rhsMinutes
        case let (.absolute(lhsDate), .absolute(rhsDate)):
            return Calendar.current.compare(lhsDate, to: rhsDate, toGranularity: .minute) == .orderedSame
        default:
            return false
        }
    }

    func rescheduleExternalEventNotifications(referenceDate: Date = Date()) {
        let now = referenceDate
        // External and recurring occurrences share the same bounded plan.
        // Never register a repeating trigger that would ignore skipped dates.
        let maxScheduledReminders = 48
        let calendar = Calendar.current
        let horizon = calendar.date(byAdding: .month, value: 18, to: now) ?? now
        let settingsManager = NotificationSettingsManager.shared
        let parentEnabled = settingsManager.isEventCategoryNotificationEnabled
        let settingsByCategory: [String: CategoryNotificationSetting]
        if parentEnabled {
            var categories = Set((calendarEvents + externalCalendarEvents).map(\.calendarName))
            for exception in calendarExceptions {
                if let replacement = exception.replacement { categories.insert(replacement.calendarName) }
            }
            let settings = settingsManager.ensureCategorySettings(for: Array(categories))
            settingsByCategory = Dictionary(uniqueKeysWithValues: settings.map { ($0.categoryName, $0) })
        } else {
            settingsByCategory = [:]
        }

        func configuredStrategy(for event: CalendarEvent) -> EventReminderStrategy? {
            let defaultStrategy = parentEnabled
                ? eventCategoryDefaultReminderStrategy(for: event, setting: settingsByCategory[event.calendarName])
                : nil
            return explicitReminderStrategy(for: event) ?? defaultStrategy
        }

        let notifyingOverrideSeries = Set(calendarExceptions.compactMap { exception -> UUID? in
            guard let replacement = exception.replacement, configuredStrategy(for: replacement) != nil else { return nil }
            return exception.seriesID
        })
        // Most records have no reminder. Exclude them before constructing and
        // hashing hundreds of generated occurrences, while retaining a series
        // whose individually edited occurrence has its own reminder.
        let recurringSeries = calendarEvents.filter {
            $0.recurrenceRule != nil &&
                (notifyingOverrideSeries.contains($0.id) || configuredStrategy(for: $0) != nil)
        }
        let recurringEvents = EventRecurrenceExpander.occurrences(
            events: recurringSeries, exceptions: calendarExceptions,
            rangeStart: calendar.startOfDay(for: now), rangeEndExclusive: horizon, calendar: calendar,
            sortResults: false
        )
        let plannedEvents = externalCalendarEvents + recurringEvents

        struct PendingExternalReminder {
            let event: CalendarEvent
            let strategy: EventReminderStrategy
            let fireDate: Date
        }

        let candidates: [PendingExternalReminder] = plannedEvents.compactMap { event in
            // Decode persisted category settings once for the whole batch.
            guard let strategy = configuredStrategy(for: event) else { return nil }

            let fireDate: Date
            switch strategy {
            case .relative(let minutesBefore):
                fireDate = event.startDate.addingTimeInterval(-Double(minutesBefore * 60))
            case .absolute(let reminderDate):
                fireDate = reminderDate
            }

            guard fireDate > now else { return nil }
            return PendingExternalReminder(event: event, strategy: strategy, fireDate: fireDate)
        }

        let remindersToSchedule = candidates
            .sorted(by: { $0.fireDate < $1.fireDate })
            .prefix(maxScheduledReminders)
        let dailyRefresh = calendar.date(byAdding: .day, value: 1, to: now) ?? horizon
        nextExternalReminderRefreshDate = recurringSeries.isEmpty
            ? remindersToSchedule.first?.fireDate
            : min(remindersToSchedule.first?.fireDate ?? dailyRefresh, dailyRefresh)

        externalReminderRescheduleGeneration &+= 1
        let generation = externalReminderRescheduleGeneration

        calendarNotificationService.cancelAllReminders(ofTypes: [.externalEvent, .recurringEvent], shouldCancel: { [weak self] in
            self?.externalReminderRescheduleGeneration == generation
        }) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.externalReminderRescheduleGeneration == generation else { return }

                for candidate in remindersToSchedule {
                    if candidate.event.occurrenceReference != nil {
                        self.calendarNotificationService.scheduleRecurringEventReminder(
                            occurrenceID: candidate.event.id, title: candidate.event.title,
                            reminderDate: candidate.fireDate
                        )
                        continue
                    }
                    let externalEventKey = self.externalEventReminderKey(for: candidate.event)
                    switch candidate.strategy {
                    case .relative(let minutesBefore):
                        self.calendarNotificationService.scheduleExternalEventReminder(
                            externalEventKey: externalEventKey,
                            title: candidate.event.title,
                            startDate: candidate.event.startDate,
                            minutesBefore: minutesBefore
                        )
                    case .absolute(let reminderDate):
                        self.calendarNotificationService.scheduleExternalEventReminderAtDate(
                            externalEventKey: externalEventKey,
                            title: candidate.event.title,
                            reminderDate: reminderDate
                        )
                    }
                }
            }
        }
    }

    private func externalEventReminderKey(for event: CalendarEvent) -> String {
        let source = event.sourceCalendarIdentifier ?? "unknown"
        let start = Int(event.startDate.timeIntervalSince1970)
        let end = Int(event.endDate.timeIntervalSince1970)
        let signature = "\(event.id.uuidString)|\(source)|\(start)|\(end)|\(event.isAllDay)|\(event.title)"
        return stableHash(signature)
    }

    private func stableHash(_ value: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return String(hash, radix: 16)
    }

    func scheduleEventNotification(_ event: CalendarEvent) {
        scheduleEventNotification(event, strategy: effectiveReminderStrategy(for: event))
    }

    private func scheduleEventNotification(_ event: CalendarEvent, strategy: EventReminderStrategy?) {
        // キャンセルしてから再スケジュール
        calendarNotificationService.cancelEventReminder(eventId: event.id)

        if event.recurrenceRule != nil {
            rescheduleExternalEventNotifications()
            return
        }

        guard let strategy else { return }

        switch strategy {
        case .relative(let minutesBefore):
            if minutesBefore == 0 {
                calendarNotificationService.scheduleEventReminderAtDate(eventId: event.id, title: event.title, reminderDate: event.startDate)
                return
            }
            calendarNotificationService.scheduleEventReminder(
                eventId: event.id,
                title: event.title,
                startDate: event.startDate,
                minutesBefore: minutesBefore
            )
        case .absolute(let reminderDate):
            calendarNotificationService.scheduleEventReminderAtDate(
                eventId: event.id,
                title: event.title,
                reminderDate: reminderDate
            )
        }
    }

    // MARK: - Calendar Persisters

    private func persistCalendarEvent(_ event: CalendarEvent) {
        let eventID = event.id
        do {
            var descriptor = FetchDescriptor<SDCalendarEvent>(predicate: #Predicate { $0.id == eventID })
            descriptor.fetchLimit = 1
            if let existing = try modelContext.fetch(descriptor).first {
                if CalendarEvent(sd: existing) != event {
                    existing.update(from: event)
                }
            } else {
                modelContext.insert(SDCalendarEvent(domain: event))
            }
            saveContext()
        } catch {
            // A fetch error is not evidence that the row is absent. Do not
            // insert over it; the same operation can retry this targeted read.
            AppLogger.data.error("Calendar event persistence fetch failed: \(error)")
        }
    }

    func persistCalendarEvents() {
        // Full Sync to SwiftData
        let descriptor = FetchDescriptor<SDCalendarEvent>()
        do {
            let existingItems = try modelContext.fetch(descriptor)
            let existingMap = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })
            var validIDs: Set<UUID> = []

            for event in calendarEvents {
                validIDs.insert(event.id)
                if let existing = existingMap[event.id] {
                    if CalendarEvent(sd: existing) != event {
                        existing.update(from: event)
                    }
                } else {
                    let newEvent = SDCalendarEvent(domain: event)
                    modelContext.insert(newEvent)
                }
            }

            // Delete removed
            for existing in existingItems {
                if !validIDs.contains(existing.id) {
                    modelContext.delete(existing)
                }
            }
            saveContext()
        } catch {
            AppLogger.data.error("Calendar events full-sync fetch failed: \(error)")
        }
    }

    func persistExternalCalendarEvents() {
        persist(externalCalendarEvents, forKey: Self.externalCalendarEventsDefaultsKey)
    }

    func persistExternalCalendarRange() {
        persist(externalCalendarRange, forKey: Self.externalCalendarRangeDefaultsKey)
    }

}
