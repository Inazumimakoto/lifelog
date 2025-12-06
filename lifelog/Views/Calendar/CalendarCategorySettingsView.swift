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

    var body: some View {
        List {
            Section {
                Text("iPhoneの標準カレンダーの予定をアプリ内に表示します。\n各カレンダーに対応させるカテゴリを選択してください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
            
            ForEach(store.appState.calendarCategoryLinks.sorted(by: { $0.calendarTitle < $1.calendarTitle })) { link in
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
                            Text(link.categoryId ?? "表示しない")
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
                }), noneLabel: "表示しない")
            .onDisappear {
                let categoryName = tempCategory.isEmpty ? nil : tempCategory
                store.updateCalendarLinkCategory(calendarIdentifier: link.calendarIdentifier, categoryName: categoryName)
                let _ = _Concurrency.Task.detached {
                    await resyncExternalEvents()
                }
            }
        }
        .onAppear {
            calendarService.refreshCalendarLinks(store: store)
        }
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
        if let events = try? await calendarService.fetchEventsForCurrentAndNextMonth() {
            let links = store.appState.calendarCategoryLinks
            let linkMap = Dictionary(uniqueKeysWithValues: links.map { ($0.calendarIdentifier, $0) })
            let defaultCategory = CategoryPalette.defaultCategoryName
            let external = events.compactMap { event -> CalendarEvent? in
                let identifier = event.calendar.calendarIdentifier
                if let link = linkMap[identifier] {
                    guard let category = link.categoryId else { return nil }
                    return CalendarEvent(event: event, categoryName: category)
                }
                return CalendarEvent(event: event, categoryName: defaultCategory)
            }
            await MainActor.run {
                store.updateExternalCalendarEvents(external)
                store.updateLastCalendarSync(date: Date())
            }
        }
    }
}
