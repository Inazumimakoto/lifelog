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

enum WidgetPremiumAccess {
    static let storageKey = "monetization.isPremiumUnlockedForSharedSurfaces"

    static var isUnlocked: Bool {
        let defaults = UserDefaults(suiteName: PersistenceController.appGroupIdentifier) ?? .standard
        return defaults.object(forKey: storageKey) as? Bool ?? false
    }
}

struct PremiumWidgetLockView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryInline {
            Text("Premiumで解放")
                .lineLimit(1)
        } else {
            VStack(spacing: 7) {
                Image(systemName: "lock.fill")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(.yellow)
                Text("プレミアムで解放")
                    .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("アプリでプランを確認")
                    .font(.system(size: messageSize, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var iconSize: CGFloat {
        family == .systemSmall ? 20 : 24
    }

    private var titleSize: CGFloat {
        family == .systemSmall ? 12 : 14
    }

    private var messageSize: CGFloat {
        family == .systemSmall ? 10 : 11
    }
}

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
    let nextInlineEvent: ScheduleEventItem?
    let isPremiumUnlocked: Bool
    var month: ScheduleMonth? = nil
}

struct ScheduleProvider: TimelineProvider {

    func placeholder(in context: Context) -> ScheduleEntry {
        let sampleEvent = ScheduleEventItem(
            id: UUID(),
            title: String(localized: "10:00 チームMTG"),
            startDate: Date(),
            endDate: Date().addingTimeInterval(60 * 60),
            isAllDay: false,
            categoryName: String(localized: "仕事")
        )

        return ScheduleEntry(
            date: Date(),
            events: [sampleEvent],
            tasks: [
                ScheduleTaskItem(id: UUID(), title: String(localized: "週次レポート提出"), priority: .high),
                ScheduleTaskItem(id: UUID(), title: String(localized: "買い物メモ整理"), priority: .medium)
            ],
            nextInlineEvent: sampleEvent,
            isPremiumUnlocked: true,
            month: ScheduleMonth(
                containing: sampleEvent.startDate,
                eventIntervals: [DateInterval(start: sampleEvent.startDate, end: sampleEvent.endDate)],
                calendar: CalendarWeekStart.sunday.calendar
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        let includeMonth = context.family == .systemMedium
        _Concurrency.Task { @MainActor in
            completion(loadEntry(for: Date(), includeMonth: includeMonth))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let includeMonth = context.family == .systemMedium
        _Concurrency.Task { @MainActor in
            let now = Date()
            let entry = loadEntry(for: now, includeMonth: includeMonth)
            let regularRefresh = now.addingTimeInterval(60 * 15)
            let nextMidnight = Calendar.current.dateInterval(of: .day, for: now)?.end ?? regularRefresh
            let nextRefresh = min(regularRefresh, nextMidnight)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    @MainActor
    private func loadEntry(for date: Date, includeMonth: Bool) -> ScheduleEntry {
        guard WidgetPremiumAccess.isUnlocked else {
            return ScheduleEntry(
                date: date,
                events: [],
                tasks: [],
                nextInlineEvent: nil,
                isPremiumUnlocked: false
            )
        }

        let todayEvents = fetchEvents(on: date)
        return ScheduleEntry(
            date: date,
            events: todayEvents,
            tasks: fetchTasks(on: date),
            nextInlineEvent: fetchNextInlineEvent(from: date),
            isPremiumUnlocked: true,
            month: includeMonth ? fetchMonth(containing: date) : nil
        )
    }

    @MainActor
    private func fetchMonth(containing date: Date) -> ScheduleMonth {
        let calendar = CalendarWeekStart.current.calendar
        guard let interval = calendar.dateInterval(of: .month, for: date) else {
            return ScheduleMonth(containing: date, calendar: calendar)
        }
        let intervals = fetchEvents(from: interval.start, to: interval.end).compactMap { event in
            guard event.endDate > event.startDate else { return nil as DateInterval? }
            return DateInterval(start: event.startDate, end: event.endDate)
        }
        return ScheduleMonth(containing: date, eventIntervals: intervals, calendar: calendar)
    }

    @MainActor
    private func fetchEvents(on date: Date) -> [ScheduleEventItem] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return fetchEvents(from: dayStart, to: dayEnd)
    }

    @MainActor
    private func fetchEvents(from rangeStart: Date, to rangeEnd: Date) -> [ScheduleEventItem] {
        // Resolve the same masters and exceptions used by Today and Calendar.
        let externalEvents = fetchExternalEvents(from: rangeStart, to: rangeEnd)
        let merged: [CalendarEvent]
        do {
            merged = try CalendarEventStorageQuery.events(
                in: PersistenceController.shared.container.mainContext,
                from: rangeStart,
                to: rangeEnd,
                externalEvents: externalEvents
            )
        } catch {
            merged = EventQuerying.mergedDedupedSorted(internalEvents: [], externalEvents: externalEvents)
        }
        return merged.map {
            ScheduleEventItem(
                id: $0.id,
                title: $0.title,
                startDate: $0.displayStartDate(),
                endDate: $0.displayEndDate(),
                isAllDay: $0.isAllDay,
                categoryName: $0.calendarName
            )
        }
    }

    private func fetchExternalEvents(from rangeStart: Date, to rangeEnd: Date) -> [CalendarEvent] {
        // 外部イベントの読み出しとデコード・期間フィルタは共有 EventQuerying に集約。
        let defaults = UserDefaults(suiteName: PersistenceController.appGroupIdentifier)
        let events = EventQuerying.loadExternalEvents(from: defaults)
        return EventQuerying.overlapping(events, rangeStart: rangeStart, rangeEndExclusive: rangeEnd)
    }

    @MainActor
    private func fetchNextInlineEvent(from date: Date) -> ScheduleEventItem? {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: date)
        guard let searchEnd = calendar.date(byAdding: .day, value: 2, to: todayStart) else { return nil }

        return fetchEvents(from: todayStart, to: searchEnd)
            .filter { $0.endDate > date }
            .sorted { lhs, rhs in
                let lhsAnchor = max(lhs.startDate.timeIntervalSince1970, date.timeIntervalSince1970)
                let rhsAnchor = max(rhs.startDate.timeIntervalSince1970, date.timeIntervalSince1970)
                if lhsAnchor != rhsAnchor { return lhsAnchor < rhsAnchor }
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.title < rhs.title
            }
            .first
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
        TaskPresentation.isScheduled(task, on: date)
    }

    private func sortTasks(_ lhs: SDTask, _ rhs: SDTask) -> Bool {
        TaskPresentation.orderedBefore(lhs, rhs, preferring: .start)
    }
}

private enum ScheduleWidgetFormatter {
    static let headerDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MdE")
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Hm")
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
        return AppColorPalette.color(for: token)
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


}

// UIColor(hex:) は共有ファイル ColorHex.swift へ移動した。

struct ScheduleWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleProvider.Entry
    var rowLimit: Int? = nil

    private var maxVisibleRows: Int {
        if let rowLimit { return rowLimit }
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
            parts.append(String(localized: "+予定\(hiddenEventCount)件"))
        }
        if hiddenTaskCount > 0 {
            parts.append(String(localized: "+タスク\(hiddenTaskCount)件"))
        }
        guard parts.isEmpty == false else { return nil }
        return parts.joined(separator: " ")
    }

    private var hasContent: Bool {
        visibleEvents.isEmpty == false || visibleTasks.isEmpty == false
    }

    var body: some View {
        if entry.isPremiumUnlocked == false {
            PremiumWidgetLockView()
        } else if family == .accessoryInline {
            inlineLockScreenText
        } else if family == .systemMedium, rowLimit == nil {
            // docs/ui-guidelines.md: 予定ウィジェット（中サイズ）
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    ViewThatFits(in: .vertical) {
                        ForEach([5, 4, 3, 2], id: \.self) { limit in
                            ScheduleWidgetEntryView(entry: entry, rowLimit: limit)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider()

                ScheduleMonthCalendarView(
                    month: entry.month ?? ScheduleMonth(containing: entry.date, calendar: CalendarWeekStart.current.calendar),
                    today: entry.date
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 9)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                header
                if hasContent {
                    rows
                    overflowSummary
                } else {
                    emptyLine(String(localized: "予定・タスクはありません"))
                }
                if rowLimit == nil {
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(.primary)
            .padding(.vertical, rowLimit != nil ? 0 : (family == .systemSmall ? 7 : 8))
            .padding(.horizontal, rowLimit != nil ? 0 : (family == .systemSmall ? 8 : 9))
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var inlineLockScreenText: some View {
        let taskPrefix = inlinePendingTaskPrefix

        if let nextEvent = entry.nextInlineEvent {
            let dayPrefix = inlineDayPrefix(for: nextEvent.startDate)
            let timeText: String = nextEvent.isAllDay ? String(localized: "終日") : ScheduleWidgetFormatter.time.string(from: nextEvent.startDate)
            return (
                Text("\(taskPrefix)\(dayPrefix)\(timeText) \(nextEvent.title)")
            )
            .lineLimit(1)
        } else {
            return (
                Text("\(taskPrefix)\(String(localized: "予定なし"))")
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

    private func inlineDayPrefix(for eventDate: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(eventDate, inSameDayAs: entry.date) {
            return ""
        }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: entry.date),
           calendar.isDate(eventDate, inSameDayAs: tomorrow) {
            return String(localized: "明日 ")
        }

        return ""
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
            return String(localized: "終日")
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
        .description("今日の予定と未完了タスクを表示。中サイズでは月間カレンダーも確認できます。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryInline])
        .contentMarginsDisabled()
    }
}
