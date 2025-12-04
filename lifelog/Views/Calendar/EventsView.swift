//
//  EventsView.swift
//  lifelog
//
//  Created by Codex on 2025/12/05.
//

import SwiftUI

struct EventsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: EventsViewModel
    @State private var showAddEditor = false
    @State private var editingEvent: CalendarEvent?

    private let store: AppDataStore

    init(store: AppDataStore) {
        self.store = store
        _viewModel = StateObject(wrappedValue: EventsViewModel(store: store))
    }

    var body: some View {
        List {
            Section {
                Text("予定はカレンダーとホームで共有されます。外部カレンダーの予定は編集できません。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(EventsViewModel.EventSection.allCases) { section in
                let events = viewModel.events(for: section)
                if events.isEmpty == false {
                    Section(section.rawValue) {
                        ForEach(events) { event in
                            eventRow(event)
                        }
                    }
                }
            }
            if viewModel.allEvents.isEmpty {
                VStack(spacing: 12) {
                    Text("予定はまだありません")
                        .font(.headline)
                    Text("右上の＋ボタンから自由に追加してください。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("予定")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("閉じる") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddEditor) {
            NavigationStack {
                CalendarEventEditorView(onSave: { event in
                    viewModel.add(event)
                })
            }
        }
        .sheet(item: $editingEvent) { event in
            NavigationStack {
                CalendarEventEditorView(event: event,
                                        onSave: { updated in
                    viewModel.update(updated)
                },
                                        onDelete: {
                    viewModel.delete(event)
                })
            }
        }
    }

    @ViewBuilder
    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(CategoryPalette.color(for: event.calendarName))
                .frame(width: 10, height: 10)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.body.weight(.semibold))
                Label(eventTimeLabel(event), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(event.calendarName)
                        .font(.caption2)
                        .foregroundStyle(CategoryPalette.color(for: event.calendarName))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(CategoryPalette.color(for: event.calendarName).opacity(0.15), in: Capsule())
                    if viewModel.isExternalEvent(event) {
                        Text("外部")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }
            }
            Spacer()

            if !viewModel.isExternalEvent(event) {
                Button {
                    editingEvent = event
                } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
    }

    private func eventTimeLabel(_ event: CalendarEvent) -> String {
        if event.isAllDay {
            let calendar = Calendar.current
            let startDay = calendar.startOfDay(for: event.startDate)
            let endDay = calendar.startOfDay(for: calendar.date(byAdding: .second, value: -1, to: event.endDate) ?? event.endDate)
            if startDay == endDay {
                return "終日"
            } else {
                return "終日 (\(event.startDate.jaMonthDayString) - \(endDay.jaMonthDayString))"
            }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d H:mm"
        return "\(formatter.string(from: event.startDate)) - \(formatter.string(from: event.endDate))"
    }
}
