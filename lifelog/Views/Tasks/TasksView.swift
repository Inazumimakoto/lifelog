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
    @State private var showEditor = false
    @State private var editingTask: Task?

    init(store: AppDataStore) {
        _viewModel = StateObject(wrappedValue: TasksViewModel(store: store))
    }

    var body: some View {
        List {
            Section {
                Text("開始・終了日時を設定するとTodayやカレンダーのタイムラインに反映されます。終わったタスクはスワイプで削除できます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(TasksViewModel.TaskSection.allCases) { section in
                let tasks = viewModel.tasks(for: section)
                if tasks.isEmpty == false {
                    Section(section.rawValue) {
                        ForEach(tasks) { task in
                            TaskRowView(task: task, onToggle: {
                                viewModel.toggle(task: task)
                            })
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingTask = task
                                showEditor = true
                            }
                        }
                        .onDelete { offsets in
                            viewModel.delete(at: offsets, in: section)
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
                    editingTask = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                TaskEditorView(task: editingTask) { task in
                    if editingTask == nil {
                        viewModel.add(task)
                    } else {
                        viewModel.update(task)
                    }
                }
            }
        }
    }
}
