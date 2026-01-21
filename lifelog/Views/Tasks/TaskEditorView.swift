//
//  TaskEditorView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var formState = TaskEditorFormState()
    @State private var showDeleteConfirmation = false

    var onSave: (Task) -> Void
    var onDelete: (() -> Void)?

    private let originalTask: Task?
    private let defaultDate: Date?
    private let calendar = Calendar.current

    init(task: Task? = nil,
         defaultDate: Date? = nil,
         onSave: @escaping (Task) -> Void,
         onDelete: (() -> Void)? = nil) {
        self.onSave = onSave
        self.onDelete = onDelete
        self.originalTask = task
        self.defaultDate = defaultDate
    }

    var body: some View {
        Form {
            Section("タスク内容") {
                TextField("タイトルを入力", text: $formState.title)
                TextField("詳細メモ（任意）", text: $formState.detail, axis: .vertical)
                
                Picker("期限", selection: $formState.isSomeday) {
                    Text("日付指定").tag(false)
                    Text("いつか").tag(true)
                }
                .pickerStyle(.segmented)
                
                if !formState.isSomeday {
                    DatePicker("開始日", selection: $formState.startDate, displayedComponents: [.date])
                        .onChange(of: formState.startDate) { newValue in
                            formState.startDate = calendar.startOfDay(for: newValue)
                            if formState.endDate < formState.startDate {
                                formState.endDate = formState.startDate
                            }
                        }
                    DatePicker("終了日", selection: $formState.endDate, in: formState.startDate..., displayedComponents: [.date])
                        .onChange(of: formState.endDate) { newValue in
                            formState.endDate = max(calendar.startOfDay(for: newValue), formState.startDate)
                        }
                }
                
                Picker("優先度", selection: $formState.priority) {
                    ForEach(TaskPriority.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                
                if formState.isSomeday {
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
                Toggle("リマインダー", isOn: $formState.hasReminder)
                if formState.hasReminder {
                    DatePicker("通知日時", selection: $formState.reminderDate, displayedComponents: [.date, .hourAndMinute])
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
                                    title: formState.title,
                                    detail: formState.detail,
                                    startDate: formState.isSomeday ? nil : calendar.startOfDay(for: formState.startDate),
                                    endDate: formState.isSomeday ? nil : calendar.startOfDay(for: formState.endDate),
                                    priority: formState.priority,
                                    isCompleted: originalTask?.isCompleted ?? false,
                                    reminderDate: formState.hasReminder ? formState.reminderDate : nil,
                                    completedAt: originalTask?.completedAt)
                    onSave(task)
                    formState.reset()
                    dismiss()
                }
                .disabled(formState.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル", role: .cancel) {
                    formState.reset()
                    dismiss()
                }
            }
        }
        .confirmationDialog("このタスクを削除しますか？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                onDelete?()
                formState.reset()
                dismiss()
            }
            Button("キャンセル", role: .cancel) { }
        }
        .onAppear {
            formState.configure(task: originalTask, defaultDate: defaultDate)
        }
        .onChange(of: formState.priority) { _, newPriority in
            // 新規作成時のみ優先度変更で通知設定を連動
            guard originalTask == nil else { return }
            let priorityEnabled = UserDefaults.standard.bool(forKey: "taskPriorityNotificationEnabled")
            guard priorityEnabled else { return }
            
            if let setting = NotificationSettingsManager.shared.getSetting(for: newPriority), setting.enabled {
                formState.hasReminder = true
                // 開始日の指定時刻に通知
                if let newReminderDate = calendar.date(bySettingHour: setting.hour, minute: setting.minute, second: 0, of: formState.startDate) {
                    formState.reminderDate = newReminderDate
                }
            } else {
                formState.hasReminder = false
            }
        }
        .onChange(of: formState.startDate) { _, newStartDate in
            // リマインダーONの場合、開始日変更時に通知日時の日付部分を連動更新
            guard formState.hasReminder else { return }
            let currentTime = calendar.dateComponents([.hour, .minute], from: formState.reminderDate)
            if let newReminderDate = calendar.date(bySettingHour: currentTime.hour ?? 9, minute: currentTime.minute ?? 0, second: 0, of: newStartDate) {
                formState.reminderDate = newReminderDate
            }
        }
    }
}
