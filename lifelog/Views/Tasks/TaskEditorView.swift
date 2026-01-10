//
//  TaskEditorView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false

    var onSave: (Task) -> Void
    var onDelete: (() -> Void)?

    private let originalTask: Task?
    private let defaultDate: Date?
    private let calendar = Calendar.current

    @State private var title: String
    @State private var detail: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var priority: TaskPriority
    @State private var hasReminder: Bool
    @State private var reminderDate: Date
    @State private var isSomeday: Bool

    init(task: Task? = nil,
         defaultDate: Date? = nil,
         onSave: @escaping (Task) -> Void,
         onDelete: (() -> Void)? = nil) {
        self.onSave = onSave
        self.onDelete = onDelete
        self.originalTask = task
        self.defaultDate = defaultDate
        let base = calendar.startOfDay(for: task?.startDate ?? defaultDate ?? Date())
        let end = calendar.startOfDay(for: task?.endDate ?? base)
        _title = State(initialValue: task?.title ?? "")
        _detail = State(initialValue: task?.detail ?? "")
        _startDate = State(initialValue: base)
        _endDate = State(initialValue: max(base, end))
        _priority = State(initialValue: task?.priority ?? .medium)
        // 既存タスクで両方nilなら「いつか」タスク（新規は常にfalse）
        _isSomeday = State(initialValue: task != nil && task?.startDate == nil && task?.endDate == nil)
        
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
        _hasReminder = State(initialValue: hasReminderValue)
        
        // 新規タスクの場合、開始日の指定時刻に通知
        let defaultReminderDateTime: Date = {
            let cal = Calendar.current
            return cal.date(bySettingHour: defaultHour, minute: defaultMinute, second: 0, of: base) ?? base
        }()
        _reminderDate = State(initialValue: task?.reminderDate ?? defaultReminderDateTime)
    }

    var body: some View {
        Form {
            Section("タスク内容") {
                TextField("タイトルを入力", text: $title)
                TextField("詳細メモ（任意）", text: $detail, axis: .vertical)
                
                Picker("期限", selection: $isSomeday) {
                    Text("日付指定").tag(false)
                    Text("いつか").tag(true)
                }
                .pickerStyle(.segmented)
                
                if !isSomeday {
                    DatePicker("開始日", selection: $startDate, displayedComponents: [.date])
                        .onChange(of: startDate) { newValue in
                            startDate = calendar.startOfDay(for: newValue)
                            if endDate < startDate {
                                endDate = startDate
                            }
                        }
                    DatePicker("終了日", selection: $endDate, in: startDate..., displayedComponents: [.date])
                        .onChange(of: endDate) { newValue in
                            endDate = max(calendar.startOfDay(for: newValue), startDate)
                        }
                }
                
                Picker("優先度", selection: $priority) {
                    ForEach(TaskPriority.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                
                if isSomeday {
                    Text("「いつか」タスクはカレンダーやホームには表示されず、タスク一覧でのみ確認できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("開始日と終了日が同じ場合は単日タスクとして扱われます。複数日にまたがる場合は期間全体に表示されます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("通知") {
                Toggle("リマインダー", isOn: $hasReminder)
                if hasReminder {
                    DatePicker("通知日時", selection: $reminderDate, displayedComponents: [.date, .hourAndMinute])
                }
            }
            
            if originalTask != nil && onDelete != nil {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("タスクを削除")
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle("タスク")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let task = Task(id: originalTask?.id ?? UUID(),
                                    title: title,
                                    detail: detail,
                                    startDate: isSomeday ? nil : calendar.startOfDay(for: startDate),
                                    endDate: isSomeday ? nil : calendar.startOfDay(for: endDate),
                                    priority: priority,
                                    isCompleted: originalTask?.isCompleted ?? false,
                                    reminderDate: hasReminder ? reminderDate : nil,
                                    completedAt: originalTask?.completedAt)
                    onSave(task)
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル", role: .cancel) {
                    dismiss()
                }
            }
        }
        .confirmationDialog("このタスクを削除しますか？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("キャンセル", role: .cancel) { }
        }
        .onChange(of: priority) { _, newPriority in
            // 新規作成時のみ優先度変更で通知設定を連動
            guard originalTask == nil else { return }
            let priorityEnabled = UserDefaults.standard.bool(forKey: "taskPriorityNotificationEnabled")
            guard priorityEnabled else { return }
            
            if let setting = NotificationSettingsManager.shared.getSetting(for: newPriority), setting.enabled {
                hasReminder = true
                // 開始日の指定時刻に通知
                if let newReminderDate = calendar.date(bySettingHour: setting.hour, minute: setting.minute, second: 0, of: startDate) {
                    reminderDate = newReminderDate
                }
            } else {
                hasReminder = false
            }
        }
        .onChange(of: startDate) { _, newStartDate in
            // リマインダーONの場合、開始日変更時に通知日時の日付部分を連動更新
            guard hasReminder else { return }
            let currentTime = calendar.dateComponents([.hour, .minute], from: reminderDate)
            if let newReminderDate = calendar.date(bySettingHour: currentTime.hour ?? 9, minute: currentTime.minute ?? 0, second: 0, of: newStartDate) {
                reminderDate = newReminderDate
            }
        }
    }
}
