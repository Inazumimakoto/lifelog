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
    @State private var hasStartDate: Bool
    @State private var startDate: Date
    @State private var startLabel: String
    @State private var endLabel: String

    private var editorCalendar: Calendar {
        let identifier = editingAnniversary?.dateOnlyTimeZoneIdentifier
        if let identifier, let zone = TimeZone(identifier: identifier) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            return calendar
        }
        return .current
    }

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
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = TimeZone(identifier: anniversary?.dateOnlyTimeZoneIdentifier ?? "") ?? .current
        let defaultTime = sourceCalendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        _reminderTime = State(initialValue: anniversary?.reminderTime ?? defaultTime)
        // 日時指定の初期値: 次回の記念日 - reminderDaysBefore の reminderTime
        let originalTargetDate = anniversary?.targetDate ?? Date()
        let defaultDays = anniversary?.reminderDaysBefore ?? 1
        let defaultReminderDate: Date = {
            let calendar = Calendar.current
            let today = Date()
            
            // 次回の記念日を計算（過去なら来年に進める）
            var nextTargetDate = originalTargetDate
            if anniversary?.repeatsYearly == true, nextTargetDate < today {
                nextTargetDate = calendar.nextDate(after: today,
                    matching: calendar.dateComponents([.month, .day, .hour, .minute], from: originalTargetDate),
                    matchingPolicy: .nextTimePreservingSmallerComponents) ?? originalTargetDate
            }
            
            guard let reminderDay = calendar.date(byAdding: .day, value: -defaultDays, to: nextTargetDate) else { return nextTargetDate }
            let hour = calendar.component(.hour, from: defaultTime)
            let minute = calendar.component(.minute, from: defaultTime)
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: reminderDay) ?? reminderDay
        }()
        _reminderDate = State(initialValue: anniversary?.reminderDate ?? defaultReminderDate)
        _hasStartDate = State(initialValue: anniversary?.startDate != nil)
        _startDate = State(initialValue: anniversary?.startDate ?? Date())
        _startLabel = State(initialValue: anniversary?.startLabel ?? "")
        _endLabel = State(initialValue: anniversary?.endLabel ?? "")
    }

    var body: some View {
        Form {
            Section("基本情報") {
                TextField("タイトル", text: $title)
                // 日付範囲: 毎年繰り返しOFFの場合のみ制限
                datePicker
                Picker("種類", selection: $type) {
                    ForEach(AnniversaryType.allCases) { type in
                        Text(type == .countdown ? "までの残り日数" : "経過日数").tag(type)
                    }
                }
                Toggle("毎年繰り返す", isOn: $repeatsYearly)
                    .disabled(hasStartDate)
                if repeatsYearly {
                    Text("通知は毎年この月日に届きます（年は無視されます）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if hasStartDate {
                    Text("開始日が設定されているため無効です")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("開始日") {
                Toggle("開始日を設定", isOn: $hasStartDate)
                    .disabled(repeatsYearly)
                if hasStartDate {
                    DatePicker("開始日", selection: $startDate, in: ...date, displayedComponents: .date)
                    TextField("開始ラベル（例：生まれてから）", text: $startLabel)
                    TextField("終了ラベル（例：100歳まで）", text: $endLabel)
                    Text("進捗バーと経過/残り日数が表示されます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if repeatsYearly {
                    Text("毎年繰り返しが設定されているため無効です")
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
                            updateAbsoluteReminderPreview(daysBefore: newValue, time: reminderTime)
                        }
                        DatePicker("通知時刻", selection: $reminderTime, displayedComponents: .hourAndMinute)
                            .onChange(of: reminderTime) { _, newValue in
                                updateAbsoluteReminderPreview(daysBefore: reminderDaysBefore, time: newValue)
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
        .environment(\.calendar, editorCalendar)
        .environment(\.timeZone, editorCalendar.timeZone)
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
                        startDate: hasStartDate ? startDate : nil,
                        startLabel: hasStartDate && !startLabel.isEmpty ? startLabel : nil,
                        endLabel: hasStartDate && !endLabel.isEmpty ? endLabel : nil,
                        reminderDaysBefore: hasReminder && useRelativeReminder ? reminderDaysBefore : nil,
                        reminderTime: hasReminder && useRelativeReminder ? reminderTime : nil,
                        reminderDate: hasReminder && !useRelativeReminder ? reminderDate : nil,
                        dateOnlyTimeZoneIdentifier: editorCalendar.timeZone.identifier
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
        .onChange(of: date) { _, _ in
            if !useRelativeReminder {
                updateAbsoluteReminderPreview(daysBefore: reminderDaysBefore, time: reminderTime)
            }
        }
    }
    
    @ViewBuilder
    private var datePicker: some View {
        // Existing records may legitimately have a past countdown or future
        // elapsed date. Opening their editor must not clamp the saved day.
        if editingAnniversary != nil || repeatsYearly {
            DatePicker("日付", selection: $date, displayedComponents: .date)
        } else if type == .since {
            DatePicker("日付", selection: $date, in: ...Date(), displayedComponents: .date)
        } else {
            DatePicker("日付", selection: $date, in: Date()..., displayedComponents: .date)
        }
    }

    private func updateAbsoluteReminderPreview(daysBefore: Int, time: Date) {
        let calendar = editorCalendar
        var nextTarget = date
        if repeatsYearly && nextTarget < Date() {
            nextTarget = calendar.nextDate(after: Date(),
                matching: calendar.dateComponents([.month, .day, .hour, .minute], from: date),
                matchingPolicy: .nextTimePreservingSmallerComponents) ?? date
        }
        guard let day = calendar.date(byAdding: .day, value: -daysBefore, to: nextTarget) else { return }
        reminderDate = calendar.date(bySettingHour: calendar.component(.hour, from: time),
                                     minute: calendar.component(.minute, from: time), second: 0, of: day) ?? day
    }
}
