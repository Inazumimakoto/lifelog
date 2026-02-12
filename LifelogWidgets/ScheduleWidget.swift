//
//  ScheduleWidget.swift
//  LifelogWidgets
//
//  Rebuilt for daily agenda overview
//

import WidgetKit
import SwiftUI
import SwiftData
import UIKit

struct ScheduleEventItem: Identifiable {
    let id: UUID
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
}

struct ScheduleTaskItem: Identifiable {
    let id: UUID
    let title: String
    let priority: TaskPriority
}

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let events: [ScheduleEventItem]
    let tasks: [ScheduleTaskItem]
}

struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(
            date: Date(),
            events: [
                ScheduleEventItem(
                    id: UUID(),
                    title: "10:00 チームMTG",
                    startDate: Date(),
                    endDate: Date().addingTimeInterval(60 * 60),
                    isAllDay: false
                )
            ],
            tasks: [
                ScheduleTaskItem(id: UUID(), title: "週次レポート提出", priority: .high),
                ScheduleTaskItem(id: UUID(), title: "買い物メモ整理", priority: .medium)
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        _Concurrency.Task { @MainActor in
            completion(loadEntry(for: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        _Concurrency.Task { @MainActor in
            let now = Date()
            let entry = loadEntry(for: now)
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(60 * 15)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    @MainActor
    private func loadEntry(for date: Date) -> ScheduleEntry {
        ScheduleEntry(
            date: date,
            events: fetchEvents(on: date),
            tasks: fetchTasks(on: date)
        )
    }

    @MainActor
    private func fetchEvents(on date: Date) -> [ScheduleEventItem] {
        do {
            let context = PersistenceController.shared.container.mainContext
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: date)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

            let descriptor = FetchDescriptor<SDCalendarEvent>(
                predicate: #Predicate<SDCalendarEvent> { $0.startDate < dayEnd && $0.endDate > dayStart },
                sortBy: [SortDescriptor(\.startDate)]
            )

            return try context.fetch(descriptor).map {
                ScheduleEventItem(
                    id: $0.id,
                    title: $0.title,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    isAllDay: $0.isAllDay
                )
            }
        } catch {
            return []
        }
    }

    @MainActor
    private func fetchTasks(on date: Date) -> [ScheduleTaskItem] {
        do {
            let context = PersistenceController.shared.container.mainContext
            let descriptor = FetchDescriptor<SDTask>(
                predicate: #Predicate<SDTask> { !$0.isCompleted }
            )
            let uncompleted = try context.fetch(descriptor)
            let filtered = uncompleted
                .filter { isTask($0, scheduledOn: date) }
                .sorted(by: sortTasks)

            return filtered.map {
                ScheduleTaskItem(id: $0.id, title: $0.title, priority: $0.priority)
            }
        } catch {
            return []
        }
    }

    private func isTask(_ task: SDTask, scheduledOn date: Date) -> Bool {
        let calendar = Calendar.current
        let start = task.startDate ?? task.endDate
        let end = task.endDate ?? task.startDate
        guard let anchor = start ?? end else { return false }
        let normalizedStart = calendar.startOfDay(for: start ?? anchor)
        let normalizedEnd = calendar.startOfDay(for: end ?? anchor)
        let target = calendar.startOfDay(for: date)
        return normalizedStart...normalizedEnd ~= target
    }

    private func sortTasks(_ lhs: SDTask, _ rhs: SDTask) -> Bool {
        if lhs.priority.rawValue != rhs.priority.rawValue {
            return lhs.priority.rawValue > rhs.priority.rawValue
        }
        let lhsDate = lhs.startDate ?? lhs.endDate ?? .distantFuture
        let rhsDate = rhs.startDate ?? rhs.endDate ?? .distantFuture
        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }
        return lhs.title < rhs.title
    }
}

private enum ScheduleWidgetFormatter {
    static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

struct ScheduleWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleProvider.Entry

    private var eventLimit: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 3
        default: return 6
        }
    }

    private var taskLimit: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 3
        default: return 6
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            sectionHeader(title: "予定", icon: "calendar")
            eventSection
            sectionHeader(title: "未完了タスク", icon: "checklist")
            taskSection
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(ScheduleWidgetFormatter.date.string(from: entry.date))
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Text(ScheduleWidgetFormatter.weekday.string(from: entry.date))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var eventSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if entry.events.isEmpty {
                emptyLine("予定はありません")
            } else {
                ForEach(entry.events.prefix(eventLimit)) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(event.isAllDay ? "終日" : timeLabel(for: event))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(event.title)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                }
                let overflow = entry.events.count - eventLimit
                if overflow > 0 {
                    summaryLine("他\(overflow)件")
                }
            }
        }
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if entry.tasks.isEmpty {
                emptyLine("未完了タスクはありません")
            } else {
                ForEach(entry.tasks.prefix(taskLimit)) { task in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(priorityColor(for: task.priority))
                            .frame(width: 6, height: 6)
                        Text(task.title)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                }
                let overflow = entry.tasks.count - taskLimit
                if overflow > 0 {
                    summaryLine("他\(overflow)件")
                }
            }
        }
    }

    private func timeLabel(for event: ScheduleEventItem) -> String {
        let start = ScheduleWidgetFormatter.time.string(from: event.startDate)
        let end = ScheduleWidgetFormatter.time.string(from: event.endDate)
        return "\(start)-\(end)"
    }

    private func priorityColor(for priority: TaskPriority) -> Color {
        switch priority {
        case .high:
            return .red
        case .medium:
            return .orange
        case .low:
            return .green
        }
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func summaryLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
    }
}

struct ScheduleWidget: Widget {
    let kind: String = "ScheduleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScheduleProvider()) { entry in
            if #available(iOS 17.0, *) {
                ScheduleWidgetEntryView(entry: entry)
                    .containerBackground(Color(uiColor: .systemBackground), for: .widget)
            } else {
                ScheduleWidgetEntryView(entry: entry)
                    .background(Color(uiColor: .systemBackground))
            }
        }
        .configurationDisplayName("今日の予定とタスク")
        .description("日付・曜日・当日の予定・未完了タスクを表示します。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
