//
//  TasksView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct TasksView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: TasksViewModel
    @State private var showAddEditor = false
    @State private var editingTask: Task?

    init(store: AppDataStore) {
        _viewModel = StateObject(wrappedValue: TasksViewModel(store: store))
    }

    var body: some View {
        List {
            Section {
                Text("開始・終了日時を設定するとTodayやカレンダーのタイムラインに反映されます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(TasksViewModel.TaskSection.allCases) { section in
                let tasks = viewModel.tasks(for: section)
                if tasks.isEmpty == false {
                    Section(section.rawValue) {
                        ForEach(tasks) { task in
                            HStack {
                                TaskRowView(task: task, onToggle: {
                                    viewModel.toggle(task: task)
                                })
                                Spacer()
                                Button {
                                    editingTask = task
                                } label: {
                                    Image(systemName: "square.and.pencil")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
            if viewModel.tasks.isEmpty {
                VStack(spacing: 12) {
                    Text("タスクはまだありません")
                        .font(.headline)
                    Text("右上の＋ボタンから自由に追加してください。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("タスク")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("閉じる") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddEditor) {
            NavigationStack {
                TaskEditorView(onSave: { task in
                    viewModel.add(task)
                })
            }
        }
        .sheet(item: $editingTask) { task in
            NavigationStack {
                TaskEditorView(task: task,
                               onSave: { updated in
                    viewModel.update(updated)
                },
                               onDelete: {
                    viewModel.delete(task: task)
                })
            }
        }
    }
}
