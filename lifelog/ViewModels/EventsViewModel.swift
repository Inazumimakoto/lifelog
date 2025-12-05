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
    }

    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var externalEvents: [CalendarEvent] = []

    private let store: AppDataStore
    private var cancellables = Set<AnyCancellable>()

    init(store: AppDataStore) {
        self.store = store
        bind()
    }

    private func bind() {
        store.$calendarEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] events in
                self?.events = events
            }
            .store(in: &cancellables)

        store.$externalCalendarEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] events in
                self?.externalEvents = events
            }
            .store(in: &cancellables)
    }

    var allEvents: [CalendarEvent] {
        events + externalEvents
    }

    func events(for section: EventSection) -> [CalendarEvent] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
            return []
        }

        switch section {
        case .today:
            return allEvents
                .filter { event in
                    event.startDate < todayEnd && event.endDate > todayStart
                }
                .sorted(by: sortEvents)
        case .upcoming:
            return allEvents
                .filter { event in
                    event.startDate >= todayEnd
                }
                .sorted(by: sortEvents)
        case .past:
            return allEvents
                .filter { event in
                    event.endDate <= todayStart
                }
                .sorted { $0.startDate > $1.startDate } // Newest first for past
        }
    }

    func add(_ event: CalendarEvent) {
        store.addCalendarEvent(event)
    }

    func update(_ event: CalendarEvent) {
        store.updateCalendarEvent(event)
    }

    func delete(_ event: CalendarEvent) {
        store.deleteCalendarEvent(event.id)
    }

    func isExternalEvent(_ event: CalendarEvent) -> Bool {
        event.sourceCalendarIdentifier != nil
    }

    private func sortEvents(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }
        // 同じ開始時間なら終日予定を先に
        if lhs.isAllDay != rhs.isAllDay {
            return lhs.isAllDay
        }
        return lhs.title < rhs.title
    }
}
