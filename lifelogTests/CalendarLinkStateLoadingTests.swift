import EventKit
import SwiftData
import XCTest
@testable import lifelify

@MainActor
final class CalendarLinkStateLoadingTests: XCTestCase {
    func testFailedAppStateRead_preservesSnapshotAndBlocksCategoryResetAndWrites() throws {
        let container = PersistenceController(inMemory: true).container
        let saved = fixtureLink(identifier: "saved", category: "User choice")
        let unavailable = fixtureLink(identifier: "unavailable", category: nil)
        container.mainContext.insert(SDAppState(calendarCategoryLinks: [saved],
                                                unavailableCalendarCategoryLinks: [unavailable],
                                                diaryReminderEnabled: true))
        try container.mainContext.save()
        let store = makeStore(container: container)
        XCTAssertTrue(store.hasLoadedAppState)

        XCTAssertFalse(store.loadAppState(fetch: { throw ReadFailure.unavailable }))
        XCTAssertFalse(store.hasLoadedAppState)
        XCTAssertEqual(store.appState.calendarCategoryLinks, [saved])
        XCTAssertEqual(store.appState.unavailableCalendarCategoryLinks, [unavailable])

        store.updateCalendarLinks(with: [])
        XCTAssertEqual(store.appState.calendarCategoryLinks, [saved])
        XCTAssertEqual(store.appState.unavailableCalendarCategoryLinks, [unavailable])
        XCTAssertFalse(store.loadAppState(fetch: { throw ReadFailure.unavailable }))
        // A fresh/default snapshot cannot replace unknown persistent selections.
        store.appState = AppState()
        store.persistAppState()

        let reader = ModelContext(container)
        let rows = try reader.fetch(FetchDescriptor<SDAppState>())
        XCTAssertEqual(rows.count, 1)
        let state = AppState(sd: try XCTUnwrap(rows.first))
        XCTAssertEqual(state.calendarCategoryLinks, [saved])
        XCTAssertEqual(state.unavailableCalendarCategoryLinks, [unavailable])
        XCTAssertTrue(state.diaryReminderEnabled)
    }

    func testSuccessfulRetry_reloadsSavedChoicesBeforeReconciliation() throws {
        let container = PersistenceController(inMemory: true).container
        let eventStore = EKEventStore()
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = "User calendar"
        let saved = fixtureLink(identifier: calendar.calendarIdentifier, category: "User choice")
        let unavailable = fixtureLink(identifier: "unavailable", category: "Archived choice")
        container.mainContext.insert(SDAppState(calendarCategoryLinks: [saved],
                                                unavailableCalendarCategoryLinks: [unavailable]))
        try container.mainContext.save()
        let store = makeStore(container: container)
        XCTAssertFalse(store.loadAppState(fetch: { throw ReadFailure.unavailable }))
        store.appState = AppState()

        // Sync entry points retry this read before accessing EventKit.
        XCTAssertTrue(store.loadAppState())

        XCTAssertTrue(store.hasLoadedAppState)
        XCTAssertEqual(store.appState.calendarCategoryLinks, [saved])
        XCTAssertEqual(store.appState.unavailableCalendarCategoryLinks, [unavailable])
        store.updateCalendarLinks(with: [calendar])
        store.updateCalendarLinkCategory(calendarIdentifier: calendar.calendarIdentifier,
                                         categoryName: "Edited choice")

        let rows = try ModelContext(container).fetch(FetchDescriptor<SDAppState>())
        let state = AppState(sd: try XCTUnwrap(rows.first))
        XCTAssertEqual(state.calendarCategoryLinks.map(\.categoryId), ["Edited choice"])
        XCTAssertEqual(state.unavailableCalendarCategoryLinks, [unavailable])
    }

    func testSuccessfulEmptyStateRead_allowsNewCalendarSelectionsToPersist() throws {
        let container = PersistenceController(inMemory: true).container
        let store = makeStore(container: container)
        XCTAssertTrue(store.hasLoadedAppState)
        XCTAssertTrue(store.appState.calendarCategoryLinks.isEmpty)
        let eventStore = EKEventStore()
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = "旅行"

        store.updateCalendarLinks(with: [calendar])

        let rows = try ModelContext(container).fetch(FetchDescriptor<SDAppState>())
        XCTAssertEqual(rows.count, 1)
        let state = AppState(sd: try XCTUnwrap(rows.first))
        XCTAssertEqual(state.calendarCategoryLinks.first?.calendarIdentifier, calendar.calendarIdentifier)
        XCTAssertEqual(state.calendarCategoryLinks.first?.categoryId, "旅行")
        XCTAssertTrue(state.unavailableCalendarCategoryLinks.isEmpty)
    }

    private enum ReadFailure: Error {
        case unavailable
    }

    private func makeStore(container: ModelContainer) -> AppDataStore {
        AppDataStore(container: container, startsBackgroundServices: false,
                     defersNotificationUpdatesUntilStartup: true)
    }

    private func fixtureLink(identifier: String, category: String?) -> CalendarCategoryLink {
        CalendarCategoryLink(calendarIdentifier: identifier, calendarTitle: "User calendar",
                             categoryId: category, colorHex: nil)
    }
}
