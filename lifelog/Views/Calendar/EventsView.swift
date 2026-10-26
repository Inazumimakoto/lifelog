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
                if viewModel.hasRecurringEvents {
                    Text(viewModel.recurrenceRangeDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    NavigationLink("繰り返し予定を管理") {
                        RecurringEventSeriesListView(store: store)
                    }
                }
            }
            ForEach(EventsViewModel.EventSection.allCases) { section in
                let events = viewModel.events(for: section)
                if !events.isEmpty || (viewModel.hasRecurringEvents && section != .today) {
                    Section(section.displayName) {
                        ForEach(events) { event in
                            eventRow(event)
                        }
                        if viewModel.hasRecurringEvents && section == .upcoming {
                            Button("さらに先の繰り返し予定を表示") { viewModel.loadMoreUpcomingEvents() }
                        } else if viewModel.hasRecurringEvents && section == .past {
                            Button("さらに前の繰り返し予定を表示") { viewModel.loadMorePastEvents() }
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
                },
                                        onSkipWeek: { store.skipCalendarWeek(containing: event) },
                                        onEndSeries: { store.endCalendarSeries(startingAt: event) },
                                        exceptions: store.calendarExceptions,
                                        onRestoreException: { store.restoreCalendarException($0) },
                                        onDeleteSeries: { store.deleteCalendarSeries(containing: event) },
                                        canDeleteWeek: { store.canDeleteCalendarWeek(containing: event) },
                                        editStore: store)
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
                if event.detail.isEmpty == false {
                    Text(event.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let url = event.linkURL {
                    ScheduleLinkButton(url: url)
                }
                HStack(spacing: 4) {
                    Text(CategoryPalette.displayName(for: event.calendarName))
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
            let startDay = calendar.startOfDay(for: event.displayStartDate(calendar: calendar))
            let end = event.displayEndDate(calendar: calendar)
            let endDay = calendar.startOfDay(for: calendar.date(byAdding: .second, value: -1, to: end) ?? end)
            if startDay == endDay {
                return String(localized: "終日")
            } else {
                return String(localized: "終日 (\(startDay.jaMonthDayString) - \(endDay.jaMonthDayString))")
            }
        }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MdHm")
        return "\(formatter.string(from: event.startDate)) - \(formatter.string(from: event.endDate))"
    }
}
