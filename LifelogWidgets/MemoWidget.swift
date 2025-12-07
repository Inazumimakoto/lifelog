//
//  MemoWidget.swift
//  LifelogWidgets
//
//  Created for Widget Implementation
//

import WidgetKit
import SwiftUI
import SwiftData

struct MemoProvider: TimelineProvider {
    func placeholder(in context: Context) -> MemoEntry {
        MemoEntry(date: Date(), text: "メモの内容がここに表示されます。")
    }

    func getSnapshot(in context: Context, completion: @escaping (MemoEntry) -> ()) {
        _Concurrency.Task { @MainActor in
            let entry = MemoEntry(date: Date(), text: fetchMemo())
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MemoEntry>) -> ()) {
        _Concurrency.Task { @MainActor in
            let entry = MemoEntry(date: Date(), text: fetchMemo())
            
            // Refresh every 15 mins or on app open (OS managed)
            let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdateDate))
            completion(timeline)
        }
    }

    @MainActor
    private func fetchMemo() -> String {
        do {
            let descriptor = FetchDescriptor<SDMemoPad>()
            // Use the shared container which has the proper full schema
            let memos = try PersistenceController.shared.container.mainContext.fetch(descriptor)
            return memos.first?.text ?? "メモはありません"
        } catch {
            return "読み込みエラー"
        }
    }
}

struct MemoEntry: TimelineEntry {
    let date: Date
    let text: String
}

struct MemoWidgetEntryView : View {
    var entry: MemoProvider.Entry

    var body: some View {
        VStack(alignment: .leading) {
            Text("Memo")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
            
            Text(entry.text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.top, 4)
            
            Spacer()
        }
        .padding()
    }
}

struct MemoWidget: Widget {
    let kind: String = "MemoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MemoProvider()) { entry in
            if #available(iOS 17.0, *) {
                MemoWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                MemoWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("メモ")
        .description("メモパッドの内容を表示します。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
