//
//  AnniversaryWidget.swift
//  LifelogWidgets
//
//  Created for Widget Implementation
//

import WidgetKit
import SwiftUI
import SwiftData

struct AnniversaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> AnniversaryEntry {
        AnniversaryEntry(date: Date(), anniversary: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (AnniversaryEntry) -> ()) {
        _Concurrency.Task { @MainActor in
            let entry = AnniversaryEntry(date: Date(), anniversary: fetchTopAnniversary())
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AnniversaryEntry>) -> ()) {
        _Concurrency.Task { @MainActor in
            let entry = AnniversaryEntry(date: Date(), anniversary: fetchTopAnniversary())
            
            // Refresh daily
            let nextUpdateDate = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdateDate))
            completion(timeline)
        }
    }

    @MainActor
    private func fetchTopAnniversary() -> AnniversaryWidgetModel? {
        do {
            let context = PersistenceController.shared.container.mainContext
            let descriptor = FetchDescriptor<SDAnniversary>(
                sortBy: [SortDescriptor(\.orderIndex)]
            )
            let anniversaries = try context.fetch(descriptor)
            
            guard let first = anniversaries.first else { return nil }
            
            return AnniversaryWidgetModel(
                title: first.title,
                date: first.targetDate,
                type: first.type.rawValue
            )
        } catch {
            return nil
        }
    }
}

struct AnniversaryWidgetModel {
    let title: String
    let date: Date
    let type: String
}

struct AnniversaryEntry: TimelineEntry {
    let date: Date
    let anniversary: AnniversaryWidgetModel?
}

struct AnniversaryWidgetEntryView : View {
    var entry: AnniversaryProvider.Entry

    var body: some View {
        VStack {
            if let anniversary = entry.anniversary {
                VStack(spacing: 4) {
                    Text(anniversary.title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    Spacer()
                    
                    if anniversary.type == "countdown" {
                        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: anniversary.date)).day ?? 0
                        Text("あと")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(max(0, days))")
                            .font(.system(size: 36, weight: .bold))
                            .contentTransition(.numericText())
                        Text("日")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        // Since
                         let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: anniversary.date), to: Calendar.current.startOfDay(for: Date())).day ?? 0
                        Text("から")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(days)")
                            .font(.system(size: 36, weight: .bold))
                        Text("日経過")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(anniversary.date.formatted(date: .numeric, time: .omitted))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("記念日がありません")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

struct AnniversaryWidget: Widget {
    let kind: String = "AnniversaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AnniversaryProvider()) { entry in
             if #available(iOS 17.0, *) {
                AnniversaryWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                AnniversaryWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("記念日")
        .description("記念日やカウントダウンを表示します。")
        .supportedFamilies([.systemSmall])
    }
}
