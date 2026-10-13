import XCTest
import Combine
import EventKit
import CoreGraphics
import SwiftData
@testable import lifelify

@MainActor
final class ExternalCalendarRefreshTests: XCTestCase {
    func testIdenticalRefresh_preservesDayCacheAndDoesNotPublishOrReschedule() {
        let store = AppDataStore(container: PersistenceController(inMemory: true).container,
                                 startsBackgroundServices: false)
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let event = CalendarEvent(title: "Meeting", startDate: day.addingTimeInterval(3_600),
                                  endDate: day.addingTimeInterval(7_200), calendarName: "Work")
        let range = ExternalCalendarRange(start: day, end: day.addingTimeInterval(86_400))
        store.externalCalendarEvents = [event]
        store.externalCalendarRange = range
        store.eventsCache[day] = [event]
        let generation = store.externalReminderRescheduleGeneration
        var publications = 0
        let observation = store.$externalCalendarEvents.dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel() }

        store.updateExternalCalendarEvents([event], range: range)

        XCTAssertEqual(publications, 0)
        XCTAssertEqual(store.eventsCache[day], [event])
        XCTAssertEqual(store.externalReminderRescheduleGeneration, generation)
    }

    func testReorderedRefresh_preservesAlreadySortedEventsAndDayCache() {
        let store = AppDataStore(container: PersistenceController(inMemory: true).container,
                                 startsBackgroundServices: false)
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let first = CalendarEvent(title: "First", startDate: day.addingTimeInterval(3_600),
                                  endDate: day.addingTimeInterval(7_200), calendarName: "Work")
        let second = CalendarEvent(title: "Second", startDate: day.addingTimeInterval(10_800),
                                   endDate: day.addingTimeInterval(14_400), calendarName: "Work")
        store.externalCalendarEvents = [first, second]
        store.eventsCache[day] = [first, second]
        var publications = 0
        let observation = store.$externalCalendarEvents.dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel() }

        store.updateExternalCalendarEvents([second, first])

        XCTAssertEqual(publications, 0)
        XCTAssertEqual(store.eventsCache[day], [first, second])
    }

    func testUnchangedCalendarLinks_doNotPublishAppState() {
        let store = AppDataStore(container: PersistenceController(inMemory: true).container,
                                 startsBackgroundServices: false)
        var publications = 0
        let observation = store.$appState.dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel() }

        store.updateCalendarLinks(with: [])

        XCTAssertEqual(publications, 0)
    }

    func testCalendarLinkCategoryChange_updatesOnlyMatchingSourceAndClearsDayCache() {
        let store = makeStore()
        let day = fixtureDay
        let linked = fixtureEvent(title: "Linked", source: "work")
        let otherCalendar = fixtureEvent(title: "Other", source: "personal")
        let legacyEvent = fixtureEvent(title: "Legacy", source: nil)
        let internalEvent = fixtureEvent(title: "Internal", source: nil)
        store.appState.calendarCategoryLinks = [fixtureLink(identifier: "work", category: "Work")]
        store.externalCalendarEvents = [linked, otherCalendar, legacyEvent]
        store.calendarEvents = [internalEvent]
        let range = ExternalCalendarRange(start: day, end: day.addingTimeInterval(86_400))
        store.externalCalendarRange = range
        store.eventsCache[day] = [linked, otherCalendar, legacyEvent, internalEvent]
        let generation = store.externalReminderRescheduleGeneration

        store.updateCalendarLinkCategory(calendarIdentifier: "work", categoryName: "My category")

        var expected = linked
        expected.calendarName = "My category"
        XCTAssertEqual(store.externalCalendarEvents.first(where: { $0.id == linked.id }), expected)
        XCTAssertEqual(store.externalCalendarEvents.first(where: { $0.id == otherCalendar.id }), otherCalendar)
        XCTAssertEqual(store.externalCalendarEvents.first(where: { $0.id == legacyEvent.id }), legacyEvent)
        XCTAssertEqual(store.calendarEvents, [internalEvent])
        XCTAssertNil(store.eventsCache[day])
        XCTAssertTrue(store.events(on: day).contains(expected))
        XCTAssertEqual(store.currentExternalCalendarRange(), range)
        XCTAssertEqual(store.externalReminderRescheduleGeneration, generation + 1)
    }

    func testCalendarLinkCategoryChange_hidesOnlyMatchingSourceImmediately() {
        let store = makeStore()
        let linked = fixtureEvent(title: "Linked", source: "work")
        let otherCalendar = fixtureEvent(title: "Other", source: "personal")
        let legacyEvent = fixtureEvent(title: "Legacy", source: nil)
        store.appState.calendarCategoryLinks = [fixtureLink(identifier: "work", category: "Work")]
        store.externalCalendarEvents = [linked, otherCalendar, legacyEvent]
        store.eventsCache[fixtureDay] = [linked, otherCalendar, legacyEvent]
        let generation = store.externalReminderRescheduleGeneration

        store.updateCalendarLinkCategory(calendarIdentifier: "work", categoryName: nil)

        XCTAssertNil(store.appState.calendarCategoryLinks.first?.categoryId)
        XCTAssertFalse(store.externalCalendarEvents.contains(where: { $0.id == linked.id }))
        XCTAssertEqual(Set(store.externalCalendarEvents), Set([otherCalendar, legacyEvent]))
        XCTAssertNil(store.eventsCache[fixtureDay])
        XCTAssertFalse(store.events(on: fixtureDay).contains(where: { $0.id == linked.id }))
        XCTAssertEqual(store.externalReminderRescheduleGeneration, generation + 1)
    }

    func testUnchangedCalendarLinkCategory_doesNotPublishPersistOrReschedule() throws {
        let store = makeStore()
        let event = fixtureEvent(title: "Linked", source: "work")
        store.appState.calendarCategoryLinks = [fixtureLink(identifier: "work", category: "Work")]
        store.externalCalendarEvents = [event]
        store.eventsCache[fixtureDay] = [event]
        let generation = store.externalReminderRescheduleGeneration
        var appStatePublications = 0
        var eventPublications = 0
        let stateObservation = store.$appState.dropFirst().sink { _ in appStatePublications += 1 }
        let eventObservation = store.$externalCalendarEvents.dropFirst().sink { _ in eventPublications += 1 }
        defer {
            stateObservation.cancel()
            eventObservation.cancel()
        }

        store.updateCalendarLinkCategory(calendarIdentifier: "work", categoryName: "Work")
        store.updateCalendarLinkCategory(calendarIdentifier: "missing", categoryName: "Work")

        XCTAssertEqual(appStatePublications, 0)
        XCTAssertEqual(eventPublications, 0)
        XCTAssertEqual(store.eventsCache[fixtureDay], [event])
        XCTAssertEqual(store.externalReminderRescheduleGeneration, generation)
        XCTAssertTrue(try store.modelContext.fetch(FetchDescriptor<SDAppState>()).isEmpty)
    }

    func testCalendarLinksRefresh_removesDeletedAndDuplicateLinksAndKeepsUserCategory() {
        let store = makeStore()
        let eventStore = EKEventStore()
        let existingCalendar = EKCalendar(for: .event, eventStore: eventStore)
        existingCalendar.title = "Updated calendar name"
        existingCalendar.cgColor = CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        let newCalendar = EKCalendar(for: .event, eventStore: eventStore)
        newCalendar.title = "旅行"
        store.appState.calendarCategoryLinks = [
            fixtureLink(identifier: existingCalendar.calendarIdentifier, category: "My category"),
            fixtureLink(identifier: "deleted-calendar", category: "Deleted category"),
            fixtureLink(identifier: existingCalendar.calendarIdentifier, category: "Duplicate category")
        ]

        store.updateCalendarLinks(with: [existingCalendar, existingCalendar, newCalendar])

        XCTAssertEqual(store.appState.calendarCategoryLinks.count, 2)
        let existingLink = store.appState.calendarCategoryLinks.first
        XCTAssertEqual(existingLink?.calendarIdentifier, existingCalendar.calendarIdentifier)
        XCTAssertEqual(existingLink?.calendarTitle, existingCalendar.title)
        XCTAssertEqual(existingLink?.colorHex, existingCalendar.cgColor?.hexString)
        XCTAssertEqual(existingLink?.categoryId, "My category")
        XCTAssertEqual(store.appState.calendarCategoryLinks.last?.categoryId, "旅行")
        XCTAssertFalse(store.appState.calendarCategoryLinks.contains(where: { $0.calendarIdentifier == "deleted-calendar" }))
    }

    func testCalendarLinksRefresh_preservesHiddenCategoryAndOrderWhenCalendarRenamed() {
        let store = makeStore()
        let eventStore = EKEventStore()
        let hiddenCalendar = EKCalendar(for: .event, eventStore: eventStore)
        hiddenCalendar.title = "Renamed work calendar"
        let visibleCalendar = EKCalendar(for: .event, eventStore: eventStore)
        visibleCalendar.title = "Personal calendar"
        store.appState.calendarCategoryLinks = [
            fixtureLink(identifier: hiddenCalendar.calendarIdentifier, category: nil),
            fixtureLink(identifier: visibleCalendar.calendarIdentifier, category: "My category")
        ]

        store.updateCalendarLinks(with: [visibleCalendar, hiddenCalendar])

        XCTAssertEqual(store.appState.calendarCategoryLinks.map(\.calendarIdentifier),
                       [hiddenCalendar.calendarIdentifier, visibleCalendar.calendarIdentifier])
        XCTAssertEqual(store.appState.calendarCategoryLinks.first?.calendarTitle, hiddenCalendar.title)
        XCTAssertNil(store.appState.calendarCategoryLinks.first?.categoryId)
        XCTAssertEqual(store.appState.calendarCategoryLinks.last?.categoryId, "My category")
    }

    func testDeletedCategoryFallback_movesAllLinkedAndInternalExternalEvents() throws {
        let store = makeStore()
        let fallback = "Remaining category"
        let internalEvent = fixtureEvent(title: "Internal", source: nil)
        var unrelatedInternal = fixtureEvent(title: "Unrelated internal", source: nil)
        unrelatedInternal.calendarName = "Other category"
        let firstExternal = fixtureEvent(title: "First external", source: "work")
        let secondExternal = fixtureEvent(title: "Second external", source: "personal")
        let legacyExternal = fixtureEvent(title: "Legacy external", source: nil)
        var unrelatedExternal = fixtureEvent(title: "Unrelated external", source: "other")
        unrelatedExternal.calendarName = "Other category"
        let internalEvents = [internalEvent, unrelatedInternal]
        let externalEvents = [firstExternal, secondExternal, legacyExternal, unrelatedExternal]
        store.calendarEvents = internalEvents
        store.externalCalendarEvents = externalEvents
        store.appState.calendarCategoryLinks = [
            fixtureLink(identifier: "work", category: "Work"),
            fixtureLink(identifier: "personal", category: "Work"),
            fixtureLink(identifier: "other", category: "Other category"),
            fixtureLink(identifier: "hidden", category: nil)
        ]
        let range = ExternalCalendarRange(start: fixtureDay, end: fixtureDay.addingTimeInterval(86_400))
        store.externalCalendarRange = range
        store.eventsCache[fixtureDay] = internalEvents + externalEvents
        let generation = store.externalReminderRescheduleGeneration
        let migrate: (CalendarEvent) -> CalendarEvent = { event in
            var updated = event
            if updated.calendarName == "Work" { updated.calendarName = fallback }
            return updated
        }

        // Category deletion uses the same migration after selecting a fallback.
        store.renameCalendarCategory(from: "Work", to: fallback)

        XCTAssertEqual(store.calendarEvents, internalEvents.map(migrate))
        XCTAssertEqual(store.externalCalendarEvents, externalEvents.map(migrate))
        XCTAssertEqual(store.appState.calendarCategoryLinks.map(\.categoryId),
                       [fallback, fallback, "Other category", nil])
        XCTAssertNil(store.eventsCache[fixtureDay])
        XCTAssertEqual(store.currentExternalCalendarRange(), range)
        XCTAssertEqual(store.externalReminderRescheduleGeneration, generation + 1)
        let persistedEvents = try store.modelContext.fetch(FetchDescriptor<SDCalendarEvent>())
        XCTAssertEqual(Set(persistedEvents.map { CalendarEvent(sd: $0) }), Set(internalEvents.map(migrate)))
        let persistedState = try store.modelContext.fetch(FetchDescriptor<SDAppState>()).first
        XCTAssertEqual(persistedState?.calendarCategoryLinks, store.appState.calendarCategoryLinks)
    }

    func testUnchangedEventsAfterReminderFires_replenishesPlanWithoutPublishingOrEvictingCache() {
        let store = AppDataStore(container: PersistenceController(inMemory: true).container,
                                 startsBackgroundServices: false)
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let first = CalendarEvent(title: "First", startDate: day.addingTimeInterval(3_600),
                                  endDate: day.addingTimeInterval(7_200), calendarName: "Work", reminderMinutes: 30)
        let second = CalendarEvent(title: "Second", startDate: day.addingTimeInterval(10_800),
                                   endDate: day.addingTimeInterval(14_400), calendarName: "Work", reminderMinutes: 30)
        store.externalCalendarEvents = [first, second]
        store.eventsCache[day] = [first, second]
        store.nextExternalReminderRefreshDate = first.startDate.addingTimeInterval(-30 * 60)
        let generation = store.externalReminderRescheduleGeneration
        var publications = 0
        let observation = store.$externalCalendarEvents.dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel() }

        store.updateExternalCalendarEvents([first, second], referenceDate: day.addingTimeInterval(900))
        XCTAssertEqual(store.externalReminderRescheduleGeneration, generation)
        store.updateExternalCalendarEvents([first, second], referenceDate: day.addingTimeInterval(1_800))

        XCTAssertEqual(store.externalReminderRescheduleGeneration, generation + 1)
        XCTAssertEqual(store.nextExternalReminderRefreshDate, second.startDate.addingTimeInterval(-30 * 60))
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(store.eventsCache[day], [first, second])
    }

    func testExpiredPlanWithNoRemainingReminders_doesNotRepeatedlyRescheduleUnchangedEvents() {
        let store = AppDataStore(container: PersistenceController(inMemory: true).container,
                                 startsBackgroundServices: false)
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let event = CalendarEvent(title: "Meeting", startDate: day.addingTimeInterval(3_600),
                                  endDate: day.addingTimeInterval(7_200), calendarName: "Work", reminderMinutes: 30)
        store.externalCalendarEvents = [event]
        store.nextExternalReminderRefreshDate = event.startDate.addingTimeInterval(-30 * 60)
        let generation = store.externalReminderRescheduleGeneration

        store.updateExternalCalendarEvents([event], referenceDate: day.addingTimeInterval(7_200))
        XCTAssertEqual(store.externalReminderRescheduleGeneration, generation + 1)
        XCTAssertNil(store.nextExternalReminderRefreshDate)
        store.updateExternalCalendarEvents([event], referenceDate: day.addingTimeInterval(10_800))

        XCTAssertEqual(store.externalReminderRescheduleGeneration, generation + 1)
    }

    private var fixtureDay: Date {
        Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private func makeStore() -> AppDataStore {
        AppDataStore(container: PersistenceController(inMemory: true).container,
                     startsBackgroundServices: false)
    }

    private func fixtureEvent(title: String, source: String?) -> CalendarEvent {
        CalendarEvent(title: title,
                      startDate: fixtureDay.addingTimeInterval(3_600),
                      endDate: fixtureDay.addingTimeInterval(7_200),
                      calendarName: "Work", sourceCalendarIdentifier: source)
    }

    private func fixtureLink(identifier: String, category: String?) -> CalendarCategoryLink {
        CalendarCategoryLink(calendarIdentifier: identifier, calendarTitle: "Old name",
                             categoryId: category, colorHex: nil)
    }
}
