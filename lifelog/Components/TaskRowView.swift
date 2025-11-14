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

    init(task: Task,
         onToggle: (() -> Void)? = nil) {
        self.task = task
        self.onToggle = onToggle
    }

    private var priorityColor: Color {
        task.priority.color.opacity(0.8)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let onToggle {
                Button(action: onToggle) {
                    toggleIcon
                }
                .buttonStyle(.plain)
            } else {
                toggleIcon
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
                if let start = task.startDate {
                    dateSummary(start: start, end: task.endDate)
                } else if let end = task.endDate {
                    dateSummary(start: end, end: end)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: task.isCompleted)
    }

    private var toggleIcon: some View {
        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20))
            .foregroundStyle(task.isCompleted ? Color.accentColor : .secondary)
    }

    @ViewBuilder
    private func dateSummary(start: Date, end: Date?) -> some View {
        if let end, end != start {
            Text("\(start.jaMonthDayString) 〜 \(end.jaMonthDayString)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text(start.jaMonthDayString)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
