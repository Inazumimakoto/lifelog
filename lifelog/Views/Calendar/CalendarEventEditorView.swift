//
//  CalendarEventEditorView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct CalendarEventEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var formState = CalendarEventEditorFormState()
    @State private var isShowingCategorySelection = false
    @State private var showDeleteConfirmation = false

    var onSave: (CalendarEvent) -> Void
    var onDelete: (() -> Void)?

    private let originalEvent: CalendarEvent?
    private let defaultDate: Date

    init(defaultDate: Date = Date(),
         event: CalendarEvent? = nil,
         onSave: @escaping (CalendarEvent) -> Void,
         onDelete: (() -> Void)? = nil) {
        self.onSave = onSave
        self.onDelete = onDelete
        self.originalEvent = event
        self.defaultDate = defaultDate
    }

    var body: some View {
        Form {
            Section("予定") {
                TextField("タイトル", text: $formState.title)
                Button(action: { isShowingCategorySelection = true }) {
                    HStack {
                        Text("カテゴリ")
                        Spacer()
                        Circle()
                            .fill(CategoryPalette.color(for: formState.category))
                            .frame(width: 10, height: 10)
                        Text(formState.category)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundColor(.primary)
            }
            Section("時間") {
                Toggle("終日", isOn: $formState.isAllDay)
                DatePicker("開始", selection: $formState.startDate, displayedComponents: formState.isAllDay ? [.date] : [.date, .hourAndMinute])
                    .onChange(of: formState.startDate) { _, newValue in
                        if formState.endDate < newValue {
                            formState.endDate = newValue
                        }
                        if formState.isAllDay {
                            formState.startDate = Calendar.current.startOfDay(for: newValue)
                        }
                        // 開始前モードの場合のみ、reminderDateを連動更新
                        if formState.useRelativeReminder {
                            formState.reminderDate = newValue.addingTimeInterval(-Double(formState.reminderMinutes * 60))
                        }
                    }
                DatePicker("終了", selection: $formState.endDate, in: formState.startDate..., displayedComponents: formState.isAllDay ? [.date] : [.date, .hourAndMinute])
                    .onChange(of: formState.endDate) { _, newValue in
                        formState.endDate = max(newValue, formState.startDate)
                        if formState.isAllDay {
                            formState.endDate = Calendar.current.startOfDay(for: formState.endDate)
                        }
                    }
            }
            
            Section("通知") {
                Toggle("リマインダー", isOn: $formState.hasReminder)
                if formState.hasReminder {
                    Picker("通知方法", selection: $formState.useRelativeReminder) {
                        Text("開始前").tag(true)
                        Text("日時指定").tag(false)
                    }
                    .pickerStyle(.segmented)
                    
                    if formState.useRelativeReminder {
                        Picker("タイミング", selection: $formState.reminderMinutes) {
                            Text("5分前").tag(5)
                            Text("15分前").tag(15)
                            Text("30分前").tag(30)
                            Text("1時間前").tag(60)
                            Text("1日前").tag(1440)
                        }
                        .onChange(of: formState.reminderMinutes) { _, newValue in
                            formState.reminderDate = formState.startDate.addingTimeInterval(-Double(newValue * 60))
                        }
                    } else {
                        DatePicker("通知日時", selection: $formState.reminderDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }
            }
            
            if originalEvent != nil && onDelete != nil {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("予定を削除")
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle(originalEvent == nil ? "予定を追加" : "予定を編集")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let calendar = Calendar.current
                    let normalizedStart = formState.isAllDay ? calendar.startOfDay(for: formState.startDate) : formState.startDate
                    let normalizedEnd: Date = {
                        if formState.isAllDay {
                            let endDay = calendar.startOfDay(for: formState.endDate)
                            return calendar.date(byAdding: .day, value: 1, to: max(endDay, normalizedStart)) ?? normalizedStart.addingTimeInterval(86_400)
                        } else {
                            return max(formState.endDate, normalizedStart.addingTimeInterval(900))
                        }
                    }()
                    let event = CalendarEvent(id: originalEvent?.id ?? UUID(),
                                              title: formState.title.isEmpty ? "予定" : formState.title,
                                              startDate: normalizedStart,
                                              endDate: normalizedEnd,
                                              calendarName: formState.category,
                                              isAllDay: formState.isAllDay,
                                              reminderMinutes: formState.hasReminder && formState.useRelativeReminder ? formState.reminderMinutes : nil,
                                              reminderDate: formState.hasReminder && !formState.useRelativeReminder ? formState.reminderDate : nil)
                    onSave(event)
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
        .onAppear {
            formState.configure(event: originalEvent, defaultDate: defaultDate)
        }
        .onChange(of: formState.isAllDay) { _, newValue in
            if newValue {
                let calendar = Calendar.current
                formState.startDate = calendar.startOfDay(for: formState.startDate)
                formState.endDate = calendar.startOfDay(for: max(formState.endDate, formState.startDate))
            }
        }
        .onChange(of: formState.category) { _, newCategory in
            // 新規作成時のみカテゴリ変更で通知設定を連動
            guard originalEvent == nil else { return }
            let categoryEnabled = UserDefaults.standard.bool(forKey: "eventCategoryNotificationEnabled")
            guard categoryEnabled else { return }

            let setting = NotificationSettingsManager.shared.getOrCreateSetting(for: newCategory)
            formState.hasReminder = setting.enabled
            if setting.enabled {
                formState.useRelativeReminder = setting.useRelativeTime
                if setting.useRelativeTime {
                    formState.reminderMinutes = setting.minutesBefore
                    formState.reminderDate = formState.startDate.addingTimeInterval(-Double(setting.minutesBefore * 60))
                } else {
                    let cal = Calendar.current
                    formState.reminderDate = cal.date(bySettingHour: setting.hour, minute: setting.minute, second: 0, of: formState.startDate) ?? formState.startDate
                }
            }
        }
        .sheet(isPresented: $isShowingCategorySelection) {
            CategorySelectionView(selectedCategory: $formState.category)
        }
        .confirmationDialog("この予定を削除しますか？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                onDelete?()
                formState.reset()
                dismiss()
            }
            Button("キャンセル", role: .cancel) { }
        }
    }
}
