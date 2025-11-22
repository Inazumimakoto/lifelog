//
//  CalendarEventService.swift
//  lifelog
//
//  Created by Codex on 2025/11/22.
//

import Foundation
import EventKit

@MainActor
final class CalendarEventService {
    private let eventStore = EKEventStore()

    func requestAccessIfNeeded() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            do {
                return try await eventStore.requestAccess(to: .event)
            } catch {
                return false
            }
        default:
            return false
        }
    }

    func fetchEventsForCurrentAndNextMonth() async throws -> [EKEvent] {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .authorized else { return [] }

        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        guard let startOfMonth = calendar.date(from: components),
              let startOfNextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth),
              let endOfNextMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfNextMonth) else {
            return []
        }

        let startDate = startOfMonth
        let endDate = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endOfNextMonth) ?? endOfNextMonth

        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        return events
    }

    func refreshCalendarLinks(store: AppDataStore) {
        let calendars = eventStore.calendars(for: .event)
        store.updateCalendarLinks(with: calendars)
    }
}
