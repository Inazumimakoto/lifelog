//
//  AppDataStore+Tasks.swift
//  lifelog
//

import Foundation
import SwiftData

extension AppDataStore {

    // MARK: - Task CRUD

    func addTask(_ task: Task) {
        tasks.append(task)

        let sdTask = SDTask(domain: task)
        modelContext.insert(sdTask)
        saveContext()

        scheduleTaskNotification(task)
        rescheduleTodayOverviewReminderIfNeeded()
    }

    func updateTask(_ task: Task) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task

        let taskID = task.id
        let descriptor = FetchDescriptor<SDTask>(predicate: #Predicate { $0.id == taskID })
        if let existing = try? modelContext.fetch(descriptor).first {
             existing.update(from: task)
             saveContext()
        }

        scheduleTaskNotification(task)
        rescheduleTodayOverviewReminderIfNeeded()
    }

    func deleteTasks(at offsets: IndexSet) {
        let idsToDelete = offsets.compactMap { index -> UUID? in
            guard tasks.indices.contains(index) else { return nil }
            return tasks[index].id
        }

        for index in offsets.sorted(by: >) where tasks.indices.contains(index) {
            taskNotificationService.cancelTaskReminder(taskId: tasks[index].id)
            tasks.remove(at: index)
        }

        persistTaskDeletion(withIDs: idsToDelete)
    }

    func deleteTasks(withIDs ids: [UUID]) {
        for id in ids {
            taskNotificationService.cancelTaskReminder(taskId: id)
        }
        tasks.removeAll { ids.contains($0.id) }

        persistTaskDeletion(withIDs: ids)
    }

    private func persistTaskDeletion(withIDs ids: [UUID]) {
        for id in ids {
            let descriptor = FetchDescriptor<SDTask>(predicate: #Predicate { $0.id == id })
            if let existing = try? modelContext.fetch(descriptor).first {
                modelContext.delete(existing)
            }
        }
        saveContext()
        rescheduleTodayOverviewReminderIfNeeded()
    }

    func toggleTaskCompletion(_ taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].isCompleted.toggle()
        // Set completedAt when completed, clear when uncompleted
        tasks[index].completedAt = tasks[index].isCompleted ? Date() : nil

        let descriptor = FetchDescriptor<SDTask>(predicate: #Predicate { $0.id == taskID })
        if let existing = try? modelContext.fetch(descriptor).first {
             existing.isCompleted = tasks[index].isCompleted
             existing.completedAt = tasks[index].completedAt
             saveContext()
        }
        scheduleTaskNotification(tasks[index])
        rescheduleTodayOverviewReminderIfNeeded()
    }

    // MARK: - Task Notification Helpers

    func scheduleTaskNotification(_ task: Task) {
        // キャンセルしてから再スケジュール
        taskNotificationService.cancelTaskReminder(taskId: task.id)
        if !task.isCompleted, let reminderDate = task.reminderDate {
            taskNotificationService.scheduleTaskReminder(
                taskId: task.id,
                title: task.title,
                reminderDate: reminderDate
            )
        }
    }

    func taskPriorityDefaultReminderDate(for task: Task, setting: PriorityNotificationSetting?) -> Date? {
        guard let setting, setting.enabled else { return nil }
        let baseDate = TaskPresentation.displayDate(for: task, preferring: .start)
        guard let baseDate else { return nil }
        return Calendar.current.date(bySettingHour: setting.hour, minute: setting.minute, second: 0, of: baseDate)
    }

    func reminderDate(_ lhs: Date?, matches rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return Calendar.current.compare(lhs, to: rhs, toGranularity: .minute) == .orderedSame
        default:
            return false
        }
    }

    func isTask(_ task: Task, scheduledOn date: Date) -> Bool {
        TaskPresentation.isScheduled(task, on: date)
    }

    // MARK: - Task Persister

}
