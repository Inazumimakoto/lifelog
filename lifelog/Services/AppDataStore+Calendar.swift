//
//  AppDataStore+Calendar.swift
//  lifelog
//

import Foundation
import EventKit
import UserNotifications
import SwiftData
import os

extension AppDataStore {

    // MARK: - Calendar

    func events(on date: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)

        // キャッシュチェック
        if let cached = eventsCache[dayStart] {
            return cached
        }

        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        // マージ・重複排除・整列の方針は共有の EventQuerying に一本化する。
        // 内部/外部それぞれ当日と重なるものに絞ってからマージする。
        let internalEvents = EventQuerying.overlapping(calendarEvents, rangeStart: dayStart, rangeEndExclusive: dayEnd)
        let externalEvents = EventQuerying.overlapping(externalCalendarEvents, rangeStart: dayStart, rangeEndExclusive: dayEnd)
        let result = EventQuerying.mergedDedupedSorted(
            internalEvents: internalEvents,
            externalEvents: externalEvents
        )

        // キャッシュに保存
        eventsCache[dayStart] = result
        return result
    }

    func addCalendarEvent(_ event: CalendarEvent) {
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
    }

    func updateCalendarEvent(_ event: CalendarEvent) {
        guard let index = calendarEvents.firstIndex(where: { $0.id == event.id }) else { return }
        let changed = calendarEvents[index] != event
        if changed {
            eventsCache.removeAll()
            calendarEvents[index] = event
        }
        // Even an equal memory snapshot can have an earlier unsaved change or
        // failed fetch. Retry just this row without publishing it a second time.
        persistCalendarEvent(event)
        guard changed else { return }
        scheduleEventNotification(event)
        rescheduleTodayOverviewReminderIfNeeded()
    }

    func deleteCalendarEvent(_ eventID: UUID) {
        let changed = calendarEvents.contains { $0.id == eventID }
        if changed {
            eventsCache.removeAll()
            calendarEvents.removeAll { $0.id == eventID }
        }
        do {
            var descriptor = FetchDescriptor<SDCalendarEvent>(predicate: #Predicate { $0.id == eventID })
            descriptor.fetchLimit = 1
            if let existing = try modelContext.fetch(descriptor).first {
                modelContext.delete(existing)
            }
            // Keep this path usable when memory already reflects a failed save.
            saveContext()
        } catch {
            AppLogger.data.error("Calendar event deletion fetch failed: \(error)")
        }
        guard changed else { return }
        NotificationService.shared.cancelEventReminder(eventId: eventID)
        rescheduleTodayOverviewReminderIfNeeded()
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
        if let minutes = event.reminderMinutes, minutes > 0 {
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

        let reminderDate = Calendar.current.date(
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
        let maxScheduledExternalReminders = 48
        let settingsManager = NotificationSettingsManager.shared
        let parentEnabled = settingsManager.isEventCategoryNotificationEnabled
        let settings = parentEnabled
            ? settingsManager.ensureCategorySettings(for: Array(Set(externalCalendarEvents.map(\.calendarName))))
            : []
        let settingsByCategory = Dictionary(uniqueKeysWithValues: settings.map { ($0.categoryName, $0) })

        struct PendingExternalReminder {
            let event: CalendarEvent
            let strategy: EventReminderStrategy
            let fireDate: Date
        }

        let candidates: [PendingExternalReminder] = externalCalendarEvents.compactMap { event in
            // Decode persisted category settings once for the whole batch.
            let defaultStrategy = parentEnabled
                ? eventCategoryDefaultReminderStrategy(for: event, setting: settingsByCategory[event.calendarName])
                : nil
            guard let strategy = explicitReminderStrategy(for: event) ?? defaultStrategy else { return nil }

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
            .prefix(maxScheduledExternalReminders)
        nextExternalReminderRefreshDate = remindersToSchedule.first?.fireDate

        externalReminderRescheduleGeneration &+= 1
        let generation = externalReminderRescheduleGeneration

        NotificationService.shared.cancelAllReminders(ofType: .externalEvent) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.externalReminderRescheduleGeneration == generation else { return }

                for candidate in remindersToSchedule {
                    let externalEventKey = self.externalEventReminderKey(for: candidate.event)
                    switch candidate.strategy {
                    case .relative(let minutesBefore):
                        NotificationService.shared.scheduleExternalEventReminder(
                            externalEventKey: externalEventKey,
                            title: candidate.event.title,
                            startDate: candidate.event.startDate,
                            minutesBefore: minutesBefore
                        )
                    case .absolute(let reminderDate):
                        NotificationService.shared.scheduleExternalEventReminderAtDate(
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
        NotificationService.shared.cancelEventReminder(eventId: event.id)

        guard let strategy else { return }

        switch strategy {
        case .relative(let minutesBefore):
            NotificationService.shared.scheduleEventReminder(
                eventId: event.id,
                title: event.title,
                startDate: event.startDate,
                minutesBefore: minutesBefore
            )
        case .absolute(let reminderDate):
            NotificationService.shared.scheduleEventReminderAtDate(
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
