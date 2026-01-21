//
//  TaskEditorFormState.swift
//  lifelog
//
//  Created by Codex on 2025/01/21.
//

import Foundation
import Combine

/// タスクエディターのフォーム状態を管理するクラス
/// @StateObjectとして使用することで、ビューが再作成されても状態が保持される
class TaskEditorFormState: ObservableObject {
    @Published var title: String = ""
    @Published var detail: String = ""
    @Published var startDate: Date = Date()
    @Published var endDate: Date = Date()
    @Published var priority: TaskPriority = .medium
    @Published var hasReminder: Bool = false
    @Published var reminderDate: Date = Date()
    @Published var isSomeday: Bool = false
    
    private let calendar = Calendar.current
    private var isConfigured = false
    
    /// フォームを初期値で設定する（一度だけ実行される）
    func configure(task: Task?, defaultDate: Date?) {
        guard !isConfigured else { return }
        isConfigured = true
        
        let base = calendar.startOfDay(for: task?.startDate ?? defaultDate ?? Date())
        let end = calendar.startOfDay(for: task?.endDate ?? base)
        
        title = task?.title ?? ""
        detail = task?.detail ?? ""
        startDate = base
        endDate = max(base, end)
        priority = task?.priority ?? .medium
        isSomeday = task != nil && task?.startDate == nil && task?.endDate == nil
        
        // 優先度別通知設定を読み込み（新規作成時のみ適用）
        let initialPriority = task?.priority ?? .medium
        let priorityEnabled = UserDefaults.standard.bool(forKey: "taskPriorityNotificationEnabled")
        let prioritySetting = NotificationSettingsManager.shared.getSetting(for: initialPriority)
        
        let hasReminderValue: Bool
        let defaultHour: Int
        let defaultMinute: Int
        
        if task != nil {
            hasReminderValue = task?.reminderDate != nil
            defaultHour = 9
            defaultMinute = 0
        } else if priorityEnabled, let setting = prioritySetting, setting.enabled {
            hasReminderValue = true
            defaultHour = setting.hour
            defaultMinute = setting.minute
        } else {
            hasReminderValue = false
            defaultHour = 9
            defaultMinute = 0
        }
        
        hasReminder = hasReminderValue
        
        // 新規タスクの場合、開始日の指定時刻に通知
        let defaultReminderDateTime = calendar.date(bySettingHour: defaultHour, minute: defaultMinute, second: 0, of: base) ?? base
        reminderDate = task?.reminderDate ?? defaultReminderDateTime
    }
    
    /// フォームをリセットして次回の使用に備える
    func reset() {
        isConfigured = false
        title = ""
        detail = ""
        startDate = Date()
        endDate = Date()
        priority = .medium
        hasReminder = false
        reminderDate = Date()
        isSomeday = false
    }
}
