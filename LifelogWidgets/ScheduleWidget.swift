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
    let categoryName: String
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
    private static let externalCalendarEventsDefaultsKey = "ExternalCalendarEvents_Storage_V1"

    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(
            date: Date(),
            events: [
                ScheduleEventItem(
                    id: UUID(),
                    title: "10:00 チームMTG",
                    startDate: Date(),
                    endDate: Date().addingTimeInterval(60 * 60),
                    isAllDay: false,
                    categoryName: "仕事"
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
        let internalEvents = fetchInternalEvents(on: date)
        let externalEvents = fetchExternalEvents(on: date)
        let merged = (internalEvents + externalEvents).reduce(into: [UUID: ScheduleEventItem]()) { result, item in
            if let existing = result[item.id] {
                result[item.id] = existing.startDate <= item.startDate ? existing : item
            } else {
                result[item.id] = item
            }
        }
        return merged.values.sorted {
            if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
            return $0.title < $1.title
        }
    }

    @MainActor
    private func fetchInternalEvents(on date: Date) -> [ScheduleEventItem] {
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
                    isAllDay: $0.isAllDay,
                    categoryName: $0.calendarName
                )
            }
        } catch {
            return []
        }
    }

    private func fetchExternalEvents(on date: Date) -> [ScheduleEventItem] {
        let defaults = UserDefaults(suiteName: PersistenceController.appGroupIdentifier) ?? UserDefaults.standard
        guard let data = defaults.data(forKey: Self.externalCalendarEventsDefaultsKey) else { return [] }
        guard let externalEvents = try? JSONDecoder().decode([CalendarEvent].self, from: data) else { return [] }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        return externalEvents
            .filter { $0.startDate < dayEnd && $0.endDate > dayStart }
            .sorted {
                if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
                return $0.title < $1.title
            }
            .map {
                ScheduleEventItem(
                    id: $0.id,
                    title: $0.title,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    isAllDay: $0.isAllDay,
                    categoryName: $0.calendarName
                )
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
    static let headerDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "MM/dd (E)"
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private enum ScheduleCategoryPalette {
    static let storageKey = "CategoryPalette_Categories_V3"
    static let fallbackMap: [String: String] = [
        "仕事": "orange",
        "趣味": "green",
        "旅行": "blue"
    ]

    static func color(for categoryName: String) -> Color {
        let normalizedName = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let map = currentMap()
        guard let token = map[normalizedName] else {
            return .accentColor
        }
        return parseColorToken(token) ?? .accentColor
    }

    private static func currentMap() -> [String: String] {
        let defaults = UserDefaults(suiteName: PersistenceController.appGroupIdentifier) ?? UserDefaults.standard
        guard let data = defaults.data(forKey: storageKey) else {
            return fallbackMap
        }
        guard let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return fallbackMap
        }
        return decoded
    }

    private static func parseColorToken(_ token: String) -> Color? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if let uiColor = UIColor(hex: trimmed) {
            return Color(uiColor: uiColor)
        }

        switch trimmed.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "mint": return .mint
        case "teal": return .teal
        case "cyan": return .cyan
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "brown": return .brown
        case "gray", "grey": return .gray
        default: return nil
        }
    }
}

private extension UIColor {
    convenience init?(hex: String) {
        var normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("#") {
            normalized.removeFirst()
        }

        guard normalized.count == 6, let raw = UInt64(normalized, radix: 16) else {
            return nil
        }

        let red = CGFloat((raw & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((raw & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(raw & 0x0000FF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}

struct ScheduleWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleProvider.Entry

    private var maxVisibleRows: Int {
        switch family {
        case .systemSmall, .systemMedium:
            return 5
        default:
            return 8
        }
    }

    private var preferredEventRows: Int {
        switch family {
        case .systemSmall, .systemMedium:
            return 3
        default:
            return 5
        }
    }

    private var preferredTaskRows: Int {
        switch family {
        case .systemSmall, .systemMedium:
            return 2
        default:
            return 5
        }
    }

    private func allocatedCounts(maxRows: Int) -> (events: Int, tasks: Int) {
        var eventCount = min(entry.events.count, preferredEventRows, maxRows)
        var taskCount = min(entry.tasks.count, preferredTaskRows, maxRows - eventCount)

        var remaining = maxRows - eventCount - taskCount
        if remaining > 0 {
            let eventRemainder = max(0, entry.events.count - eventCount)
            let eventExtra = min(remaining, eventRemainder)
            eventCount += eventExtra
            remaining -= eventExtra
        }
        if remaining > 0 {
            let taskRemainder = max(0, entry.tasks.count - taskCount)
            let taskExtra = min(remaining, taskRemainder)
            taskCount += taskExtra
        }

        if entry.events.isEmpty == false && entry.tasks.isEmpty == false {
            if eventCount == 0 && taskCount > 0 {
                eventCount = 1
                taskCount = max(0, taskCount - 1)
            } else if taskCount == 0 && eventCount > 0 {
                taskCount = 1
                eventCount = max(0, eventCount - 1)
            }
        }

        return (events: eventCount, tasks: taskCount)
    }

    private var visibleCounts: (events: Int, tasks: Int) {
        let full = allocatedCounts(maxRows: maxVisibleRows)
        let hiddenWhenFull = max(0, entry.events.count - full.events) + max(0, entry.tasks.count - full.tasks)

        if hiddenWhenFull > 0, family != .systemLarge {
            return allocatedCounts(maxRows: max(0, maxVisibleRows - 1))
        }
        return full
    }

    private var visibleEvents: [ScheduleEventItem] {
        Array(entry.events.prefix(visibleCounts.events))
    }

    private var visibleTasks: [ScheduleTaskItem] {
        Array(entry.tasks.prefix(visibleCounts.tasks))
    }

    private var hiddenEventCount: Int {
        max(0, entry.events.count - visibleEvents.count)
    }

    private var hiddenTaskCount: Int {
        max(0, entry.tasks.count - visibleTasks.count)
    }

    private var overflowSummaryText: String? {
        var parts: [String] = []
        if hiddenEventCount > 0 {
            parts.append("+予定\(hiddenEventCount)件")
        }
        if hiddenTaskCount > 0 {
            parts.append("+タスク\(hiddenTaskCount)件")
        }
        guard parts.isEmpty == false else { return nil }
        return parts.joined(separator: " ")
    }

    private var hasContent: Bool {
        visibleEvents.isEmpty == false || visibleTasks.isEmpty == false
    }

    var body: some View {
        if family == .accessoryInline {
            inlineLockScreenText
        } else {
            VStack(alignment: .leading, spacing: 4) {
                header
                if hasContent {
                    rows
                    overflowSummary
                } else {
                    emptyLine("予定・タスクはありません")
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(.vertical, family == .systemSmall ? 7 : 8)
            .padding(.horizontal, family == .systemSmall ? 8 : 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var inlineLockScreenText: some View {
        let taskPrefix = inlinePendingTaskPrefix

        if let firstEvent = entry.events.first {
            let timeText: String = firstEvent.isAllDay ? "終日" : ScheduleWidgetFormatter.time.string(from: firstEvent.startDate)
            return (
                Text("\(taskPrefix)\(timeText) \(firstEvent.title)")
            )
            .lineLimit(1)
        } else {
            return (
                Text("\(taskPrefix)予定なし")
            )
            .lineLimit(1)
        }
    }

    private var inlinePendingTaskPrefix: String {
        let count = entry.tasks.count
        guard count > 0 else { return "" }
        let compactCount = count > 9 ? "9+" : "\(count)"
        return "□\(compactCount) "
    }

    private var header: some View {
        Text(ScheduleWidgetFormatter.headerDate.string(from: entry.date))
            .font(.system(size: family == .systemSmall ? 16 : (family == .systemMedium ? 16 : 17), weight: .bold, design: .rounded))
            .lineLimit(1)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if visibleEvents.isEmpty == false {
                ForEach(Array(visibleEvents.enumerated()), id: \.element.id) { index, event in
                    eventRow(event)
                    if index < visibleEvents.count - 1 || visibleTasks.isEmpty == false {
                        rowDivider
                    }
                }
            }
            if visibleTasks.isEmpty == false {
                ForEach(Array(visibleTasks.enumerated()), id: \.element.id) { index, task in
                    taskRow(task)
                    if index < visibleTasks.count - 1 {
                        rowDivider
                    }
                }
            }
        }
    }

    private func eventRow(_ event: ScheduleEventItem) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(ScheduleCategoryPalette.color(for: event.categoryName))
                .frame(width: 6, height: 6)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.system(size: family == .systemSmall ? 12 : (family == .systemMedium ? 12 : 13), weight: .semibold, design: .rounded))
                    .lineLimit(1)
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 8, weight: .semibold))
                    Text(eventTimeLabel(event))
                        .font(.system(size: family == .systemSmall ? 10 : (family == .systemMedium ? 10 : 11), weight: .regular, design: .rounded).monospacedDigit())
                }
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, family == .systemSmall ? 1 : 2)
    }

    private func taskRow(_ task: ScheduleTaskItem) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "circle")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(priorityColor(for: task.priority))
            Text(task.title)
                .font(.system(size: family == .systemSmall ? 12 : (family == .systemMedium ? 12 : 13), weight: .semibold, design: .rounded))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, family == .systemSmall ? 1 : 2)
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 12)
    }

    @ViewBuilder
    private var overflowSummary: some View {
        if let summary = overflowSummaryText {
            summaryLine(summary)
        }
    }

    private func eventTimeLabel(_ event: ScheduleEventItem) -> String {
        if event.isAllDay {
            return "終日"
        }
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
            .font(.system(size: family == .systemSmall ? 11.5 : (family == .systemMedium ? 11.5 : 13), weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func summaryLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: family == .systemSmall ? 11 : (family == .systemMedium ? 11 : 12), weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryInline])
        .contentMarginsDisabled()
    }
}
