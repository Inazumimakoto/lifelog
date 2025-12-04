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
                    }
                DatePicker("終了", selection: $endDate, in: startDate..., displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                    .onChange(of: endDate) { _, newValue in
                        endDate = max(newValue, startDate)
                        if isAllDay {
                            endDate = Calendar.current.startOfDay(for: endDate)
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
                                              isAllDay: isAllDay)
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
