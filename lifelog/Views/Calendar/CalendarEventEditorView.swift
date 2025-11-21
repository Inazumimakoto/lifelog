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

    var onSave: (CalendarEvent) -> Void

    private let originalEvent: CalendarEvent?

    @State private var title: String
    @State private var category: String
    @State private var startDate: Date
    @State private var endDate: Date

    init(defaultDate: Date = Date(),
         event: CalendarEvent? = nil,
         onSave: @escaping (CalendarEvent) -> Void) {
        self.onSave = onSave
        self.originalEvent = event
        let initialStart = event?.startDate ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: defaultDate) ?? defaultDate
        _title = State(initialValue: event?.title ?? "")
        _category = State(initialValue: event?.calendarName ?? "個人")
        _startDate = State(initialValue: initialStart)
        _endDate = State(initialValue: event?.endDate ?? initialStart.addingTimeInterval(3600))
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
                DatePicker("開始", selection: $startDate)
                DatePicker("終了", selection: $endDate)
            }
        }
        .navigationTitle(originalEvent == nil ? "予定を追加" : "予定を編集")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let event = CalendarEvent(id: originalEvent?.id ?? UUID(),
                                              title: title.isEmpty ? "予定" : title,
                                              startDate: startDate,
                                              endDate: max(endDate, startDate.addingTimeInterval(900)),
                                              calendarName: category)
                    onSave(event)
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル", role: .cancel) { dismiss() }
            }
        }
        .sheet(isPresented: $isShowingCategorySelection) {
            CategorySelectionView(selectedCategory: $category)
        }
    }
}
