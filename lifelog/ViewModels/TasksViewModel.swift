//
//  TasksViewModel.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class TasksViewModel: ObservableObject {

    enum TaskSection: String, CaseIterable, Identifiable {
        case upcoming = "今後のタスク"
        case overdue = "期限切れ"
        case someday = "いつかやる"
        case completed = "完了済み"

        var id: String { rawValue }
    }

    @Published private(set) var tasks: [Task] = []
    private var pendingAnimation: Animation?

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
                guard let self else { return }
                let updates = { self.tasks = tasks }
                if let animation = self.pendingAnimation {
                    withAnimation(animation) {
                        updates()
                    }
                    self.pendingAnimation = nil
                } else {
                    updates()
                }
            }
            .store(in: &cancellables)
    }

    func tasks(for section: TaskSection) -> [Task] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        switch section {
        case .upcoming:
            return tasks.filter { task in
                guard !task.isCompleted else { return false }
                // 日付なし（いつか）タスクは除外
                guard let displayDate = displayDate(for: task) else { return false }
                return calendar.startOfDay(for: displayDate) >= todayStart
            }
            .sorted(by: sortTasks)
        case .overdue:
            return tasks.filter { task in
                guard !task.isCompleted else { return false }
                guard let displayDate = displayDate(for: task) else { return false }
                return calendar.startOfDay(for: displayDate) < todayStart
            }
            .sorted(by: sortTasks)
        case .someday:
            // startDateとendDateが両方nilのタスク
            return tasks.filter { task in
                guard !task.isCompleted else { return false }
                return task.startDate == nil && task.endDate == nil
            }
            .sorted(by: sortTasks)
        case .completed:
            return tasks
                .filter(\.isCompleted)
                .sorted(by: sortTasks)
        }
    }

    func addTask(title: String,
                 detail: String,
                 startDate: Date?,
                 endDate: Date?,
                 priority: TaskPriority) {
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: startDate ?? Date())
        let normalizedEnd = calendar.startOfDay(for: endDate ?? normalizedStart)
        let task = Task(title: title,
                        detail: detail,
                        startDate: normalizedStart,
                        endDate: max(normalizedStart, normalizedEnd),
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

    func delete(task: Task) {
        store.deleteTasks(withIDs: [task.id])
    }

    func toggle(task: Task) {
        pendingAnimation = .spring(response: 0.35, dampingFraction: 0.8)
        store.toggleTaskCompletion(task.id)
        
        // タスク完了をポジティブアクションとして記録（完了状態にする時のみ）
        if !task.isCompleted {
            ReviewRequestManager.shared.registerPositiveAction()
        }
    }

    private func isTask(_ task: Task, on date: Date, calendar: Calendar) -> Bool {
        let start = calendar.startOfDay(for: task.startDate ?? task.endDate ?? date)
        let end = calendar.startOfDay(for: task.endDate ?? task.startDate ?? date)
        let target = calendar.startOfDay(for: date)
        return start...end ~= target
    }

    private func displayDate(for task: Task) -> Date? {
        task.startDate ?? task.endDate
    }

    private func sortTasks(_ lhs: Task, _ rhs: Task) -> Bool {
        if lhs.priority.rawValue != rhs.priority.rawValue {
            return lhs.priority.rawValue > rhs.priority.rawValue
        }
        let lhsDate = displayDate(for: lhs) ?? .distantFuture
        let rhsDate = displayDate(for: rhs) ?? .distantFuture
        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }
        return lhs.title < rhs.title
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
