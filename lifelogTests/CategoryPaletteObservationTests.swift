import XCTest
import Combine
import SwiftUI
@testable import lifelify

@MainActor
final class CategoryPaletteObservationTests: XCTestCase {
    func testColorOnlyEdit_notifiesStoreSynchronouslyAfterSavingNewColor() throws {
        try withPalette(["Shared": "#FF0000"]) {
            let store = makeStore()
            store.appState.calendarCategoryLinks = [
                CalendarCategoryLink(calendarIdentifier: "first", calendarTitle: "First",
                                     categoryId: "Shared", colorHex: nil),
                CalendarCategoryLink(calendarIdentifier: "second", calendarTitle: "Second",
                                     categoryId: "Shared", colorHex: nil)
            ]
            let originalLinks = store.appState.calendarCategoryLinks
            var publications = 0
            var childViewPublications = 0
            var observedColors: [Color] = []
            let observation = store.objectWillChange.sink {
                publications += 1
                observedColors = store.appState.calendarCategoryLinks.compactMap(\.categoryId)
                    .map { CategoryPalette.color(for: $0) }
            }
            let childViewObservation = CategoryPaletteObserver.shared.objectWillChange.sink {
                childViewPublications += 1
            }
            defer {
                observation.cancel()
                childViewObservation.cancel()
            }

            CategoryPalette.renameCategory(oldName: "Shared", newName: "Shared", colorName: "#0000FF")

            XCTAssertEqual(publications, 1)
            XCTAssertEqual(childViewPublications, 1)
            XCTAssertEqual(observedColors, Array(repeating: AppColorPalette.color(for: "#0000FF"), count: 2))
            XCTAssertEqual(store.appState.calendarCategoryLinks, originalLinks)
        }
    }

    func testColorOnlyEdit_notifiesTodayAndJournalWithoutRebuildingCalendarData() throws {
        try withPalette(["Shared": "#FF0000"]) {
            let store = makeStore()
            let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
            let event = CalendarEvent(title: "Meeting", startDate: day.addingTimeInterval(3_600),
                                      endDate: day.addingTimeInterval(7_200), calendarName: "Shared")
            store.calendarEvents = [event]
            let today = TodayViewModel(store: store, date: day)
            let journal = JournalViewModel(store: store, anchorDate: day)
            let originalDays = journal.days
            let originalTimeline = today.timelineItems
            let originalRevision = journal.dataRevision
            let originalReminderGeneration = store.externalReminderRescheduleGeneration
            var todayPublications = 0
            var journalPublications = 0
            let todayObservation = today.objectWillChange.sink { todayPublications += 1 }
            let journalObservation = journal.objectWillChange.sink { journalPublications += 1 }
            defer {
                todayObservation.cancel()
                journalObservation.cancel()
            }

            CategoryPalette.saveCategory(name: "Shared", colorName: "#00FF00")

            XCTAssertEqual(todayPublications, 1)
            XCTAssertEqual(journalPublications, 1)
            XCTAssertEqual(today.timelineItems, originalTimeline)
            XCTAssertEqual(journal.days, originalDays)
            XCTAssertEqual(journal.dataRevision, originalRevision)
            XCTAssertEqual(store.externalReminderRescheduleGeneration, originalReminderGeneration)
        }
    }

    func testIdenticalColorSave_doesNotPublishPaletteOrStoreChanges() throws {
        try withPalette(["Shared": "#FF0000"]) {
            let store = makeStore()
            var palettePublications = 0
            var storePublications = 0
            let paletteObservation = CategoryPalette.changes.sink { palettePublications += 1 }
            let storeObservation = store.objectWillChange.sink { storePublications += 1 }
            defer {
                paletteObservation.cancel()
                storeObservation.cancel()
            }

            CategoryPalette.saveCategory(name: "Shared", colorName: "#FF0000")
            CategoryPalette.renameCategory(oldName: "Shared", newName: "Shared", colorName: "#FF0000")

            XCTAssertEqual(palettePublications, 0)
            XCTAssertEqual(storePublications, 0)
        }
    }

    private func makeStore() -> AppDataStore {
        AppDataStore(container: PersistenceController(inMemory: true).container,
                     startsBackgroundServices: false)
    }

    private func withPalette(_ palette: [String: String], operation: () throws -> Void) throws {
        let key = "CategoryPalette_Categories_V3"
        let defaults = UserDefaults.standard
        let sharedDefaults = try XCTUnwrap(UserDefaults(suiteName: PersistenceController.appGroupIdentifier))
        let originalValue = defaults.object(forKey: key)
        let originalSharedValue = sharedDefaults.object(forKey: key)
        defer {
            restore(originalValue, forKey: key, in: defaults)
            restore(originalSharedValue, forKey: key, in: sharedDefaults)
        }
        let data = try JSONEncoder().encode(palette)
        defaults.set(data, forKey: key)
        sharedDefaults.set(data, forKey: key)
        try operation()
    }

    private func restore(_ value: Any?, forKey key: String, in defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
