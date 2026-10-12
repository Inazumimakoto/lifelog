//
//  CalendarCategorySettingsView.swift
//  lifelog
//
//  Created by Codex on 2025/11/22.
//

import SwiftUI
import EventKit

struct CalendarCategorySettingsView: View {
    @ObservedObject var store: AppDataStore
    private let calendarService = CalendarEventService()

    @State private var selection: CalendarCategoryLink?
    @State private var tempCategory: String = ""
    @State private var links: [CalendarCategoryLink] = []

    var body: some View {
        List {
            Section {
                Text("iPhoneの標準カレンダーの予定をアプリ内に表示します。\n各カレンダーに対応させるカテゴリを選択してください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
            
            ForEach(links.sorted(by: { $0.calendarTitle < $1.calendarTitle })) { link in
                Button {
                    selection = link
                    tempCategory = link.categoryId ?? ""
                } label: {
                    HStack {
                        Circle()
                            .fill(displayColor(for: link))
                            .frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.calendarTitle)
                            Text(link.categoryId.map { CategoryPalette.displayName(for: $0) } ?? String(localized: "表示しない"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("カレンダーとカテゴリ")
        .sheet(item: $selection, onDismiss: { selection = nil }) { link in
            CategorySelectionView(selectedCategory: Binding(
                get: { tempCategory },
                set: { newValue in
                    tempCategory = newValue
                }), noneLabel: String(localized: "表示しない"))
            .onDisappear {
                let categoryName = tempCategory.isEmpty ? nil : tempCategory
                store.updateCalendarLinkCategory(calendarIdentifier: link.calendarIdentifier, categoryName: categoryName)
                // ローカルのlinksも更新
                if let index = links.firstIndex(where: { $0.calendarIdentifier == link.calendarIdentifier }) {
                    links[index].categoryId = categoryName
                }
                let _ = _Concurrency.Task.detached {
                    await resyncExternalEvents()
                }
            }
        }
        .onAppear {
            loadLinks()
        }
    }
    
    private func loadLinks() {
        // 一度だけロード（linksが空の場合のみ）
        guard links.isEmpty else { return }
        calendarService.refreshCalendarLinks(store: store)
        links = store.appState.calendarCategoryLinks
    }

    private func displayColor(for link: CalendarCategoryLink) -> Color {
        if let cat = link.categoryId, cat.isEmpty == false {
            return CategoryPalette.color(for: cat)
        }
        if let hex = link.colorHex, let color = Color(hex: hex) {
            return color
        }
        return .secondary
    }

    private func resyncExternalEvents() async {
        let granted = await calendarService.requestAccessIfNeeded()
        guard granted else { return }
        calendarService.refreshCalendarLinks(store: store)
        let range = store.currentExternalCalendarRange() ?? ExternalCalendarSyncPolicy.desiredRange(for: Date())
        if let events = try? await calendarService.fetchEvents(from: range.start, to: range.end) {
            let external = ExternalCalendarEventMapper(links: store.appState.calendarCategoryLinks).map(events)
            await MainActor.run {
                store.updateExternalCalendarEvents(external, range: range)
                store.updateLastCalendarSync(date: Date())
            }
        }
    }

}
