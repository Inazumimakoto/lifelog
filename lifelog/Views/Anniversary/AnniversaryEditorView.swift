//
//  AnniversaryEditorView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct AnniversaryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (Anniversary) -> Void
    var onDelete: (() -> Void)?
    private var editingAnniversary: Anniversary?

    @State private var title: String
    @State private var date: Date
    @State private var type: AnniversaryType
    @State private var repeatsYearly: Bool
    @State private var showDeleteConfirmation = false
    @State private var hasReminder: Bool
    @State private var useRelativeReminder: Bool
    @State private var reminderDaysBefore: Int
    @State private var reminderTime: Date
    @State private var reminderDate: Date

    init(anniversary: Anniversary? = nil,
         onSave: @escaping (Anniversary) -> Void,
         onDelete: (() -> Void)? = nil) {
        self.editingAnniversary = anniversary
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: anniversary?.title ?? "")
        _date = State(initialValue: anniversary?.targetDate ?? Date())
        _type = State(initialValue: anniversary?.type ?? .countdown)
        _repeatsYearly = State(initialValue: anniversary?.repeatsYearly ?? false)
        let hasReminderValue = anniversary?.reminderDaysBefore != nil || anniversary?.reminderDate != nil
        _hasReminder = State(initialValue: hasReminderValue)
        _useRelativeReminder = State(initialValue: anniversary?.reminderDate == nil)
        _reminderDaysBefore = State(initialValue: anniversary?.reminderDaysBefore ?? 1)
        let defaultTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        _reminderTime = State(initialValue: anniversary?.reminderTime ?? defaultTime)
        // 日時指定の初期値: 次回の記念日 - reminderDaysBefore の reminderTime
        let originalTargetDate = anniversary?.targetDate ?? Date()
        let defaultDays = anniversary?.reminderDaysBefore ?? 1
        let defaultReminderDate: Date = {
            let calendar = Calendar.current
            let today = Date()
            
            // 次回の記念日を計算（過去なら来年に進める）
            var nextTargetDate = originalTargetDate
            while nextTargetDate < today {
                nextTargetDate = calendar.date(byAdding: .year, value: 1, to: nextTargetDate) ?? nextTargetDate
            }
            
            guard let reminderDay = calendar.date(byAdding: .day, value: -defaultDays, to: nextTargetDate) else { return nextTargetDate }
            let hour = calendar.component(.hour, from: defaultTime)
            let minute = calendar.component(.minute, from: defaultTime)
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: reminderDay) ?? reminderDay
        }()
        _reminderDate = State(initialValue: anniversary?.reminderDate ?? defaultReminderDate)
    }

    var body: some View {
        Form {
            Section("基本情報") {
                TextField("タイトル", text: $title)
                DatePicker("日付", selection: $date, displayedComponents: .date)
                    .onChange(of: date) { _, newValue in
                        // 日時指定モードの場合、reminderDateも連動更新
                        if !useRelativeReminder {
                            let calendar = Calendar.current
                            let today = Date()
                            
                            // 次回の記念日を計算
                            var nextTargetDate = newValue
                            while nextTargetDate < today {
                                nextTargetDate = calendar.date(byAdding: .year, value: 1, to: nextTargetDate) ?? nextTargetDate
                            }
                            
                            if let reminderDay = calendar.date(byAdding: .day, value: -reminderDaysBefore, to: nextTargetDate) {
                                let hour = calendar.component(.hour, from: reminderTime)
                                let minute = calendar.component(.minute, from: reminderTime)
                                reminderDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: reminderDay) ?? reminderDay
                            }
                        }
                    }
                Picker("種類", selection: $type) {
                    ForEach(AnniversaryType.allCases) { type in
                        Text(type == .countdown ? "までの残り日数" : "経過日数").tag(type)
                    }
                }
                Toggle("毎年繰り返す", isOn: $repeatsYearly)
                if repeatsYearly {
                    Text("通知は毎年この月日に届きます（年は無視されます）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("通知") {
                Toggle("リマインダー", isOn: $hasReminder)
                if hasReminder {
                    Picker("通知方法", selection: $useRelativeReminder) {
                        Text("記念日前").tag(true)
                        Text("日時指定").tag(false)
                    }
                    .pickerStyle(.segmented)
                    
                    if useRelativeReminder {
                        Picker("何日前", selection: $reminderDaysBefore) {
                            Text("当日").tag(0)
                            Text("1日前").tag(1)
                            Text("3日前").tag(3)
                            Text("1週間前").tag(7)
                        }
                        .onChange(of: reminderDaysBefore) { _, newValue in
                            // 何日前変更時も日時指定を更新（次回の記念日を基準）
                            let calendar = Calendar.current
                            let today = Date()
                            var nextTargetDate = date
                            while nextTargetDate < today {
                                nextTargetDate = calendar.date(byAdding: .year, value: 1, to: nextTargetDate) ?? nextTargetDate
                            }
                            if let reminderDay = calendar.date(byAdding: .day, value: -newValue, to: nextTargetDate) {
                                let hour = calendar.component(.hour, from: reminderTime)
                                let minute = calendar.component(.minute, from: reminderTime)
                                reminderDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: reminderDay) ?? reminderDay
                            }
                        }
                        DatePicker("通知時刻", selection: $reminderTime, displayedComponents: .hourAndMinute)
                            .onChange(of: reminderTime) { _, newValue in
                                // 通知時刻変更時も日時指定を更新（次回の記念日を基準）
                                let calendar = Calendar.current
                                let today = Date()
                                var nextTargetDate = date
                                while nextTargetDate < today {
                                    nextTargetDate = calendar.date(byAdding: .year, value: 1, to: nextTargetDate) ?? nextTargetDate
                                }
                                if let reminderDay = calendar.date(byAdding: .day, value: -reminderDaysBefore, to: nextTargetDate) {
                                    let hour = calendar.component(.hour, from: newValue)
                                    let minute = calendar.component(.minute, from: newValue)
                                    reminderDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: reminderDay) ?? reminderDay
                                }
                            }
                    } else {
                        DatePicker("通知日時", selection: $reminderDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }
            }
            
            if editingAnniversary != nil && onDelete != nil {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("記念日を削除")
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle(editingAnniversary == nil ? "記念日を追加" : "記念日を編集")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let item = Anniversary(
                        id: editingAnniversary?.id ?? UUID(),
                        title: title,
                        targetDate: date,
                        type: type,
                        repeatsYearly: repeatsYearly,
                        reminderDaysBefore: hasReminder && useRelativeReminder ? reminderDaysBefore : nil,
                        reminderTime: hasReminder && useRelativeReminder ? reminderTime : nil,
                        reminderDate: hasReminder && !useRelativeReminder ? reminderDate : nil
                    )
                    onSave(item)
                    HapticManager.medium()
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル", role: .cancel) { dismiss() }
            }
        }
        .confirmationDialog("この記念日を削除しますか？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("キャンセル", role: .cancel) { }
        }
    }
}
