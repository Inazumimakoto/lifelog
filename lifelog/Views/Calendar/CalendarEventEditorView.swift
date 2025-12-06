//
//  CalendarEventEditorView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct CalendarEventEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingCategorySelection = false
    @State private var showDeleteConfirmation = false

    var onSave: (CalendarEvent) -> Void
    var onDelete: (() -> Void)?

    private let originalEvent: CalendarEvent?

    @State private var title: String
    @State private var category: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isAllDay: Bool
    @State private var hasReminder: Bool
    @State private var useRelativeReminder: Bool
    @State private var reminderMinutes: Int
    @State private var reminderDate: Date

    init(defaultDate: Date = Date(),
         event: CalendarEvent? = nil,
         onSave: @escaping (CalendarEvent) -> Void,
         onDelete: (() -> Void)? = nil) {
        self.onSave = onSave
        self.onDelete = onDelete
        self.originalEvent = event
        let calendar = Calendar.current
        let initialStart = event?.startDate ?? calendar.date(bySettingHour: 9, minute: 0, second: 0, of: defaultDate) ?? defaultDate
        let initialEnd = event?.endDate ?? initialStart.addingTimeInterval(3600)
        let allDayEndForState: Date = {
            guard let event, event.isAllDay else { return initialEnd }
            return calendar.date(byAdding: .day, value: -1, to: event.endDate) ?? event.endDate
        }()
        _title = State(initialValue: event?.title ?? "")
        _category = State(initialValue: event?.calendarName ?? CategoryPalette.defaultCategoryName)
        _startDate = State(initialValue: event?.isAllDay == true ? calendar.startOfDay(for: initialStart) : initialStart)
        _endDate = State(initialValue: event?.isAllDay == true ? calendar.startOfDay(for: allDayEndForState) : initialEnd)
        _isAllDay = State(initialValue: event?.isAllDay ?? false)
        
        // カテゴリ別通知設定を読み込み（新規作成時のみ適用）
        let initialCategory = event?.calendarName ?? CategoryPalette.defaultCategoryName
        let categoryEnabled = UserDefaults.standard.bool(forKey: "eventCategoryNotificationEnabled")
        let categorySetting = NotificationSettingsManager.shared.getSetting(for: initialCategory)
        
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
                // 開始日の指定時刻に通知
                let cal = Calendar.current
                defaultReminderDate = cal.date(bySettingHour: setting.hour, minute: setting.minute, second: 0, of: initialStart) ?? initialStart
            }
        } else {
            hasReminderValue = false
            defaultMinutes = 30
            useRelative = true
            defaultReminderDate = initialStart.addingTimeInterval(-Double(defaultMinutes * 60))
        }
        
        _hasReminder = State(initialValue: hasReminderValue)
        _useRelativeReminder = State(initialValue: useRelative)
        _reminderMinutes = State(initialValue: defaultMinutes)
        _reminderDate = State(initialValue: defaultReminderDate)
    }

    var body: some View {
        Form {
            Section("予定") {
                TextField("タイトル", text: $title)
                Button(action: { isShowingCategorySelection = true }) {
                    HStack {
                        Text("カテゴリ")
                        Spacer()
                        Circle()
                            .fill(CategoryPalette.color(for: category))
                            .frame(width: 10, height: 10)
                        Text(category)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundColor(.primary)
            }
            Section("時間") {
                Toggle("終日", isOn: $isAllDay)
                DatePicker("開始", selection: $startDate, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                    .onChange(of: startDate) { _, newValue in
                        if endDate < newValue {
                            endDate = newValue
                        }
                        if isAllDay {
                            startDate = Calendar.current.startOfDay(for: newValue)
                        }
                        // 開始前モードの場合のみ、reminderDateを連動更新（開始時刻 - reminderMinutes）
                        if useRelativeReminder {
                            reminderDate = newValue.addingTimeInterval(-Double(reminderMinutes * 60))
                        }
                    }
                DatePicker("終了", selection: $endDate, in: startDate..., displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                    .onChange(of: endDate) { _, newValue in
                        endDate = max(newValue, startDate)
                        if isAllDay {
                            endDate = Calendar.current.startOfDay(for: endDate)
                        }
                    }
            }
            
            Section("通知") {
                Toggle("リマインダー", isOn: $hasReminder)
                if hasReminder {
                    Picker("通知方法", selection: $useRelativeReminder) {
                        Text("開始前").tag(true)
                        Text("日時指定").tag(false)
                    }
                    .pickerStyle(.segmented)
                    
                    if useRelativeReminder {
                        Picker("タイミング", selection: $reminderMinutes) {
                            Text("5分前").tag(5)
                            Text("15分前").tag(15)
                            Text("30分前").tag(30)
                            Text("1時間前").tag(60)
                            Text("1日前").tag(1440)
                        }
                        .onChange(of: reminderMinutes) { _, newValue in
                            // 開始前設定変更時も日時指定を更新
                            reminderDate = startDate.addingTimeInterval(-Double(newValue * 60))
                        }
                    } else {
                        DatePicker("通知日時", selection: $reminderDate, displayedComponents: [.date, .hourAndMinute])
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
                    let normalizedStart = isAllDay ? calendar.startOfDay(for: startDate) : startDate
                    let normalizedEnd: Date = {
                        if isAllDay {
                            let endDay = calendar.startOfDay(for: endDate)
                            return calendar.date(byAdding: .day, value: 1, to: max(endDay, normalizedStart)) ?? normalizedStart.addingTimeInterval(86_400)
                        } else {
                            return max(endDate, normalizedStart.addingTimeInterval(900))
                        }
                    }()
                    let event = CalendarEvent(id: originalEvent?.id ?? UUID(),
                                              title: title.isEmpty ? "予定" : title,
                                              startDate: normalizedStart,
                                              endDate: normalizedEnd,
                                              calendarName: category,
                                              isAllDay: isAllDay,
                                              reminderMinutes: hasReminder && useRelativeReminder ? reminderMinutes : nil,
                                              reminderDate: hasReminder && !useRelativeReminder ? reminderDate : nil)
                    onSave(event)
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル", role: .cancel) { dismiss() }
            }
        }
        .onChange(of: isAllDay) { _, newValue in
            if newValue {
                let calendar = Calendar.current
                startDate = calendar.startOfDay(for: startDate)
                endDate = calendar.startOfDay(for: max(endDate, startDate))
            }
        }
        .onChange(of: category) { _, newCategory in
            // 新規作成時のみカテゴリ変更で通知設定を連動
            guard originalEvent == nil else { return }
            let categoryEnabled = UserDefaults.standard.bool(forKey: "eventCategoryNotificationEnabled")
            guard categoryEnabled else { return }
            
            if let setting = NotificationSettingsManager.shared.getSetting(for: newCategory) {
                hasReminder = setting.enabled
                if setting.enabled {
                    useRelativeReminder = setting.useRelativeTime
                    if setting.useRelativeTime {
                        reminderMinutes = setting.minutesBefore
                        reminderDate = startDate.addingTimeInterval(-Double(setting.minutesBefore * 60))
                    } else {
                        // 時刻指定: 開始日の指定時刻に通知
                        let cal = Calendar.current
                        reminderDate = cal.date(bySettingHour: setting.hour, minute: setting.minute, second: 0, of: startDate) ?? startDate
                    }
                }
            } else {
                hasReminder = false
            }
        }
        .sheet(isPresented: $isShowingCategorySelection) {
            CategorySelectionView(selectedCategory: $category)
        }
        .confirmationDialog("この予定を削除しますか？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("キャンセル", role: .cancel) { }
        }
    }
}
