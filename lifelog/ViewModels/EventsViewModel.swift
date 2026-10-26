//
//  EventsViewModel.swift
//  lifelog
//
//  Created by Codex on 2025/12/05.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class EventsViewModel: ObservableObject {

    enum EventSection: String, CaseIterable, Identifiable {
        case today = "今日の予定"
        case upcoming = "今後の予定"
        case past = "過去の予定"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .today: return String(localized: "今日の予定")
            case .upcoming: return String(localized: "今後の予定")
            case .past: return String(localized: "過去の予定")
            }
        }
    }

    @Published private(set) var events: [CalendarEvent] = [] {
        didSet { resolvedEventsCache = nil }
    }
    @Published private(set) var externalEvents: [CalendarEvent] = [] {
        didSet { resolvedEventsCache = nil }
    }
    @Published private(set) var calendarExceptions: [CalendarEventException] = [] {
        didSet { resolvedEventsCache = nil }
    }
    @Published private(set) var pastRecurrenceYears = 1 {
        didSet { resolvedEventsCache = nil }
    }
    @Published private(set) var upcomingRecurrenceYears = 1 {
        didSet { resolvedEventsCache = nil }
    }

    private let store: AppDataStore
    private let referenceDate: Date?
    private var effectiveReferenceDate: Date { referenceDate ?? Date() }
    private var cancellables = Set<AnyCancellable>()
    private struct ResolvedEventsCache {
        let calendar: Calendar
        let range: DateInterval
        let events: [CalendarEvent]
    }
    // The three sections and empty state share one expansion. This cache is
    // deliberately private, so filling it during a render publishes no state.
    private var resolvedEventsCache: ResolvedEventsCache?

    // Match AppDataStore and TodayViewModel's iOS 26.1 isolated-deinit workaround.
    nonisolated deinit {}

    init(store: AppDataStore, referenceDate: Date? = nil) {
        self.store = store
        self.referenceDate = referenceDate
        self.events = store.calendarEvents
        self.externalEvents = store.externalCalendarEvents
        self.calendarExceptions = store.calendarExceptions
        bind()
    }

    private func bind() {
        store.$calendarEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] events in
                guard let self, self.events != events else { return }
                self.events = events
            }
            .store(in: &cancellables)

        store.$externalCalendarEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] events in
                guard let self, self.externalEvents != events else { return }
                self.externalEvents = events
            }
            .store(in: &cancellables)

        store.$calendarExceptions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] exceptions in
                guard let self, self.calendarExceptions != exceptions else { return }
                self.calendarExceptions = exceptions
            }
            .store(in: &cancellables)
    }

    var hasRecurringEvents: Bool {
        events.contains { $0.recurrenceRule != nil }
    }

    private var recurrenceRange: DateInterval {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: effectiveReferenceDate)
        let start = calendar.date(byAdding: .year, value: -pastRecurrenceYears, to: day) ?? day
        let end = calendar.date(byAdding: .year, value: upcomingRecurrenceYears, to: day) ?? day
        return DateInterval(start: start, end: end)
    }

    var recurrenceRangeDescription: String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        let range = recurrenceRange
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: range.end) ?? range.end
        let start = formatter.string(from: range.start)
        let end = formatter.string(from: lastDay)
        return String(localized: "繰り返し予定の表示期間：\(start)〜\(end)")
    }

    func loadMoreUpcomingEvents() {
        upcomingRecurrenceYears += 1
    }

    func loadMorePastEvents() {
        pastRecurrenceYears += 1
    }

    var allEvents: [CalendarEvent] {
        // Ordinary saved events retain their full history. Only generated
        // recurrences need a finite, explicitly extendable list window (§4.2).
        let calendar = Calendar.current
        let range = recurrenceRange
        if let cached = resolvedEventsCache, cached.calendar == calendar, cached.range == range {
            return cached.events
        }
        let recurring = EventQuerying.resolved(
            internalEvents: events.filter { $0.recurrenceRule != nil },
            exceptions: calendarExceptions,
            externalEvents: [],
            rangeStart: range.start,
            rangeEndExclusive: range.end,
            calendar: calendar
        )
        let result = EventQuerying.mergedDedupedSorted(
            internalEvents: events.filter { $0.recurrenceRule == nil } + recurring,
            externalEvents: externalEvents
        )
        resolvedEventsCache = ResolvedEventsCache(calendar: calendar, range: range, events: result)
        return result
    }

    func events(for section: EventSection) -> [CalendarEvent] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: effectiveReferenceDate)
        guard let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
            return []
        }

        switch section {
        case .today:
            return allEvents
                .filter { event in
                    EventQuerying.overlaps(event, rangeStart: todayStart, rangeEndExclusive: todayEnd, calendar: calendar)
                }
                .sorted(by: sortEvents)
        case .upcoming:
            return allEvents
                .filter { event in
                    event.displayStartDate(calendar: calendar) >= todayEnd
                }
                .sorted(by: sortEvents)
        case .past:
            return allEvents
                .filter { event in
                    event.displayEndDate(calendar: calendar) <= todayStart
                }
                .sorted { $0.displayStartDate(calendar: calendar) > $1.displayStartDate(calendar: calendar) } // Newest first for past
        }
    }

    func add(_ event: CalendarEvent) {
        store.addCalendarEvent(event)
    }

    func update(_ event: CalendarEvent) {
        store.updateCalendarEvent(event)
    }

    func delete(_ event: CalendarEvent) {
        store.deleteCalendarEvent(event)
    }

    func isExternalEvent(_ event: CalendarEvent) -> Bool {
        event.sourceCalendarIdentifier != nil
    }

    private func sortEvents(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        if lhs.displayStartDate() != rhs.displayStartDate() {
            return lhs.displayStartDate() < rhs.displayStartDate()
        }
        // 同じ開始時間なら終日予定を先に
        if lhs.isAllDay != rhs.isAllDay {
            return lhs.isAllDay
        }
        return lhs.title < rhs.title
    }
}
