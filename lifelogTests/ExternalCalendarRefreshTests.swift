import XCTest
import Combine
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
}
