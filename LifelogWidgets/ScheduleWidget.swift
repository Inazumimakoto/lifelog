//
//  ScheduleWidget.swift
//  LifelogWidgets
//
//  Created for Widget Implementation
//

import WidgetKit
import SwiftUI
import SwiftData

struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(date: Date(), tasks: [], events: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> ()) {
        _Concurrency.Task { @MainActor in
            let entry = ScheduleEntry(date: Date(), tasks: fetchTasks(), events: [])
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> ()) {
        _Concurrency.Task { @MainActor in
            // Fetch fresh data
            let tasks = fetchTasks()
            let events = fetchTodayEvents()

            let currentDate = Date()
            let entry = ScheduleEntry(date: currentDate, tasks: tasks, events: events)

            // Refresh at the start of the next hour or in 15 mins
            let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdateDate))
            completion(timeline)
        }
    }
    
    @MainActor
    private func fetchTasks() -> [String] {
        do {
            // Use shared container
            let descriptor = FetchDescriptor<SDTask>(
                predicate: #Predicate<SDTask> { !$0.isCompleted },
                sortBy: [SortDescriptor(\.priority, order: .reverse)]
            )
            // Limit to top 3 for widget
            var tasks = try PersistenceController.shared.container.mainContext.fetch(descriptor)
            if tasks.count > 3 {
                tasks = Array(tasks.prefix(3))
            }
            return tasks.map { $0.title }
        } catch {
            // Error during fetch - return empty
            return []
        }
    }
    
    @MainActor
    private func fetchTodayEvents() -> [String] {
        do {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }
            
            let descriptor = FetchDescriptor<SDCalendarEvent>(
                predicate: #Predicate<SDCalendarEvent> { $0.startDate >= today && $0.startDate < tomorrow },
                sortBy: [SortDescriptor(\.startDate)]
            )
            let events = try PersistenceController.shared.container.mainContext.fetch(descriptor)
            return events.prefix(3).map { $0.title }
        } catch {
            return []
        }
    }
}

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let tasks: [String]
    let events: [String]
}

struct ScheduleWidgetEntryView : View {
    var entry: ScheduleProvider.Entry
    
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d(E)"
        return formatter.string(from: entry.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Date Display
            Text(dateString)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.bottom, 12)
            
            Spacer()
            
            // Content: Tasks
            if entry.tasks.isEmpty && entry.events.isEmpty {
                Text("予定なし")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.events, id: \.self) { event in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 6, height: 6)
                            Text(event)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                    }
                    ForEach(entry.tasks, id: \.self) { task in
                        HStack(spacing: 6) {
                            Image(systemName: "circle")
                                .font(.system(size: 10, weight: .light))
                                .foregroundColor(.white.opacity(0.6))
                            Text(task)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .background(Color.black)
    }
}

// End of file

struct ScheduleWidget: Widget {
    let kind: String = "ScheduleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScheduleProvider()) { entry in
            if #available(iOS 17.0, *) {
                ScheduleWidgetEntryView(entry: entry)
                    .containerBackground(Color.black, for: .widget)
            } else {
                ScheduleWidgetEntryView(entry: entry)
                    .background(Color.black)
            }
        }
        .configurationDisplayName("予定カレンダー")
        .description("今日の予定とタスクを表示します。")
        .supportedFamilies([.systemSmall])
    }
}
