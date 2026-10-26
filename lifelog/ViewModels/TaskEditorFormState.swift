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
@MainActor
final class TaskEditorFormState: ObservableObject {
    struct Draft: Equatable {
        var title: String
        var detail: String
        var startDate: Date
        var endDate: Date
        var priority: TaskPriority
        var hasReminder: Bool
        var reminderDate: Date
        var isSomeday: Bool
    }

    @Published var title: String = ""
    @Published var detail: String = ""
    @Published var startDate: Date = Date()
    @Published var endDate: Date = Date()
    @Published var priority: TaskPriority = .medium
    @Published var hasReminder: Bool = false
    @Published var reminderDate: Date = Date()
    @Published var isSomeday: Bool = false
    
    private let calendar: Calendar
    private let draftKey: String
    private var isConfigured = false
    private(set) var originalTask: Task?
    init(task: Task? = nil, defaultDate: Date? = nil, calendar: Calendar = .current) {
        self.calendar = calendar
        self.draftKey = Self.makeDraftKey(task: task, defaultDate: defaultDate)
        configure(task: task, defaultDate: defaultDate)
    }

    nonisolated deinit {}

    func makeTask(detailOverride: String? = nil) -> Task {
        let zone = originalTask?.dateOnlyTimeZoneIdentifier ?? calendar.timeZone.identifier
        let sourceStart = DateOnlyProjection.sourceDate(fromDisplay: startDate, sourceTimeZoneIdentifier: zone, calendar: calendar)
        let sourceEnd = DateOnlyProjection.sourceDate(fromDisplay: endDate, sourceTimeZoneIdentifier: zone, calendar: calendar)
        let originalStart = originalTask.flatMap { TaskPresentation.displayDate(for: $0, preferring: .start, calendar: calendar) }
        let originalEnd = originalTask.flatMap { TaskPresentation.displayDate(for: $0, preferring: .deadline, calendar: calendar) }
        let keepsMissingStart = originalTask != nil && originalTask?.startDate == nil && originalStart.map { calendar.isDate($0, inSameDayAs: startDate) } == true
        let keepsMissingEnd = originalTask != nil && originalTask?.endDate == nil && originalEnd.map { calendar.isDate($0, inSameDayAs: endDate) } == true
        return Task(id: originalTask?.id ?? UUID(),
             title: title,
             detail: detailOverride ?? detail,
             startDate: isSomeday || keepsMissingStart ? nil : sourceStart,
             endDate: isSomeday || keepsMissingEnd ? nil : sourceEnd,
             priority: priority,
             isCompleted: originalTask?.isCompleted ?? false,
             reminderDate: hasReminder ? reminderDate : nil,
             completedAt: originalTask?.completedAt,
             dateOnlyTimeZoneIdentifier: zone)
    }

    var draft: Draft {
        Draft(title: title,
              detail: detail,
              startDate: startDate,
              endDate: endDate,
              priority: priority,
              hasReminder: hasReminder,
              reminderDate: reminderDate,
              isSomeday: isSomeday)
    }
    
    /// フォームを初期値で設定する（一度だけ実行される）
    func configure(task: Task?, defaultDate: Date?) {
        guard !isConfigured else { return }
        isConfigured = true
        // A reopened cached draft retains the model it originally observed.
        let task = TaskEditorDraftCache.drafts[draftKey]?.originalTask ?? task
        originalTask = task
        
        let displayStart = task.flatMap { TaskPresentation.displayDate(for: $0, preferring: .start, calendar: calendar) }
        let displayEnd = task.flatMap { TaskPresentation.displayDate(for: $0, preferring: .deadline, calendar: calendar) }
        let base = calendar.startOfDay(for: displayStart ?? defaultDate ?? Date())
        let end = calendar.startOfDay(for: displayEnd ?? base)
        
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

        restoreCachedDraftIfAvailable()
    }

    func cacheDraft(detailOverride: String? = nil) {
        var draft = draft
        if let detailOverride {
            draft.detail = detailOverride
        }
        TaskEditorDraftCache.drafts[draftKey] = .init(draft: draft, originalTask: originalTask)
    }

    func clearCachedDraft() {
        TaskEditorDraftCache.drafts[draftKey] = nil
    }
    
    /// フォームをリセットして次回の使用に備える
    func reset() {
        clearCachedDraft()
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

    private func restoreCachedDraftIfAvailable() {
        guard let cached = TaskEditorDraftCache.drafts[draftKey]?.draft else { return }
        title = cached.title
        detail = cached.detail
        startDate = cached.startDate
        endDate = cached.endDate
        priority = cached.priority
        hasReminder = cached.hasReminder
        reminderDate = cached.reminderDate
        isSomeday = cached.isSomeday
    }

    private static func makeDraftKey(task: Task?, defaultDate: Date?) -> String {
        if let task {
            return "edit:\(task.id.uuidString)"
        }
        guard let defaultDate else {
            return "new:undated"
        }
        let day = Calendar.current.startOfDay(for: defaultDate).timeIntervalSinceReferenceDate
        return "new:\(day)"
    }
}

@MainActor
private enum TaskEditorDraftCache {
    struct Entry {
        var draft: TaskEditorFormState.Draft
        let originalTask: Task?
    }
    static var drafts: [String: Entry] = [:]
}
