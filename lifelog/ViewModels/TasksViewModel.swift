//
//  TasksViewModel.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import Combine

@MainActor
final class TasksViewModel: ObservableObject {

    enum TaskSection: String, CaseIterable, Identifiable {
        case today = "今日が期限"
        case upcoming = "今後のタスク"
        case completed = "完了済み"

        var id: String { rawValue }
    }

    @Published private(set) var tasks: [Task] = []

    private let store: AppDataStore
    private var cancellables = Set<AnyCancellable>()

    init(store: AppDataStore) {
        self.store = store
        bind()
    }

    private func bind() {
        store.$tasks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tasks in
                self?.tasks = tasks
            }
            .store(in: &cancellables)
    }

    func tasks(for section: TaskSection) -> [Task] {
        let calendar = Calendar.current
        switch section {
        case .today:
            return tasks.filter { task in
                guard let dueDate = task.dueDate else { return false }
                return calendar.isDateInToday(dueDate) && !task.isCompleted
            }
        case .upcoming:
            return tasks.filter { task in
                guard let dueDate = task.dueDate else { return false }
                return dueDate > Date() && !calendar.isDateInToday(dueDate) && !task.isCompleted
            }.sorted(by: { ($0.dueDate ?? Date.distantFuture) < ($1.dueDate ?? Date.distantFuture) })
        case .completed:
            return tasks.filter { $0.isCompleted }
        }
    }

    func addTask(title: String,
                 detail: String,
                 dueDate: Date?,
                 priority: TaskPriority) {
        let task = Task(title: title,
                        detail: detail,
                        dueDate: dueDate,
                        priority: priority,
                        isCompleted: false)
        store.addTask(task)
    }

    func add(_ task: Task) {
        store.addTask(task)
    }

    func update(_ task: Task) {
        store.updateTask(task)
    }

    func delete(at offsets: IndexSet, in section: TaskSection) {
        let sectionTasks = tasks(for: section)
        let idsToDelete = offsets.compactMap { sectionTasks[safe: $0]?.id }
        store.deleteTasks(withIDs: idsToDelete)
    }

    func toggle(task: Task) {
        store.toggleTaskCompletion(task.id)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
