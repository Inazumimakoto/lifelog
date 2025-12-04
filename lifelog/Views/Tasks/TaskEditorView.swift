//
//  TaskEditorView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false

    var onSave: (Task) -> Void
    var onDelete: (() -> Void)?

    private let originalTask: Task?
    private let defaultDate: Date?
    private let calendar = Calendar.current

    @State private var title: String
    @State private var detail: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var priority: TaskPriority

    init(task: Task? = nil,
         defaultDate: Date? = nil,
         onSave: @escaping (Task) -> Void,
         onDelete: (() -> Void)? = nil) {
        self.onSave = onSave
        self.onDelete = onDelete
        self.originalTask = task
        self.defaultDate = defaultDate
        let base = calendar.startOfDay(for: task?.startDate ?? defaultDate ?? Date())
        let end = calendar.startOfDay(for: task?.endDate ?? base)
        _title = State(initialValue: task?.title ?? "")
        _detail = State(initialValue: task?.detail ?? "")
        _startDate = State(initialValue: base)
        _endDate = State(initialValue: max(base, end))
        _priority = State(initialValue: task?.priority ?? .medium)
    }

    var body: some View {
        Form {
            Section("タスク内容") {
                TextField("タイトルを入力", text: $title)
                TextField("詳細メモ（任意）", text: $detail, axis: .vertical)
                DatePicker("開始日", selection: $startDate, displayedComponents: [.date])
                    .onChange(of: startDate) { newValue in
                        startDate = calendar.startOfDay(for: newValue)
                        if endDate < startDate {
                            endDate = startDate
                        }
                    }
                DatePicker("終了日", selection: $endDate, in: startDate..., displayedComponents: [.date])
                    .onChange(of: endDate) { newValue in
                        endDate = max(calendar.startOfDay(for: newValue), startDate)
                    }
                Picker("優先度", selection: $priority) {
                    ForEach(TaskPriority.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                Text("開始日と終了日が同じ場合は単日タスクとして扱われます。複数日にまたがる場合は期間全体に表示されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                                    title: title,
                                    detail: detail,
                                    startDate: calendar.startOfDay(for: startDate),
                                    endDate: calendar.startOfDay(for: endDate),
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
        .confirmationDialog("このタスクを削除しますか？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("キャンセル", role: .cancel) { }
        }
    }
}
