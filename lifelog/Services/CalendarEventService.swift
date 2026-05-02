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

    func requestAccessIfNeeded(shouldPrompt: Bool = true) async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            return true
        case .writeOnly:
            return false
        case .notDetermined:
            guard shouldPrompt else { return false }
            do {
                return try await eventStore.requestFullAccessToEvents()
            } catch {
                return false
            }
        default:
            return false
        }
    }

    func fetchEvents(from startDate: Date, to endDate: Date) async throws -> [EKEvent] {
        guard Self.hasFullCalendarAccess else { return [] }
        guard startDate <= endDate else { return [] }

        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        return events
    }

    func refreshCalendarLinks(store: AppDataStore) {
        // Only access calendars if authorized
        guard Self.hasFullCalendarAccess else { return }
        
        let calendars = eventStore.calendars(for: .event)
        store.updateCalendarLinks(with: calendars)
    }

    private static var hasFullCalendarAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }
}
