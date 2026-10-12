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
    private static let eventQuery = CalendarEventQueryCoordinator()

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

        // EventKit's async-looking wrapper must not run its synchronous database
        // query on MainActor: this range can contain two years of recurring events.
        return await Self.eventQuery.fetchEvents(from: startDate, to: endDate)
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

/// Launch, Today and Journal can request the same range before the first fetch
/// finishes. Join that in-flight query across service instances, then discard it
/// so an explicit subsequent refresh still reads current calendar data.
@MainActor
final class CalendarEventQueryCoordinator {
    private struct Range: Hashable {
        let start: Date
        let end: Date
    }

    private let query: CalendarEventQuery
    private var inFlight: [Range: _Concurrency.Task<[EKEvent], Never>] = [:]

    init(query: CalendarEventQuery = CalendarEventQuery()) {
        self.query = query
    }

    func fetchEvents(from startDate: Date, to endDate: Date) async -> [EKEvent] {
        guard startDate <= endDate else { return [] }
        let range = Range(start: startDate, end: endDate)
        if let pending = inFlight[range] {
            return await pending.value
        }
        let pending = _Concurrency.Task {
            await query.fetchEvents(from: startDate, to: endDate)
        }
        inFlight[range] = pending
        defer { inFlight.removeValue(forKey: range) }
        return await pending.value
    }
}

/// A separate store confines synchronous EventKit reads to one serial queue.
/// The main-actor store above remains responsible for authorization and links.
nonisolated final class CalendarEventQuery: @unchecked Sendable {
    private let queue = DispatchQueue(label: "lifelify.calendar-query", qos: .userInitiated)
    private let eventStore: EKEventStore
    private let query: (@Sendable (Date, Date) -> [EKEvent])?

    init(query: (@Sendable (Date, Date) -> [EKEvent])? = nil) {
        eventStore = EKEventStore()
        self.query = query
    }

    func fetchEvents(from startDate: Date, to endDate: Date) async -> [EKEvent] {
        guard startDate <= endDate else { return [] }
        return await withCheckedContinuation { continuation in
            queue.async {
                let events: [EKEvent]
                if let query = self.query {
                    events = query(startDate, endDate)
                } else {
                    let predicate = self.eventStore.predicateForEvents(
                        withStart: startDate, end: endDate, calendars: nil
                    )
                    events = self.eventStore.events(matching: predicate)
                }
                continuation.resume(returning: events)
            }
        }
    }
}
