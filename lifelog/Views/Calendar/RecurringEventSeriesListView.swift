import SwiftUI

/// Series remain reachable even when every occurrence has been skipped or the rule has ended.
struct RecurringEventSeriesListView: View {
    @ObservedObject var store: AppDataStore
    @State private var editingSeries: CalendarEvent?

    private var series: [CalendarEvent] {
        store.calendarEvents.filter { $0.recurrenceRule != nil }
            .sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        List {
            if series.isEmpty {
                Text("登録した繰り返し予定はありません。")
                    .foregroundStyle(.secondary)
            }
            ForEach(series) { event in
                Button {
                    editingSeries = event
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "repeat")
                            .foregroundStyle(CategoryPalette.color(for: event.calendarName))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title)
                                .foregroundStyle(.primary)
                            seriesDateRange(for: event)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("繰り返し予定を管理")
        .sheet(item: $editingSeries) { event in
            NavigationStack {
                CalendarEventEditorView(event: event,
                                        onSave: { store.updateCalendarEvent($0) },
                                        onDelete: { store.deleteCalendarSeries(containing: event) },
                                        exceptions: store.calendarExceptions,
                                        onRestoreException: { store.restoreCalendarException($0) },
                                        onDeleteSeries: { store.deleteCalendarSeries(containing: event) },
                                        canDeleteWeek: { store.canDeleteCalendarWeek(containing: event) },
                                        editStore: store)
            }
        }
    }

    @ViewBuilder
    private func seriesDateRange(for event: CalendarEvent) -> some View {
        HStack(spacing: 4) {
            if let end = event.recurrenceRule?.until, hasEmptyDateRange(event, endingAt: end) {
                Text("終了済み")
                Text(verbatim: "·")
                Text(dateLabel(end, for: event))
            } else {
                Text(dateLabel(event.startDate, for: event))
                Text(verbatim: "–")
                if let end = event.recurrenceRule?.until {
                    Text(dateLabel(end, for: event))
                } else {
                    Text("終了日なし")
                }
            }
        }
    }

    private func dateLabel(_ date: Date, for event: CalendarEvent) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        let zoneIdentifier = event.recurrenceRule?.timeZoneIdentifier
        formatter.timeZone = zoneIdentifier.flatMap { TimeZone(identifier: $0) } ?? .current
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter.string(from: date)
    }

    private func hasEmptyDateRange(_ event: CalendarEvent, endingAt end: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        let zoneIdentifier = event.recurrenceRule?.timeZoneIdentifier
        calendar.timeZone = zoneIdentifier.flatMap { TimeZone(identifier: $0) } ?? .current
        return calendar.startOfDay(for: end) < calendar.startOfDay(for: event.startDate)
    }
}
