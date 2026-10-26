import XCTest
import SwiftData
import Combine
@testable import lifelify

@MainActor
final class CalendarPersistencePerformanceTests: XCTestCase {
    func testEditingOneEvent_preservesPendingChangesToOtherStoredEvents() throws {
        let first = event(title: "First")
        let second = event(title: "Second", offset: 3_600)
        let store = try makeStore(events: [first, second])
        store.modelContext.autosaveEnabled = false
        let rows = try store.modelContext.fetch(FetchDescriptor<SDCalendarEvent>())
        let otherRow = try XCTUnwrap(rows.first { $0.id == second.id })
        otherRow.title = "Incoming change to another event"
        var edited = first
        edited.title = "Edited first"
        edited.detail = "Updated details"

        store.updateCalendarEvent(edited)

        let persisted = try persistedEvents(in: store)
        XCTAssertEqual(persisted.count, 2)
        XCTAssertEqual(persisted.first { $0.id == first.id }, edited)
        XCTAssertEqual(persisted.first { $0.id == second.id }?.title, "Incoming change to another event")
    }

    func testAddAndDelete_doNotRemoveRowsMissingFromMemorySnapshot() throws {
        let original = event(title: "Original")
        let store = try makeStore(events: [original])
        let incoming = event(title: "Incoming", offset: 3_600)
        let otherContext = ModelContext(store.modelContext.container)
        otherContext.insert(SDCalendarEvent(domain: incoming))
        try otherContext.save()
        let added = event(title: "Added", offset: 7_200)

        store.addCalendarEvent(added)
        XCTAssertEqual(Set(try persistedEvents(in: store).map(\.id)), Set([original.id, incoming.id, added.id]))
        store.deleteCalendarEvent(added.id)

        XCTAssertEqual(Set(try persistedEvents(in: store).map(\.id)), Set([original.id, incoming.id]))
        XCTAssertEqual(store.calendarEvents, [original])
    }

    func testEqualUpdate_doesNotPublishEvictCacheOrDirtyContext() throws {
        let original = event(title: "Original")
        let store = try makeStore(events: [original])
        let day = Calendar.current.startOfDay(for: original.startDate)
        store.eventsCache[day] = [original]
        var publications = 0
        let observation = store.$calendarEvents.dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel() }

        store.updateCalendarEvent(original)

        XCTAssertEqual(publications, 0)
        XCTAssertEqual(store.eventsCache[day], [original])
        XCTAssertFalse(store.modelContext.hasChanges)
        XCTAssertEqual(try persistedEvents(in: store), [original])
    }

    func testAddRetryWhenMemoryAlreadyContainsEvent_insertsOnceWithoutPublishingAgain() throws {
        let store = try makeStore(events: [])
        let original = event(title: "Original")
        // Memory can already reflect an operation whose persistence fetch failed.
        store.calendarEvents = [original]
        var publications = 0
        let observation = store.$calendarEvents.dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel() }

        store.addCalendarEvent(original)
        store.addCalendarEvent(original)

        XCTAssertEqual(publications, 0)
        XCTAssertEqual(store.calendarEvents, [original])
        XCTAssertEqual(try persistedEvents(in: store), [original])
    }

    func testEqualUpdateWithPendingSave_retriesSaveWithoutPublishingAgain() throws {
        let original = event(title: "Original")
        let store = try makeStore(events: [original])
        store.modelContext.autosaveEnabled = false
        var edited = original
        edited.title = "Pending edit"
        store.calendarEvents = [edited]
        let row = try XCTUnwrap(store.modelContext.fetch(FetchDescriptor<SDCalendarEvent>()).first)
        row.update(from: edited)
        XCTAssertTrue(store.modelContext.hasChanges)
        var publications = 0
        let observation = store.$calendarEvents.dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel() }

        store.updateCalendarEvent(edited)

        XCTAssertEqual(publications, 0)
        XCTAssertFalse(store.modelContext.hasChanges)
        XCTAssertEqual(try persistedEvents(in: store), [edited])
    }

    func testDeleteRetryWhenMemoryAlreadyRemovedEvent_removesStoredRowWithoutPublishingAgain() throws {
        let original = event(title: "Original")
        let retained = event(title: "Retained", offset: 3_600)
        let store = try makeStore(events: [original, retained])
        store.calendarEvents = [retained]
        var publications = 0
        let observation = store.$calendarEvents.dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel() }

        store.deleteCalendarEvent(original.id)
        store.deleteCalendarEvent(original.id)

        XCTAssertEqual(publications, 0)
        XCTAssertEqual(try persistedEvents(in: store), [retained])
    }

    private func makeStore(events: [CalendarEvent]) throws -> AppDataStore {
        let container = PersistenceController(inMemory: true).container
        for event in events { container.mainContext.insert(SDCalendarEvent(domain: event)) }
        try container.mainContext.save()
        return AppDataStore(container: container, startsBackgroundServices: false)
    }

    private func persistedEvents(in store: AppDataStore) throws -> [CalendarEvent] {
        try ModelContext(store.modelContext.container)
            .fetch(FetchDescriptor<SDCalendarEvent>())
            .map { CalendarEvent(sd: $0) }
    }

    private func event(title: String, offset: TimeInterval = 0) -> CalendarEvent {
        let start = Date(timeIntervalSince1970: 1_700_000_000 + offset)
        return CalendarEvent(title: title, startDate: start, endDate: start.addingTimeInterval(1_800), calendarName: "Work")
    }
}
