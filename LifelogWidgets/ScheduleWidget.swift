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

    private var isCompact: Bool {
        family == .systemSmall
    }

    private var eventLimit: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 3
        default: return 5
        }
    }

    private var taskLimit: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 3
        default: return 5
        }
    }

    private var visibleEvents: [ScheduleEventItem] {
        Array(entry.events.prefix(eventLimit))
    }

    private var visibleTasks: [ScheduleTaskItem] {
        Array(entry.tasks.prefix(taskLimit))
    }

    private var hiddenEventCount: Int {
        max(0, entry.events.count - visibleEvents.count)
    }

    private var hiddenTaskCount: Int {
        max(0, entry.tasks.count - visibleTasks.count)
    }

    private var hasContent: Bool {
        visibleEvents.isEmpty == false || visibleTasks.isEmpty == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 6) {
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
        .padding(family == .systemSmall ? 8 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        Text(ScheduleWidgetFormatter.headerDate.string(from: entry.date))
            .font(.system(size: family == .systemSmall ? 15 : 17, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
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
                .padding(.top, isCompact ? 4 : 5)

            if isCompact {
                Text(eventTimeLabel(event))
                    .font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(event.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 8, weight: .semibold))
                        Text(eventTimeLabel(event))
                            .font(.system(size: 10, weight: .regular, design: .rounded).monospacedDigit())
                    }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, isCompact ? 2 : 3)
    }

    private func taskRow(_ task: ScheduleTaskItem) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "circle")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(priorityColor(for: task.priority))
            Text(task.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.vertical, isCompact ? 2 : 3)
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 13)
    }

    private var overflowSummary: some View {
        HStack(spacing: 8) {
            if hiddenEventCount > 0 {
                summaryLine("+予定\(hiddenEventCount)")
            }
            if hiddenTaskCount > 0 {
                summaryLine("+タスク\(hiddenTaskCount)")
            }
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
            .font(.system(size: 11, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func summaryLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: isCompact ? 10 : 11, weight: .semibold, design: .rounded))
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
