import Foundation
import EventKit
import SwiftData
import XCTest
@testable import lifelify

@MainActor
final class CalendarLinkRecoveryPersistenceTests: XCTestCase {
    func testEmptyInventoryThenReload_restoresEachCategoryAndHiddenSelection() throws {
        let store = makeStore()
        let eventStore = EKEventStore()
        let visible = calendar(title: "My schedule", eventStore: eventStore)
        let hidden = calendar(title: "Birthdays", eventStore: eventStore)
        let original = [link(for: visible, category: "User category"), link(for: hidden, category: nil)]
        store.appState.calendarCategoryLinks = original

        store.updateCalendarLinks(with: [])

        XCTAssertTrue(store.appState.calendarCategoryLinks.isEmpty)
        XCTAssertEqual(store.appState.unavailableCalendarCategoryLinks, original)
        let reloaded = makeStore(container: store.modelContext.container)
        XCTAssertEqual(reloaded.appState.unavailableCalendarCategoryLinks, original)

        reloaded.updateCalendarLinks(with: [visible, hidden])

        XCTAssertEqual(reloaded.appState.calendarCategoryLinks.map(\.calendarIdentifier),
                       [visible.calendarIdentifier, hidden.calendarIdentifier])
        XCTAssertEqual(reloaded.appState.calendarCategoryLinks.map(\.categoryId), ["User category", nil])
        XCTAssertTrue(reloaded.appState.unavailableCalendarCategoryLinks.isEmpty)
        let persisted = try XCTUnwrap(reloaded.modelContext.fetch(FetchDescriptor<SDAppState>()).first)
        XCTAssertEqual(persisted.calendarCategoryLinks, reloaded.appState.calendarCategoryLinks)
    }

    func testChangedIdentifiersAfterEmptyInventoryAndReload_restoresLegacyCategoryChoices() {
        let store = makeStore()
        store.appState.calendarCategoryLinks = [
            CalendarCategoryLink(calendarIdentifier: "old-personal", calendarTitle: "My schedule",
                                 categoryId: "Personal choice", colorHex: "#123456"),
            CalendarCategoryLink(calendarIdentifier: "old-hidden", calendarTitle: "Birthdays",
                                 categoryId: nil, colorHex: "#654321")
        ]
        store.updateCalendarLinks(with: [])
        let reloaded = makeStore(container: store.modelContext.container)
        let eventStore = EKEventStore()
        let visible = calendar(title: "My schedule", eventStore: eventStore)
        let hidden = calendar(title: "Birthdays", eventStore: eventStore)

        reloaded.updateCalendarLinks(with: [visible, hidden])

        XCTAssertEqual(reloaded.appState.calendarCategoryLinks.map(\.calendarIdentifier),
                       [visible.calendarIdentifier, hidden.calendarIdentifier])
        XCTAssertEqual(reloaded.appState.calendarCategoryLinks.map(\.categoryId), ["Personal choice", nil])
        XCTAssertTrue(reloaded.appState.unavailableCalendarCategoryLinks.isEmpty)
    }

    func testPartialInventoryThenReload_keepsMissingChoiceAndLaterVisibleEdits() {
        let store = makeStore()
        let eventStore = EKEventStore()
        let first = calendar(title: "First calendar", eventStore: eventStore)
        let second = calendar(title: "Second calendar", eventStore: eventStore)
        store.appState.calendarCategoryLinks = [
            link(for: first, category: "First choice"),
            link(for: second, category: "Second choice")
        ]

        store.updateCalendarLinks(with: [first])
        store.updateCalendarLinkCategory(calendarIdentifier: first.calendarIdentifier, categoryName: "Changed choice")
        let reloaded = makeStore(container: store.modelContext.container)

        XCTAssertEqual(reloaded.appState.calendarCategoryLinks.map(\.categoryId), ["Changed choice"])
        XCTAssertEqual(reloaded.appState.unavailableCalendarCategoryLinks.map(\.categoryId), ["Second choice"])
        reloaded.updateCalendarLinks(with: [second, first])

        XCTAssertEqual(reloaded.appState.calendarCategoryLinks.first {
            $0.calendarIdentifier == first.calendarIdentifier
        }?.categoryId, "Changed choice")
        XCTAssertEqual(reloaded.appState.calendarCategoryLinks.first {
            $0.calendarIdentifier == second.calendarIdentifier
        }?.categoryId, "Second choice")
        XCTAssertTrue(reloaded.appState.unavailableCalendarCategoryLinks.isEmpty)
    }

    func testArchivedCategoryRename_survivesReloadAndDoesNotRestoreOldCategory() {
        let store = makeStore()
        let eventStore = EKEventStore()
        let calendar = calendar(title: "Temporarily unavailable", eventStore: eventStore)
        store.appState.calendarCategoryLinks = [link(for: calendar, category: "Old choice")]
        store.updateCalendarLinks(with: [])

        // Category deletion uses this same reference migration with a replacement.
        store.renameCalendarCategory(from: "Old choice", to: "Replacement choice")
        let reloaded = makeStore(container: store.modelContext.container)

        XCTAssertEqual(reloaded.appState.unavailableCalendarCategoryLinks.map(\.categoryId), ["Replacement choice"])
        reloaded.updateCalendarLinks(with: [calendar])
        XCTAssertEqual(reloaded.appState.calendarCategoryLinks.map(\.categoryId), ["Replacement choice"])
        XCTAssertTrue(reloaded.appState.unavailableCalendarCategoryLinks.isEmpty)
    }

    func testLegacyJSONWithoutRecoveryFields_preservesCalendarChoicesAndReminderSettings() throws {
        let payload = Data(##"{"calendarCategoryLinks":[{"calendarIdentifier":"saved-id","calendarTitle":"User calendar","categoryId":"User category","colorHex":"#123456"},{"calendarIdentifier":"hidden-id","calendarTitle":"Hidden calendar"}],"diaryReminderEnabled":true,"diaryReminderHour":7,"diaryReminderMinute":30}"##.utf8)

        let state = try JSONDecoder().decode(AppState.self, from: payload)

        XCTAssertEqual(state.calendarCategoryLinks.map(\.categoryId), ["User category", nil])
        XCTAssertNil(state.calendarCategoryLinks.first?.sourceIdentifier)
        XCTAssertNil(state.calendarCategoryLinks.first?.sourceTitle)
        XCTAssertNil(state.calendarCategoryLinks.first?.sourceTypeRawValue)
        XCTAssertNil(state.calendarCategoryLinks.first?.calendarTypeRawValue)
        XCTAssertTrue(state.unavailableCalendarCategoryLinks.isEmpty)
        XCTAssertTrue(state.diaryReminderEnabled)
        XCTAssertEqual(state.diaryReminderHour, 7)
        XCTAssertEqual(state.diaryReminderMinute, 30)
    }

    func testRecoveryMetadataRoundTrip_preservesUnavailableChoicesAndSourceIdentity() throws {
        var source = CalendarCategoryLink(calendarIdentifier: "old-id", calendarTitle: "Calendar",
                                          categoryId: "Saved choice", colorHex: "#123456")
        source.sourceIdentifier = "account-id"
        source.sourceTitle = "User account"
        source.sourceTypeRawValue = EKSourceType.calDAV.rawValue
        source.calendarTypeRawValue = EKCalendarType.calDAV.rawValue
        var state = AppState()
        state.unavailableCalendarCategoryLinks = [source]

        let decoded = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))

        XCTAssertEqual(decoded.unavailableCalendarCategoryLinks, [source])
        XCTAssertTrue(decoded.calendarCategoryLinks.isEmpty)
    }

    func testLegacySQLiteMigration_preservesChoicesAndPersistsArchiveAcrossReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("calendar-link-migration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.store")
        let original = CalendarCategoryLink(calendarIdentifier: "saved-id", calendarTitle: "User calendar",
                                            categoryId: "User choice", colorHex: "#123456")
        weak var releasedContainer: ModelContainer?

        try autoreleasepool {
            let schema = Schema([LegacyCalendarLinkStateSchema.SDAppState.self])
            let container = try ModelContainer(for: schema, configurations: [
                ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            ])
            releasedContainer = container
            let context = ModelContext(container)
            context.insert(LegacyCalendarLinkStateSchema.SDAppState(links: [original]))
            try context.save()
        }
        XCTAssertNil(releasedContainer)

        for launch in 0..<2 {
            try autoreleasepool {
                let schema = Schema([SDAppState.self])
                let container = try ModelContainer(for: schema, configurations: [
                    ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
                ])
                let context = ModelContext(container)
                let rows = try context.fetch(FetchDescriptor<SDAppState>())
                XCTAssertEqual(rows.count, 1)
                let row = try XCTUnwrap(rows.first)
                let state = AppState(sd: row)
                XCTAssertTrue(state.diaryReminderEnabled)
                XCTAssertEqual(state.diaryReminderHour, 7)
                XCTAssertEqual(state.diaryReminderMinute, 30)
                if launch == 0 {
                    XCTAssertEqual(state.calendarCategoryLinks, [original])
                    XCTAssertTrue(state.unavailableCalendarCategoryLinks.isEmpty)
                    row.calendarCategoryLinks = []
                    row.unavailableCalendarCategoryLinks = [original]
                    try context.save()
                } else {
                    XCTAssertTrue(state.calendarCategoryLinks.isEmpty)
                    XCTAssertEqual(state.unavailableCalendarCategoryLinks, [original])
                }
            }
        }
    }

    private func makeStore(container: ModelContainer? = nil) -> AppDataStore {
        AppDataStore(container: container ?? PersistenceController(inMemory: true).container,
                     startsBackgroundServices: false, defersNotificationUpdatesUntilStartup: true)
    }

    private func calendar(title: String, eventStore: EKEventStore) -> EKCalendar {
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = title
        return calendar
    }

    private func link(for calendar: EKCalendar, category: String?) -> CalendarCategoryLink {
        CalendarCategoryLink(calendarIdentifier: calendar.calendarIdentifier, calendarTitle: calendar.title,
                             categoryId: category, colorHex: nil)
    }
}

/// The persisted entity shape before adding the optional unavailable-link archive.
private enum LegacyCalendarLinkStateSchema {
    @Model
    final class SDAppState {
        var lastCalendarSyncDate: Date?
        var calendarCategoryLinks: [CalendarCategoryLink]
        var diaryReminderEnabled: Bool
        var diaryReminderHour: Int
        var diaryReminderMinute: Int

        init(links: [CalendarCategoryLink]) {
            lastCalendarSyncDate = nil
            calendarCategoryLinks = links
            diaryReminderEnabled = true
            diaryReminderHour = 7
            diaryReminderMinute = 30
        }
    }
}
