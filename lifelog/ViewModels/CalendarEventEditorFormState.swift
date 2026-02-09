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
class CalendarEventEditorFormState: ObservableObject {
    @Published var title: String = ""
    @Published var category: String = CategoryPalette.defaultCategoryName
    @Published var startDate: Date = Date()
    @Published var endDate: Date = Date()
    @Published var isAllDay: Bool = false
    @Published var hasReminder: Bool = false
    @Published var useRelativeReminder: Bool = true
    @Published var reminderMinutes: Int = 30
    @Published var reminderDate: Date = Date()
    
    private var isConfigured = false
    
    /// フォームを初期値で設定する（一度だけ実行される）
    func configure(event: CalendarEvent?, defaultDate: Date) {
        guard !isConfigured else { return }
        isConfigured = true
        
        let calendar = Calendar.current
        let initialStart = event?.startDate ?? calendar.date(bySettingHour: 9, minute: 0, second: 0, of: defaultDate) ?? defaultDate
        let initialEnd = event?.endDate ?? initialStart.addingTimeInterval(3600)
        
        let allDayEndForState: Date = {
            guard let event, event.isAllDay else { return initialEnd }
            return calendar.date(byAdding: .day, value: -1, to: event.endDate) ?? event.endDate
        }()
        
        title = event?.title ?? ""
        category = event?.calendarName ?? CategoryPalette.defaultCategoryName
        startDate = event?.isAllDay == true ? calendar.startOfDay(for: initialStart) : initialStart
        endDate = event?.isAllDay == true ? calendar.startOfDay(for: allDayEndForState) : initialEnd
        isAllDay = event?.isAllDay ?? false
        
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
    }
    
    /// フォームをリセットして次回の使用に備える
    func reset() {
        isConfigured = false
        title = ""
        category = CategoryPalette.defaultCategoryName
        startDate = Date()
        endDate = Date()
        isAllDay = false
        hasReminder = false
        useRelativeReminder = true
        reminderMinutes = 30
        reminderDate = Date()
    }
}
