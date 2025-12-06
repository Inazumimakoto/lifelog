//
//  NotificationSettingsView.swift
//  lifelog
//
//  Created by Codex on 2025/12/06.
//

import SwiftUI

struct NotificationSettingsView: View {
    // 日記リマインダー設定
    @AppStorage("diaryReminderEnabled") private var diaryReminderEnabled: Bool = false
    @AppStorage("diaryReminderHour") private var diaryReminderHour: Int = 21
    @AppStorage("diaryReminderMinute") private var diaryReminderMinute: Int = 0
    
    // 予定・タスク通知の親トグル
    @AppStorage("eventCategoryNotificationEnabled") private var eventCategoryNotificationEnabled: Bool = false
    @AppStorage("taskPriorityNotificationEnabled") private var taskPriorityNotificationEnabled: Bool = false
    
    // カテゴリ・優先度設定
    @State private var categorySettings: [CategoryNotificationSetting] = []
    @State private var prioritySettings: [PriorityNotificationSetting] = []
    
    private let reminderOptions: [(String, Int)] = [
        ("5分前", 5),
        ("15分前", 15),
        ("30分前", 30),
        ("1時間前", 60),
        ("1日前", 1440)
    ]
    
    var body: some View {
        Form {
            // 日記リマインダーセクション
            diaryReminderSection
            
            // 予定セクション
            eventSection
            
            // タスクセクション
            taskSection
        }
        .navigationTitle("通知")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadSettings()
        }
        .onChange(of: diaryReminderEnabled) { _, enabled in
            updateDiaryReminder(enabled: enabled)
        }
        .onChange(of: diaryReminderHour) { _, _ in
            if diaryReminderEnabled {
                updateDiaryReminder(enabled: true)
            }
        }
        .onChange(of: diaryReminderMinute) { _, _ in
            if diaryReminderEnabled {
                updateDiaryReminder(enabled: true)
            }
        }
    }
    
    // MARK: - Sections
    
    private var diaryReminderSection: some View {
        Section {
            Toggle("日記リマインダー", isOn: $diaryReminderEnabled)
            
            if diaryReminderEnabled {
                DatePicker(
                    "通知時刻",
                    selection: diaryReminderTimeBinding,
                    displayedComponents: .hourAndMinute
                )
            }
            
            Text("その日の日記が未記入の場合に通知します。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("日記リマインダー")
        }
    }
    
    private var eventSection: some View {
        Section {
            Toggle("カテゴリごとの通知設定", isOn: $eventCategoryNotificationEnabled)
            
            if eventCategoryNotificationEnabled {
                ForEach($categorySettings) { $setting in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle()
                                .fill(CategoryPalette.color(for: setting.categoryName))
                                .frame(width: 12, height: 12)
                            Text(setting.categoryName)
                            Spacer()
                            Toggle("", isOn: $setting.enabled)
                                .labelsHidden()
                        }
                        
                        if setting.enabled {
                            Picker("通知タイミング", selection: $setting.minutesBefore) {
                                ForEach(reminderOptions, id: \.1) { option in
                                    Text(option.0).tag(option.1)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .padding(.vertical, 4)
                    .onChange(of: setting) { _, newValue in
                        saveCategorySettings()
                    }
                }
            }
            
            Text("新規作成時のデフォルト値です。個別に変更できます。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("予定")
        }
    }
    
    private var taskSection: some View {
        Section {
            Toggle("優先度ごとの通知設定", isOn: $taskPriorityNotificationEnabled)
            
            if taskPriorityNotificationEnabled {
                ForEach($prioritySettings) { $setting in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(priorityLabel(for: setting.priority))
                            Spacer()
                            Toggle("", isOn: $setting.enabled)
                                .labelsHidden()
                        }
                        
                        if setting.enabled {
                            DatePicker(
                                "通知時刻",
                                selection: priorityTimeBinding(for: $setting),
                                displayedComponents: .hourAndMinute
                            )
                        }
                    }
                    .padding(.vertical, 4)
                    .onChange(of: setting) { _, newValue in
                        savePrioritySettings()
                    }
                }
            }
            
            Text("新規作成時のデフォルト値です。個別に変更できます。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("タスク")
        }
    }
    
    // MARK: - Bindings
    
    private var diaryReminderTimeBinding: Binding<Date> {
        Binding<Date>(
            get: {
                var components = DateComponents()
                components.hour = diaryReminderHour
                components.minute = diaryReminderMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                diaryReminderHour = components.hour ?? 21
                diaryReminderMinute = components.minute ?? 0
            }
        )
    }
    
    private func priorityTimeBinding(for setting: Binding<PriorityNotificationSetting>) -> Binding<Date> {
        Binding<Date>(
            get: {
                var components = DateComponents()
                components.hour = setting.wrappedValue.hour
                components.minute = setting.wrappedValue.minute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                setting.wrappedValue.hour = components.hour ?? 9
                setting.wrappedValue.minute = components.minute ?? 0
            }
        )
    }
    
    // MARK: - Helpers
    
    private func priorityLabel(for priority: Int) -> String {
        if let taskPriority = TaskPriority(rawValue: priority) {
            return taskPriority.label
        }
        return "\(priority)"
    }
    
    private func loadSettings() {
        // Load category settings, ensuring all current categories are included
        let allCategories = CategoryPalette.allCategoryNames()
        var existingSettings = NotificationSettingsManager.shared.getCategorySettings()
        
        for category in allCategories {
            if !existingSettings.contains(where: { $0.categoryName == category }) {
                existingSettings.append(CategoryNotificationSetting(categoryName: category))
            }
        }
        categorySettings = existingSettings.sorted { $0.categoryName < $1.categoryName }
        
        // Load priority settings
        prioritySettings = NotificationSettingsManager.shared.getPrioritySettings()
    }
    
    private func saveCategorySettings() {
        NotificationSettingsManager.shared.saveCategorySettings(categorySettings)
    }
    
    private func savePrioritySettings() {
        NotificationSettingsManager.shared.savePrioritySettings(prioritySettings)
    }
    
    private func updateDiaryReminder(enabled: Bool) {
        if enabled {
            NotificationService.shared.scheduleDiaryReminder(hour: diaryReminderHour, minute: diaryReminderMinute)
        } else {
            NotificationService.shared.cancelDiaryReminder()
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
}
