//
//  CalendarEventEditorView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct CalendarEventEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var formState: CalendarEventEditorFormState
    @StateObject private var detailDraft: LongFormTextDraft
    @ObservedObject private var categoryPalette = CategoryPaletteObserver.shared
    @State private var isShowingCategorySelection = false
    @State private var showDeleteConfirmation = false
    @State private var didFinishEditing = false

    var onSave: (CalendarEvent) -> Void
    var onDelete: (() -> Void)?

    private let originalEvent: CalendarEvent?
    private let defaultDate: Date
    private var isReadOnly: Bool { originalEvent?.sourceCalendarIdentifier != nil }

    init(defaultDate: Date = Date(),
         event: CalendarEvent? = nil,
         onSave: @escaping (CalendarEvent) -> Void,
         onDelete: (() -> Void)? = nil) {
        self.onSave = onSave
        self.onDelete = onDelete
        self.originalEvent = event
        self.defaultDate = defaultDate
        let formState = CalendarEventEditorFormState(event: event, defaultDate: defaultDate)
        _formState = StateObject(wrappedValue: formState)
        _detailDraft = StateObject(wrappedValue: LongFormTextDraft(text: formState.detail))
    }

    var body: some View {
        Form {
            Section("予定") {
                TextField("タイトル", text: $formState.title)
                DetailMemoEditor(draft: detailDraft) { newValue in
                    formState.cacheDraft(detailOverride: newValue)
                }
                Button(action: { isShowingCategorySelection = true }) {
                    HStack {
                        Text("カテゴリ")
                        Spacer()
                        Circle()
                            .fill(CategoryPalette.color(for: formState.category))
                            .frame(width: 10, height: 10)
                        Text(CategoryPalette.displayName(for: formState.category))
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
                            formState.startDate = formState.calendar.startOfDay(for: newValue)
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
                            formState.endDate = formState.calendar.startOfDay(for: formState.endDate)
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
            
            if originalEvent != nil && onDelete != nil && !isReadOnly {
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
        .disabled(isReadOnly)
        .environment(\.calendar, formState.calendar)
        .environment(\.timeZone, formState.calendar.timeZone)
        .navigationTitle(originalEvent == nil ? "予定を追加" : "予定を編集")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let event = formState.makeEvent(detailOverride: detailDraft.text)
                    onSave(event)
                    didFinishEditing = true
                    formState.clearCachedDraft()
                    dismiss()
                }
                .disabled(isReadOnly || formState.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル", role: .cancel) {
                    didFinishEditing = true
                    formState.clearCachedDraft()
                    dismiss()
                }
            }
        }
        .onChange(of: formState.draft) { _, _ in
            formState.cacheDraft(detailOverride: detailDraft.text)
        }
        .onChange(of: formState.isAllDay) { _, newValue in
            if newValue {
                let calendar = formState.calendar
                formState.startDate = calendar.startOfDay(for: formState.startDate)
                formState.endDate = calendar.startOfDay(for: max(formState.endDate, formState.startDate))
            }
        }
        .sheet(isPresented: $isShowingCategorySelection) {
            CategorySelectionView(selectedCategory: Binding(
                get: { formState.category },
                set: { formState.selectCategory($0) }
            ))
        }
        .confirmationDialog("この予定を削除しますか？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                onDelete?()
                didFinishEditing = true
                formState.clearCachedDraft()
                dismiss()
            }
            Button("キャンセル", role: .cancel) { }
        }
        .onDisappear {
            if !didFinishEditing && !isReadOnly {
                formState.cacheDraft(detailOverride: detailDraft.text)
            }
        }
    }
}
