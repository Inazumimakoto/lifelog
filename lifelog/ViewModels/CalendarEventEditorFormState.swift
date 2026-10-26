//
//  CalendarEventEditorFormState.swift
//  lifelog
//
//  Created by Codex on 2025/01/21.
//

import Foundation
import Combine

/// カレンダーイベントエディターのフォーム状態を管理するクラス
/// @StateObjectとして使用することで、ビューが再作成されても状態が保持される
@MainActor
final class CalendarEventEditorFormState: ObservableObject {
    enum RecurrenceFrequency: String, CaseIterable, Identifiable {
        case none
        case daily
        case weekly
        case biweekly

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .none: return String(localized: "繰り返しなし")
            case .daily: return String(localized: "毎日")
            case .weekly: return String(localized: "毎週")
            case .biweekly: return String(localized: "隔週")
            }
        }
    }

    struct Draft: Equatable {
        var title: String
        var detail: String
        var urlString: String
        var category: String
        var startDate: Date
        var endDate: Date
        var isAllDay: Bool
        var hasReminder: Bool
        var useRelativeReminder: Bool
        var reminderMinutes: Int
        var reminderDate: Date
        var recurrenceFrequency: RecurrenceFrequency
        var recurrenceWeekdays: Set<Int>
        var hasRecurrenceEnd: Bool
        var recurrenceEndDate: Date
    }

    @Published var title: String = ""
    @Published var detail: String = ""
    @Published var urlString: String = ""
    @Published var category: String = CategoryPalette.defaultCategoryName
    @Published var startDate: Date = Date()
    @Published var endDate: Date = Date()
    @Published var isAllDay: Bool = false
    @Published var hasReminder: Bool = false
    @Published var useRelativeReminder: Bool = true
    @Published var reminderMinutes: Int = 30
    @Published var reminderDate: Date = Date()
    @Published var recurrenceFrequency: RecurrenceFrequency = .none
    @Published var recurrenceWeekdays: Set<Int> = []
    @Published var hasRecurrenceEnd = false
    @Published var recurrenceEndDate: Date = Date()
    
    private let draftKey: String
    private var isConfigured = false
    private var isNewEvent = true
    private var categoryReplacementObservation: AnyCancellable?
    private(set) var originalEvent: CalendarEvent?
    init(event: CalendarEvent? = nil, defaultDate: Date = Date()) {
        self.draftKey = Self.makeDraftKey(event: event, defaultDate: defaultDate)
        startObserving(event: event, defaultDate: defaultDate)
    }

    private func startObserving(event: CalendarEvent?, defaultDate: Date) {
        CalendarEventEditorDraftCache.startObservingCategoryReplacements()
        configure(event: event, defaultDate: defaultDate)
        categoryReplacementObservation = CategoryPalette.categoryReplacements
            .sink { [weak self] replacement in
                guard let self else { return }
                // A category rename/deletion only migrates identity. It must
                // preserve this unsaved event's text, dates, and reminders.
                // The saved baseline can still use the old category after the
                // user has selected a different category in the unsaved draft.
                if self.originalEvent?.calendarName == replacement.oldName {
                    self.originalEvent?.calendarName = replacement.newName
                }
                if self.category == replacement.oldName {
                    self.category = replacement.newName
                }
            }
    }

    // Match AppDataStore's iOS 26.1 isolated-deinit workaround; Combine handles
    // cancellation without requiring actor-bound teardown.
    nonisolated deinit {}

    var calendar: Calendar {
        var value = Calendar.current
        let identifier = originalEvent?.recurrenceRule?.timeZoneIdentifier ?? originalEvent?.dateOnlyTimeZoneIdentifier
        if let identifier, let zone = TimeZone(identifier: identifier) {
            value.timeZone = zone
        }
        return value
    }

    var isOccurrence: Bool { originalEvent?.occurrenceReference != nil }
    var isRepeating: Bool { recurrenceFrequency != .none }
    var usesWeeklyRecurrence: Bool { recurrenceFrequency == .weekly || recurrenceFrequency == .biweekly }
    var recurrenceEndLowerBound: Date {
        let firstDay = calendar.startOfDay(for: startDate)
        // Ending at the very first occurrence intentionally leaves a cutoff
        // before the series starts. Resaving that series must not revive it.
        guard let originalEnd = originalEvent?.recurrenceRule?.until else { return firstDay }
        return min(firstDay, calendar.startOfDay(for: originalEnd))
    }
    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            ScheduleLink.isValid(urlString) &&
            (!usesWeeklyRecurrence || !recurrenceWeekdays.isEmpty)
    }

    var hasRecurrenceRuleChanges: Bool { recurrenceRule != originalEvent?.recurrenceRule }

    /// Retain untouched rule metadata, including the original interval anchor.
    /// The save flow chooses whether changed controls apply to the future or series (§4.2).
    var recurrenceRule: EventRecurrenceRule? {
        guard isRepeating else { return nil }
        if let originalRule = originalEvent?.recurrenceRule, recurrenceControlsMatch(originalRule) {
            return originalRule
        }
        return EventRecurrenceRule(frequency: recurrenceFrequency == .daily ? .daily : .weekly,
                                   interval: recurrenceFrequency == .biweekly ? 2 : 1,
                                   weekdays: usesWeeklyRecurrence ? recurrenceWeekdays.sorted() : [],
                                   until: hasRecurrenceEnd ? max(recurrenceEndDate, recurrenceEndLowerBound) : nil,
                                   timeZoneIdentifier: calendar.timeZone.identifier,
                                   anchorDate: originalEvent?.recurrenceRule?.anchorDate,
                                   seriesGroupID: originalEvent?.recurrenceRule?.seriesGroupID)
    }

    func selectRecurrenceFrequency(_ frequency: RecurrenceFrequency) {
        recurrenceFrequency = frequency
        if usesWeeklyRecurrence && recurrenceWeekdays.isEmpty {
            recurrenceWeekdays = [calendar.component(.weekday, from: startDate)]
        }
        if isRepeating {
            useRelativeReminder = true
            reminderDate = startDate.addingTimeInterval(-Double(reminderMinutes * 60))
        }
    }

    private func recurrenceControlsMatch(_ rule: EventRecurrenceRule) -> Bool {
        let originalFrequency: RecurrenceFrequency = rule.frequency == .daily ? .daily : (rule.interval == 2 ? .biweekly : .weekly)
        guard recurrenceFrequency == originalFrequency, hasRecurrenceEnd == (rule.until != nil) else { return false }
        if usesWeeklyRecurrence {
            let referenceDate = rule.anchorDate ?? originalEvent?.occurrenceReference?.originalStartDate ?? originalEvent?.startDate ?? startDate
            let originalDays = Set(rule.weekdays.isEmpty ? [calendar.component(.weekday, from: referenceDate)] : rule.weekdays)
            guard recurrenceWeekdays == originalDays else { return false }
        }
        if let until = rule.until {
            return calendar.isDate(recurrenceEndDate, inSameDayAs: until)
        }
        return true
    }

    func toggleRecurrenceWeekday(_ weekday: Int) {
        if recurrenceWeekdays.contains(weekday) {
            recurrenceWeekdays.remove(weekday)
        } else {
            recurrenceWeekdays.insert(weekday)
        }
    }

    func makeEvent(detailOverride: String? = nil) -> CalendarEvent {
        let normalizedStart = isAllDay ? calendar.startOfDay(for: startDate) : startDate
        let normalizedEnd: Date
        if isAllDay {
            let endDay = calendar.startOfDay(for: endDate)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: max(endDay, normalizedStart))
                ?? normalizedStart.addingTimeInterval(86_400)
            // Some zones start a day at 01:00. The exclusive end is the next
            // day's earliest instant, which may return to midnight.
            normalizedEnd = calendar.startOfDay(for: nextDay)
        } else {
            normalizedEnd = max(endDate, normalizedStart.addingTimeInterval(900))
        }
        let relative = hasReminder && useRelativeReminder
        let absolute = hasReminder && !useRelativeReminder
        return CalendarEvent(id: originalEvent?.id ?? UUID(), title: title.isEmpty ? String(localized: "予定") : title,
                             detail: detailOverride ?? detail, startDate: normalizedStart, endDate: normalizedEnd,
                             calendarName: category, isAllDay: isAllDay,
                             sourceCalendarIdentifier: originalEvent?.sourceCalendarIdentifier,
                             reminderMinutes: relative ? reminderMinutes : nil,
                             reminderDate: absolute ? reminderDate : nil,
                             dateOnlyTimeZoneIdentifier: isAllDay ? calendar.timeZone.identifier : nil,
                             recurrenceRule: recurrenceRule,
                             occurrenceReference: originalEvent?.occurrenceReference,
                             urlString: ScheduleLink.normalizedString(from: urlString))
    }

    var draft: Draft {
        Draft(title: title,
              detail: detail,
              urlString: urlString,
              category: category,
              startDate: startDate,
              endDate: endDate,
              isAllDay: isAllDay,
              hasReminder: hasReminder,
              useRelativeReminder: useRelativeReminder,
              reminderMinutes: reminderMinutes,
              reminderDate: reminderDate,
              recurrenceFrequency: recurrenceFrequency,
              recurrenceWeekdays: recurrenceWeekdays,
              hasRecurrenceEnd: hasRecurrenceEnd,
              recurrenceEndDate: recurrenceEndDate)
    }
    
    /// フォームを初期値で設定する（一度だけ実行される）
    func configure(event: CalendarEvent?, defaultDate: Date) {
        guard !isConfigured else { return }
        isConfigured = true
        let event = CalendarEventEditorDraftCache.drafts[draftKey]?.originalEvent ?? event
        originalEvent = event
        isNewEvent = event == nil
        
        let calendar = self.calendar
        let initialStart = event?.startDate ?? calendar.date(bySettingHour: 9, minute: 0, second: 0, of: defaultDate) ?? defaultDate
        let initialEnd = event?.endDate ?? initialStart.addingTimeInterval(3600)
        
        let allDayEndForState: Date = {
            guard let event, event.isAllDay else { return initialEnd }
            return calendar.date(byAdding: .day, value: -1, to: event.endDate) ?? event.endDate
        }()
        
        title = event?.title ?? ""
        detail = event?.detail ?? ""
        urlString = event?.urlString ?? ""
        category = event?.calendarName ?? CategoryPalette.defaultCategoryName
        startDate = event?.isAllDay == true ? calendar.startOfDay(for: initialStart) : initialStart
        endDate = event?.isAllDay == true ? calendar.startOfDay(for: allDayEndForState) : initialEnd
        isAllDay = event?.isAllDay ?? false
        if let rule = event?.recurrenceRule {
            recurrenceFrequency = rule.frequency == .daily ? .daily : (rule.interval == 2 ? .biweekly : .weekly)
            let referenceDate = rule.anchorDate ?? event?.occurrenceReference?.originalStartDate ?? initialStart
            recurrenceWeekdays = Set(rule.weekdays.isEmpty ? [calendar.component(.weekday, from: referenceDate)] : rule.weekdays)
            hasRecurrenceEnd = rule.until != nil
            recurrenceEndDate = rule.until ?? calendar.date(byAdding: .month, value: 3, to: initialStart) ?? initialStart
        } else {
            recurrenceWeekdays = [calendar.component(.weekday, from: initialStart)]
            recurrenceEndDate = calendar.date(byAdding: .month, value: 3, to: initialStart) ?? initialStart
        }
        
        // カテゴリ別通知設定を読み込み（新規作成時のみ適用）
        let initialCategory = event?.calendarName ?? CategoryPalette.defaultCategoryName
        let categoryEnabled = UserDefaults.standard.bool(forKey: "eventCategoryNotificationEnabled")
        let categorySetting = categoryEnabled
            ? NotificationSettingsManager.shared.getOrCreateSetting(for: initialCategory)
            : nil
        
        let hasReminderValue: Bool
        let defaultMinutes: Int
        let useRelative: Bool
        var defaultReminderDate: Date
        
        if event != nil {
            hasReminderValue = event?.reminderMinutes != nil || event?.reminderDate != nil
            defaultMinutes = event?.reminderMinutes ?? 30
            useRelative = event?.reminderDate == nil
            defaultReminderDate = event?.reminderDate ?? initialStart.addingTimeInterval(-Double(defaultMinutes * 60))
        } else if categoryEnabled, let setting = categorySetting, setting.enabled {
            hasReminderValue = true
            if setting.useRelativeTime {
                defaultMinutes = setting.minutesBefore
                useRelative = true
                defaultReminderDate = initialStart.addingTimeInterval(-Double(defaultMinutes * 60))
            } else {
                defaultMinutes = 30
                useRelative = false
                let cal = Calendar.current
                defaultReminderDate = cal.date(bySettingHour: setting.hour, minute: setting.minute, second: 0, of: initialStart) ?? initialStart
            }
        } else {
            hasReminderValue = false
            defaultMinutes = 30
            useRelative = true
            defaultReminderDate = initialStart.addingTimeInterval(-Double(defaultMinutes * 60))
        }
        
        hasReminder = hasReminderValue
        useRelativeReminder = useRelative
        reminderMinutes = defaultMinutes
        reminderDate = defaultReminderDate
        if isRepeating && !isOccurrence {
            useRelativeReminder = true
            reminderDate = startDate.addingTimeInterval(-Double(reminderMinutes * 60))
        }

        restoreCachedDraftIfAvailable()
    }

    /// Only an explicit picker selection applies category reminder defaults.
    /// docs/requirements.md §Settings: management changes also update drafts,
    /// while retaining the event's independently edited fields.
    func selectCategory(_ newCategory: String) {
        guard category != newCategory else { return }
        category = newCategory
        guard isNewEvent else { return }
        guard NotificationSettingsManager.shared.isEventCategoryNotificationEnabled else { return }

        applyCategoryReminderDefaults()
    }

    private func applyCategoryReminderDefaults() {
        guard NotificationSettingsManager.shared.isEventCategoryNotificationEnabled else {
            hasReminder = false
            return
        }
        let setting = NotificationSettingsManager.shared.getOrCreateSetting(for: category)
        hasReminder = setting.enabled
        guard setting.enabled else { return }
        useRelativeReminder = setting.useRelativeTime
        if setting.useRelativeTime {
            reminderMinutes = setting.minutesBefore
            reminderDate = startDate.addingTimeInterval(-Double(setting.minutesBefore * 60))
        } else {
            reminderDate = calendar.date(bySettingHour: setting.hour,
                                                 minute: setting.minute,
                                                 second: 0,
                                                 of: startDate) ?? startDate
        }
    }

    func cacheDraft(detailOverride: String? = nil) {
        var draft = draft
        if let detailOverride {
            draft.detail = detailOverride
        }
        CalendarEventEditorDraftCache.drafts[draftKey] = .init(draft: draft, originalEvent: originalEvent)
    }

    func clearCachedDraft() {
        CalendarEventEditorDraftCache.drafts[draftKey] = nil
    }
    
    /// フォームをリセットして次回の使用に備える
    func reset() {
        clearCachedDraft()
        isConfigured = false
        title = ""
        detail = ""
        urlString = ""
        category = CategoryPalette.defaultCategoryName
        startDate = Date()
        endDate = Date()
        isAllDay = false
        hasReminder = false
        useRelativeReminder = true
        reminderMinutes = 30
        reminderDate = Date()
        recurrenceFrequency = .none
        recurrenceWeekdays = []
        hasRecurrenceEnd = false
        recurrenceEndDate = Date()
    }

    private func restoreCachedDraftIfAvailable() {
        guard let cached = CalendarEventEditorDraftCache.drafts[draftKey]?.draft else { return }
        title = cached.title
        detail = cached.detail
        urlString = cached.urlString
        category = cached.category
        startDate = cached.startDate
        endDate = cached.endDate
        isAllDay = cached.isAllDay
        hasReminder = cached.hasReminder
        useRelativeReminder = cached.useRelativeReminder
        reminderMinutes = cached.reminderMinutes
        reminderDate = cached.reminderDate
        recurrenceFrequency = cached.recurrenceFrequency
        recurrenceWeekdays = cached.recurrenceWeekdays
        hasRecurrenceEnd = cached.hasRecurrenceEnd
        recurrenceEndDate = cached.recurrenceEndDate
    }

    private static func makeDraftKey(event: CalendarEvent?, defaultDate: Date) -> String {
        if let event {
            return "edit:\(event.id.uuidString)"
        }
        let day = Calendar.current.startOfDay(for: defaultDate).timeIntervalSinceReferenceDate
        return "new:\(day)"
    }
}

@MainActor
private enum CalendarEventEditorDraftCache {
    struct Entry {
        var draft: CalendarEventEditorFormState.Draft
        var originalEvent: CalendarEvent?
    }
    static var drafts: [String: Entry] = [:]
    private static var categoryReplacementObservation: AnyCancellable?

    static func startObservingCategoryReplacements() {
        guard categoryReplacementObservation == nil else { return }
        // Keep this subscription alive after every editor closes so reopening
        // a cached draft never resurrects a renamed or deleted category.
        categoryReplacementObservation = CategoryPalette.categoryReplacements
            .sink { replacement in
                for key in Array(drafts.keys) {
                    if drafts[key]?.originalEvent?.calendarName == replacement.oldName {
                        drafts[key]?.originalEvent?.calendarName = replacement.newName
                    }
                    if drafts[key]?.draft.category == replacement.oldName {
                        drafts[key]?.draft.category = replacement.newName
                    }
                }
            }
    }
}
