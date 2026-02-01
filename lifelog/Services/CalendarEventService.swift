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

    func fetchEvents(from startDate: Date, to endDate: Date) async throws -> [EKEvent] {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .authorized else { return [] }
        guard startDate <= endDate else { return [] }

        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        return events
    }

    func refreshCalendarLinks(store: AppDataStore) {
        // Only access calendars if authorized
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .authorized else { return }
        
        let calendars = eventStore.calendars(for: .event)
        store.updateCalendarLinks(with: calendars)
    }

}
