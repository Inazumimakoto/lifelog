import Combine
import SwiftData
import XCTest
@testable import lifelify

@MainActor
final class CalendarEventScopedEditConsumerTests: XCTestCase {
    func testFutureEdit_prepareKeepsCachedSnapshotsAndApplyRefreshesCalendarAndList() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let series = CalendarEvent(
            title: "Original title", startDate: date(4), endDate: date(4, hour: 10), calendarName: "Work",
            recurrenceRule: EventRecurrenceRule(frequency: .weekly, weekdays: [2], timeZoneIdentifier: "UTC")
        )
        context.insert(SDCalendarEvent(domain: series))
        try context.save()
        let store = AppDataStore(container: persistence.container, startsBackgroundServices: false,
                                 calendarNotificationService: NotificationService(requestHandler: { _ in }))
        let journal = JournalViewModel(store: store, anchorDate: date(18), baseCalendar: calendar)
        let list = EventsViewModel(store: store, referenceDate: date(18))
        let before = journal.calendarDays(for: date(18))
        let original = try XCTUnwrap(store.events(from: date(18, hour: 0), to: date(19, hour: 0), calendar: calendar).first)
        let listBefore = list.allEvents
        let revision = journal.dataRevision
        var edited = original
        edited.title = "Future title"

        let plan = try store.prepareCalendarEventEdit(original: original, edited: edited, scope: .future)

        XCTAssertEqual(store.calendarEvents, [series])
        XCTAssertTrue(store.calendarExceptions.isEmpty)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(journal.calendarDays(for: date(18)), before)
        XCTAssertEqual(journal.dataRevision, revision)
        XCTAssertEqual(list.allEvents, listBefore)

        let refreshed = expectation(description: "Committed scoped edit refreshes the calendar")
        let observation = journal.$dataRevision.dropFirst().sink { _ in refreshed.fulfill() }
        try store.applyCalendarEventEdit(plan)
        await fulfillment(of: [refreshed], timeout: 2)
        await nextMainQueueTurn()

        let updated = journal.calendarDays(for: date(18))
        XCTAssertEqual(updated.first { calendar.isDate($0.date, inSameDayAs: date(4)) }?.events.first?.title,
                       "Original title")
        XCTAssertEqual(updated.first { calendar.isDate($0.date, inSameDayAs: date(18)) }?.events.first?.title,
                       "Future title")
        XCTAssertEqual(list.events(for: .past).first { $0.startDate == date(4) }?.title, "Original title")
        XCTAssertEqual(list.events(for: .today).first?.title, "Future title")
        XCTAssertNotEqual(list.allEvents, listBefore)
        withExtendedLifetime(observation) {}
    }

    func testFutureSplit_roundTripsCadenceAnchorAndURLsThroughSharedStorageQuery() throws {
        var rule = EventRecurrenceRule(frequency: .weekly, interval: 2, weekdays: [2, 5], timeZoneIdentifier: "UTC")
        rule.anchorDate = date(4)
        let series = CalendarEvent(title: "Original title", startDate: date(11), endDate: date(11, hour: 10),
                                   calendarName: "Work", recurrenceRule: rule,
                                   urlString: "https://example.com/original")
        let store = try makeStore(series: series)
        let rangeStart = date(11, hour: 0)
        let rangeEnd = calendar.date(byAdding: .month, value: 1, to: rangeStart)!
        let original = try XCTUnwrap(store.events(from: rangeStart, to: rangeEnd, calendar: calendar)
            .first { $0.occurrenceReference?.originalStartDate == date(21) })
        var edited = original
        edited.title = "Future title"
        edited.urlString = "https://example.com/future"

        let plan = try store.prepareCalendarEventEdit(original: original, edited: edited, scope: .future)
        try store.applyCalendarEventEdit(plan)

        let expected = store.events(from: rangeStart, to: rangeEnd, calendar: calendar)
        let storedContext = ModelContext(store.modelContext.container)
        let shared = try CalendarEventStorageQuery.events(in: storedContext, from: rangeStart, to: rangeEnd, calendar: calendar)
        let masters = try storedContext.fetch(FetchDescriptor<SDCalendarEvent>()).map { CalendarEvent(sd: $0) }
        let exceptions = try storedContext.fetch(FetchDescriptor<SDCalendarEventException>()).map { CalendarEventException(sd: $0) }
        let resolved = EventQuerying.resolved(internalEvents: masters, exceptions: exceptions, externalEvents: [],
                                              rangeStart: rangeStart, rangeEndExclusive: rangeEnd, calendar: calendar)
        XCTAssertEqual(shared, expected)
        XCTAssertEqual(resolved, expected)
        XCTAssertTrue(masters.contains { $0.recurrenceRule?.anchorDate != nil })
        XCTAssertEqual(expected.first?.startDate, date(18))
        XCTAssertEqual(expected.first?.urlString, series.urlString)
        XCTAssertTrue(expected.dropFirst().allSatisfy { $0.urlString == edited.urlString })
        XCTAssertEqual(expected.count, 4)
    }

    func testAllDayFutureSplit_preservesSourceDateLabelsAndURLAcrossDisplayZones() throws {
        var sourceCalendar = calendar
        sourceCalendar.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!
        var displayCalendar = calendar
        displayCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        func sourceDate(_ day: Int) -> Date {
            sourceCalendar.date(from: DateComponents(year: 2030, month: 3, day: day))!
        }
        let series = CalendarEvent(
            title: "All-day original", startDate: sourceDate(4), endDate: sourceDate(5), calendarName: "Work",
            isAllDay: true, dateOnlyTimeZoneIdentifier: sourceCalendar.timeZone.identifier,
            recurrenceRule: EventRecurrenceRule(frequency: .weekly, weekdays: [2],
                                                timeZoneIdentifier: sourceCalendar.timeZone.identifier),
            urlString: "https://example.com/original"
        )
        let store = try makeStore(series: series)
        let rangeStart = displayCalendar.date(from: DateComponents(year: 2030, month: 3, day: 1))!
        let rangeEnd = displayCalendar.date(from: DateComponents(year: 2030, month: 4, day: 2))!
        let original = try XCTUnwrap(store.events(from: rangeStart, to: rangeEnd, calendar: displayCalendar)
            .first { $0.occurrenceReference?.originalStartDate == sourceDate(18) })
        var edited = original
        edited.title = "All-day future"
        edited.urlString = "https://example.com/future"

        let plan = try store.prepareCalendarEventEdit(original: original, edited: edited, scope: .future)
        try store.applyCalendarEventEdit(plan)

        let expected = store.events(from: rangeStart, to: rangeEnd, calendar: displayCalendar)
        let stored = try CalendarEventStorageQuery.events(in: ModelContext(store.modelContext.container),
                                                          from: rangeStart, to: rangeEnd, calendar: displayCalendar)
        XCTAssertEqual(stored, expected)
        XCTAssertEqual(expected.map { displayCalendar.component(.day, from: $0.displayStartDate(calendar: displayCalendar)) },
                       [4, 11, 18, 25, 1])
        XCTAssertTrue(expected.allSatisfy { $0.dateOnlyTimeZoneIdentifier == sourceCalendar.timeZone.identifier })
        XCTAssertTrue(expected.prefix(2).allSatisfy { $0.urlString == series.urlString })
        XCTAssertTrue(expected.dropFirst(2).allSatisfy { $0.urlString == edited.urlString })
    }

    func testScopedApplyThenOrdinaryMutations_doesNotReviveStaleRegisteredRows() throws {
        let series = CalendarEvent(
            title: "Original title", startDate: date(4), endDate: date(4, hour: 10), calendarName: "Work",
            recurrenceRule: EventRecurrenceRule(frequency: .weekly, weekdays: [2], timeZoneIdentifier: "UTC"),
            urlString: "https://example.com/default"
        )
        let store = try makeStore(series: series)
        let start = date(1, hour: 0)
        let end = date(31, hour: 23)
        var individual = try XCTUnwrap(store.events(from: start, to: end, calendar: calendar)
            .first { $0.startDate == date(25) })
        individual.urlString = "https://example.com/individual"
        store.updateCalendarEvent(individual)
        let original = try XCTUnwrap(store.events(from: start, to: end, calendar: calendar)
            .first { $0.startDate == date(11) })
        var edited = original
        edited.title = "Future title"
        let plan = try store.prepareCalendarEventEdit(original: original, edited: edited, scope: .future)
        let pending = SDTask(domain: Task(title: "Unrelated pending task"))
        store.modelContext.insert(pending)

        try store.applyCalendarEventEdit(plan)

        XCTAssertTrue(try store.modelContext.fetch(FetchDescriptor<SDTask>()).contains { $0.id == pending.id })
        XCTAssertTrue(try ModelContext(store.modelContext.container).fetch(FetchDescriptor<SDTask>()).isEmpty)
        var future = try XCTUnwrap(store.calendarEvents.first { $0.title == "Future title" })
        future.detail = "A later ordinary master edit"
        store.updateCalendarEvent(future)
        var migrated = try XCTUnwrap(store.events(from: start, to: end, calendar: calendar)
            .first { $0.startDate == date(25) })
        migrated.detail = "A later ordinary occurrence edit"
        store.updateCalendarEvent(migrated)
        XCTAssertEqual(try sharedEvents(in: store, from: start, to: end),
                       store.events(from: start, to: end, calendar: calendar))

        store.restoreCalendarException(try XCTUnwrap(store.calendarExceptions.first))
        XCTAssertEqual(try sharedEvents(in: store, from: start, to: end),
                       store.events(from: start, to: end, calendar: calendar))
        store.deleteCalendarSeries(containing: future)
        let remaining = try sharedEvents(in: store, from: start, to: end)
        XCTAssertTrue(remaining.isEmpty)
        let reloaded = AppDataStore(container: store.modelContext.container, startsBackgroundServices: false)
        XCTAssertEqual(reloaded.events(from: start, to: end, calendar: calendar), remaining)
    }

    private func makeStore(series: CalendarEvent) throws -> AppDataStore {
        let persistence = PersistenceController(inMemory: true)
        persistence.container.mainContext.autosaveEnabled = false
        persistence.container.mainContext.insert(SDCalendarEvent(domain: series))
        try persistence.container.mainContext.save()
        return AppDataStore(container: persistence.container, startsBackgroundServices: false,
                            calendarNotificationService: NotificationService(requestHandler: { _ in }))
    }

    private func sharedEvents(in store: AppDataStore, from start: Date, to end: Date) throws -> [CalendarEvent] {
        try CalendarEventStorageQuery.events(in: ModelContext(store.modelContext.container),
                                             from: start, to: end, calendar: calendar)
    }

    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private func date(_ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2030, month: 3, day: day, hour: hour))!
    }

    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
