import XCTest
import Combine
import SwiftUI
import SwiftData
@testable import lifelify

@MainActor
final class CalendarCategoryServiceTests: XCTestCase {
    func testAdd_trimsNameAndPreservesUserSpelling() throws {
        try withFixture(palette: ["Work": "#FF0000"]) {
            let service = CalendarCategoryService(store: makeStore())

            let name = try service.add(name: " \n work \t", colorToken: "#0000FF")

            XCTAssertEqual(name, "work")
            XCTAssertEqual(CategoryPalette.allCategories(), [
                .init(name: "Work", colorName: "#FF0000"),
                .init(name: "work", colorName: "#0000FF")
            ])
        }
    }

    func testEmptyName_rejectsAddAndRenameWithoutChangingPalette() throws {
        try withFixture(palette: ["Work": "#FF0000"]) {
            let service = CalendarCategoryService(store: makeStore())
            let originalPalette = CategoryPalette.allCategories()

            XCTAssertThrowsError(try service.add(name: " \t\n", colorToken: "#0000FF")) {
                XCTAssertEqual($0 as? CalendarCategoryService.ValidationError, .emptyName)
            }
            XCTAssertThrowsError(try service.update(originalName: "Work", name: " \t\n", colorToken: "#0000FF")) {
                XCTAssertEqual($0 as? CalendarCategoryService.ValidationError, .emptyName)
            }

            XCTAssertEqual(CategoryPalette.allCategories(), originalPalette)
        }
    }

    func testDuplicateAdd_preservesExistingColorAndDoesNotPublish() throws {
        try withFixture(palette: ["Work": "#FF0000"]) {
            let store = makeStore()
            let service = CalendarCategoryService(store: store)
            var publications = 0
            let observation = store.objectWillChange.sink { publications += 1 }
            defer { observation.cancel() }

            XCTAssertThrowsError(try service.add(name: "\n Work ", colorToken: "#0000FF")) {
                XCTAssertEqual($0 as? CalendarCategoryService.ValidationError, .duplicateName)
            }

            XCTAssertEqual(CategoryPalette.allCategories(), [.init(name: "Work", colorName: "#FF0000")])
            XCTAssertEqual(publications, 0)
        }
    }

    func testDuplicateRename_keepsBothCategoriesAndTheirReferencesUnchanged() throws {
        try withFixture(palette: ["Work": "#FF0000", "Personal": "#0000FF"]) {
            let store = makeStore()
            let service = CalendarCategoryService(store: store)
            store.calendarEvents = [fixtureEvent(title: "Internal", category: "Work")]
            store.externalCalendarEvents = [fixtureEvent(title: "External", category: "Personal", source: "personal")]
            store.appState.calendarCategoryLinks = [fixtureLink(identifier: "work", category: "Work")]
            let originalPalette = CategoryPalette.allCategories()
            let originalInternal = store.calendarEvents
            let originalExternal = store.externalCalendarEvents
            let originalLinks = store.appState.calendarCategoryLinks
            let generation = store.externalReminderRescheduleGeneration

            XCTAssertThrowsError(try service.update(originalName: "Work", name: " Personal ", colorToken: "#00FF00")) {
                XCTAssertEqual($0 as? CalendarCategoryService.ValidationError, .duplicateName)
            }

            XCTAssertEqual(CategoryPalette.allCategories(), originalPalette)
            XCTAssertEqual(store.calendarEvents, originalInternal)
            XCTAssertEqual(store.externalCalendarEvents, originalExternal)
            XCTAssertEqual(store.appState.calendarCategoryLinks, originalLinks)
            XCTAssertEqual(store.externalReminderRescheduleGeneration, generation)
            XCTAssertTrue(try store.modelContext.fetch(FetchDescriptor<SDCalendarEvent>()).isEmpty)
            XCTAssertTrue(try store.modelContext.fetch(FetchDescriptor<SDAppState>()).isEmpty)
        }
    }

    func testRename_movesSharedLinksAndInternalExternalEventsWhilePreservingTheirFields() throws {
        try withFixture(palette: ["Work": "#FF0000", "Personal": "#0000FF"]) {
            let store = makeStore()
            let service = CalendarCategoryService(store: store)
            store.calendarEvents = [
                fixtureEvent(title: "Internal", category: "Work"),
                fixtureEvent(title: "Unrelated internal", category: "Personal")
            ]
            store.externalCalendarEvents = [
                fixtureEvent(title: "First external", category: "Work", source: "first"),
                fixtureEvent(title: "Second external", category: "Work", source: "second"),
                fixtureEvent(title: "Legacy external", category: "Work"),
                fixtureEvent(title: "Unrelated external", category: "Personal", source: "personal")
            ]
            store.appState.calendarCategoryLinks = [
                fixtureLink(identifier: "first", category: "Work"),
                fixtureLink(identifier: "second", category: "Work"),
                fixtureLink(identifier: "personal", category: "Personal"),
                fixtureLink(identifier: "hidden", category: nil)
            ]
            let originalInternal = store.calendarEvents
            let originalExternal = store.externalCalendarEvents
            store.eventsCache[fixtureDay] = originalInternal + originalExternal
            let range = ExternalCalendarRange(start: fixtureDay, end: fixtureDay.addingTimeInterval(86_400))
            store.externalCalendarRange = range
            NotificationSettingsManager.shared.saveCategorySettings([
                .init(categoryName: "Work", enabled: false, useRelativeTime: false,
                      minutesBefore: 15, hour: 8, minute: 45)
            ])

            let name = try service.update(originalName: "Work", name: "\nMy category ", colorToken: "#00FF00")

            XCTAssertEqual(name, "My category")
            let expectedInternal = migrating(originalInternal, from: "Work", to: name)
            let expectedExternal = migrating(originalExternal, from: "Work", to: name)
            XCTAssertEqual(store.calendarEvents, expectedInternal)
            XCTAssertEqual(store.externalCalendarEvents, expectedExternal)
            XCTAssertEqual(store.appState.calendarCategoryLinks.map(\.categoryId), [name, name, "Personal", nil])
            XCTAssertNil(store.eventsCache[fixtureDay])
            XCTAssertEqual(store.currentExternalCalendarRange(), range)
            XCTAssertEqual(CategoryPalette.allCategories(), [
                .init(name: name, colorName: "#00FF00"),
                .init(name: "Personal", colorName: "#0000FF")
            ])
            let persistedEvents = try store.modelContext.fetch(FetchDescriptor<SDCalendarEvent>())
            XCTAssertEqual(Set(persistedEvents.map { CalendarEvent(sd: $0) }), Set(expectedInternal))
            let persistedState = try store.modelContext.fetch(FetchDescriptor<SDAppState>()).first
            XCTAssertEqual(persistedState?.calendarCategoryLinks, store.appState.calendarCategoryLinks)
            let sharedDefaults = try XCTUnwrap(UserDefaults(suiteName: PersistenceController.appGroupIdentifier))
            let savedExternal = try XCTUnwrap(sharedDefaults.data(forKey: AppDataStore.externalCalendarEventsDefaultsKey))
            XCTAssertEqual(try JSONDecoder().decode([CalendarEvent].self, from: savedExternal), expectedExternal)
            XCTAssertNil(NotificationSettingsManager.shared.getSetting(for: "Work"))
            XCTAssertEqual(NotificationSettingsManager.shared.getSetting(for: name),
                           .init(categoryName: name, enabled: false, useRelativeTime: false,
                                 minutesBefore: 15, hour: 8, minute: 45))
        }
    }

    func testDelete_movesSharedReferencesToFirstRemainingCategory() throws {
        try withFixture(palette: ["Work": "#FF0000", "Fallback": "#00FF00", "Personal": "#0000FF"]) {
            let store = makeStore()
            let service = CalendarCategoryService(store: store)
            store.calendarEvents = [fixtureEvent(title: "Internal", category: "Work")]
            store.externalCalendarEvents = [
                fixtureEvent(title: "First external", category: "Work", source: "first"),
                fixtureEvent(title: "Second external", category: "Work", source: "second"),
                fixtureEvent(title: "Unrelated external", category: "Personal", source: "personal")
            ]
            store.appState.calendarCategoryLinks = [
                fixtureLink(identifier: "first", category: "Work"),
                fixtureLink(identifier: "second", category: "Work"),
                fixtureLink(identifier: "personal", category: "Personal"),
                fixtureLink(identifier: "hidden", category: nil)
            ]
            let originalInternal = store.calendarEvents
            let originalExternal = store.externalCalendarEvents
            let replacementNotification = CategoryNotificationSetting(categoryName: "Fallback", enabled: false,
                                                                      minutesBefore: 60)
            NotificationSettingsManager.shared.saveCategorySettings([
                .init(categoryName: "Work", minutesBefore: 15), replacementNotification
            ])

            let replacement = service.delete(name: "Work")

            XCTAssertEqual(replacement, "Fallback")
            XCTAssertEqual(store.calendarEvents, migrating(originalInternal, from: "Work", to: replacement))
            XCTAssertEqual(store.externalCalendarEvents, migrating(originalExternal, from: "Work", to: replacement))
            XCTAssertEqual(store.appState.calendarCategoryLinks.map(\.categoryId), [replacement, replacement, "Personal", nil])
            XCTAssertEqual(CategoryPalette.allCategoryNames(), ["Fallback", "Personal"])
            XCTAssertNil(NotificationSettingsManager.shared.getSetting(for: "Work"))
            XCTAssertEqual(NotificationSettingsManager.shared.getSetting(for: replacement), replacementNotification)
        }
    }

    func testDeleteLastCategory_createsDefaultAndPreservesAllEvents() throws {
        try withFixture(palette: ["Only category": "#FF0000"]) {
            let store = makeStore()
            let service = CalendarCategoryService(store: store)
            store.calendarEvents = [fixtureEvent(title: "Internal", category: "Only category")]
            store.externalCalendarEvents = [fixtureEvent(title: "External", category: "Only category", source: "first")]
            store.appState.calendarCategoryLinks = [fixtureLink(identifier: "first", category: "Only category")]
            let originalInternal = store.calendarEvents
            let originalExternal = store.externalCalendarEvents

            let replacement = service.delete(name: "Only category")

            XCTAssertEqual(replacement, "仕事")
            XCTAssertEqual(CategoryPalette.allCategories(), [.init(name: "仕事", colorName: AppColorPalette.defaultHex)])
            XCTAssertEqual(store.calendarEvents, migrating(originalInternal, from: "Only category", to: replacement))
            XCTAssertEqual(store.externalCalendarEvents, migrating(originalExternal, from: "Only category", to: replacement))
            XCTAssertEqual(store.appState.calendarCategoryLinks.first?.categoryId, replacement)
        }
    }

    func testDeleteLastDefaultCategory_retainsValidDefaultReferences() throws {
        try withFixture(palette: ["仕事": "#FF0000"]) {
            let store = makeStore()
            let service = CalendarCategoryService(store: store)
            let event = fixtureEvent(title: "Internal", category: "仕事")
            store.calendarEvents = [event]
            store.appState.calendarCategoryLinks = [fixtureLink(identifier: "first", category: "仕事")]

            let replacement = service.delete(name: "仕事")

            XCTAssertEqual(replacement, "仕事")
            XCTAssertEqual(CategoryPalette.allCategories(), [.init(name: "仕事", colorName: AppColorPalette.defaultHex)])
            XCTAssertEqual(store.calendarEvents, [event])
            XCTAssertEqual(store.appState.calendarCategoryLinks.first?.categoryId, replacement)
        }
    }

    func testColorOnlyUpdate_notifiesSynchronouslyWithNewColorWithoutChangingEventsOrLinks() throws {
        try withFixture(palette: ["Work": "#FF0000"]) {
            let store = makeStore()
            let service = CalendarCategoryService(store: store)
            store.calendarEvents = [fixtureEvent(title: "Internal", category: "Work")]
            store.appState.calendarCategoryLinks = [fixtureLink(identifier: "first", category: "Work")]
            let originalEvents = store.calendarEvents
            let originalLinks = store.appState.calendarCategoryLinks
            let generation = store.externalReminderRescheduleGeneration
            var observedColors: [Color] = []
            let observation = store.objectWillChange.sink {
                observedColors.append(CategoryPalette.color(for: "Work"))
            }
            defer { observation.cancel() }

            let name = try service.update(originalName: "Work", name: " Work ", colorToken: "#0000FF")

            XCTAssertEqual(name, "Work")
            XCTAssertEqual(observedColors, [AppColorPalette.color(for: "#0000FF")])
            XCTAssertEqual(store.calendarEvents, originalEvents)
            XCTAssertEqual(store.appState.calendarCategoryLinks, originalLinks)
            XCTAssertEqual(store.externalReminderRescheduleGeneration, generation)
        }
    }

    func testInitializeAfterRenamingBuiltInCategory_preservesUserNameAndColor() throws {
        try withFixture(palette: ["仕事": "#FF0000", "趣味": "#00FF00", "旅行": "#0000FF"]) {
            let service = CalendarCategoryService(store: makeStore())
            try service.update(originalName: "仕事", name: "Career", colorToken: "#123456")
            let savedCategories = CategoryPalette.allCategories()
            var publications = 0
            let observation = CategoryPalette.changes.sink { publications += 1 }
            defer { observation.cancel() }

            CategoryPalette.initializeIfNeeded()

            XCTAssertEqual(CategoryPalette.allCategories(), savedCategories)
            XCTAssertEqual(CategoryPalette.allCategoryNames(), ["Career", "旅行", "趣味"])
            XCTAssertEqual(CategoryPalette.allCategories().first?.colorName, "#123456")
            XCTAssertEqual(publications, 0)
        }
    }

    func testInitializeAfterDeletingBuiltInCategory_doesNotRestoreRemovedCategory() throws {
        try withFixture(palette: ["仕事": "#FF0000", "趣味": "#00FF00", "旅行": "#0000FF"]) {
            let service = CalendarCategoryService(store: makeStore())
            service.delete(name: "趣味")
            let savedCategories = CategoryPalette.allCategories()
            var publications = 0
            let observation = CategoryPalette.changes.sink { publications += 1 }
            defer { observation.cancel() }

            CategoryPalette.initializeIfNeeded()

            XCTAssertEqual(CategoryPalette.allCategories(), savedCategories)
            XCTAssertEqual(CategoryPalette.allCategories(), [
                .init(name: "仕事", colorName: "#FF0000"),
                .init(name: "旅行", colorName: "#0000FF")
            ])
            XCTAssertEqual(publications, 0)
        }
    }

    private var fixtureDay: Date {
        Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private func makeStore() -> AppDataStore {
        AppDataStore(container: PersistenceController(inMemory: true).container, startsBackgroundServices: false)
    }

    private func fixtureEvent(title: String, category: String, source: String? = nil) -> CalendarEvent {
        CalendarEvent(title: title, detail: "User-created event detail",
                      startDate: fixtureDay.addingTimeInterval(3_600),
                      endDate: fixtureDay.addingTimeInterval(7_200), calendarName: category,
                      sourceCalendarIdentifier: source)
    }

    private func fixtureLink(identifier: String, category: String?) -> CalendarCategoryLink {
        CalendarCategoryLink(calendarIdentifier: identifier, calendarTitle: "User-created calendar title",
                             categoryId: category, colorHex: "#123456")
    }

    private func migrating(_ events: [CalendarEvent], from original: String, to replacement: String) -> [CalendarEvent] {
        events.map { event in
            var updated = event
            if updated.calendarName == original { updated.calendarName = replacement }
            return updated
        }
    }

    private func withFixture(palette: [String: String], operation: () throws -> Void) throws {
        let sharedDefaults = try XCTUnwrap(UserDefaults(suiteName: PersistenceController.appGroupIdentifier))
        let scopes = [UserDefaults.standard, sharedDefaults]
        let paletteKey = "CategoryPalette_Categories_V3"
        let keys = [paletteKey, "categoryNotificationSettings", "eventCategoryNotificationEnabled",
                    "todayOverviewNotificationEnabled", AppDataStore.externalCalendarEventsDefaultsKey,
                    AppDataStore.externalCalendarRangeDefaultsKey]
        let savedValues = scopes.flatMap { defaults in
            keys.map { key in (defaults: defaults, key: key, value: defaults.object(forKey: key)) }
        }
        defer {
            for entry in savedValues {
                if let value = entry.value {
                    entry.defaults.set(value, forKey: entry.key)
                } else {
                    entry.defaults.removeObject(forKey: entry.key)
                }
            }
        }
        let paletteData = try JSONEncoder().encode(palette)
        for defaults in scopes {
            defaults.set(paletteData, forKey: paletteKey)
            defaults.removeObject(forKey: "categoryNotificationSettings")
            defaults.set(false, forKey: "eventCategoryNotificationEnabled")
            defaults.set(false, forKey: "todayOverviewNotificationEnabled")
            defaults.removeObject(forKey: AppDataStore.externalCalendarEventsDefaultsKey)
            defaults.removeObject(forKey: AppDataStore.externalCalendarRangeDefaultsKey)
        }
        try operation()
    }
}
