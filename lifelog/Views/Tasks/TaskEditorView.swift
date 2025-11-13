//
//  TaskEditorView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss

    var onSave: (Task) -> Void

    private let originalTask: Task?

    @State private var title: String
    @State private var detail: String
    @State private var dueDate: Date?
    @State private var priority: TaskPriority

    init(task: Task? = nil,
         defaultDueDate: Date? = nil,
         onSave: @escaping (Task) -> Void) {
        self.onSave = onSave
        self.originalTask = task
        _title = State(initialValue: task?.title ?? "")
        _detail = State(initialValue: task?.detail ?? "")
        _dueDate = State(initialValue: task?.dueDate ?? defaultDueDate)
        _priority = State(initialValue: task?.priority ?? .medium)
    }

    var body: some View {
        Form {
            Section("タスク内容") {
                TextField("タイトルを入力", text: $title)
                TextField("詳細メモ（任意）", text: $detail, axis: .vertical)
                Toggle("期限を設定する", isOn: Binding(
                    get: { dueDate != nil },
                    set: { hasDate in
                        dueDate = hasDate ? (dueDate ?? Date()) : nil
                    }
                ))
                if dueDate != nil {
                    DatePicker("期限", selection: dueDateBinding, displayedComponents: [.date, .hourAndMinute])
                }
                Picker("優先度", selection: $priority) {
                    ForEach(TaskPriority.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                Text("期限を指定するとToday以外の日にも表示されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("タスク")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let task = Task(id: originalTask?.id ?? UUID(),
                                    title: title,
                                    detail: detail,
                                    dueDate: dueDate,
                                    priority: priority,
                                    isCompleted: originalTask?.isCompleted ?? false)
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
    }
    private var dueDateBinding: Binding<Date> {
        Binding<Date>(
            get: { dueDate ?? Date() },
            set: { newValue in dueDate = newValue }
        )
    }
}
