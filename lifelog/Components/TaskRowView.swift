//
//  TaskRowView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct TaskRowView: View {
    let task: Task
    var onToggle: (() -> Void)?

    private var priorityColor: Color {
        task.priority.color.opacity(0.8)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let onToggle {
                Button(action: onToggle) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(task.isCompleted ? Color.accentColor : .secondary)
                }
            } else {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(task.isCompleted ? Color.accentColor : .secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(task.title)
                        .font(.body.weight(.semibold))
                        .strikethrough(task.isCompleted, color: .primary.opacity(0.6))
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    Spacer()
                    Circle()
                        .fill(priorityColor)
                        .frame(width: 8, height: 8)
                }
                if task.detail.isEmpty == false {
                    Text(task.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let dueDate = task.dueDate {
                    Text(dueDate.formattedTime())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
