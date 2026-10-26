import Combine
import SwiftData
import XCTest
@testable import lifelify

@MainActor
final class CalendarRecurrenceConsumerTests: XCTestCase {
    func testSharedStorageQuery_oldSeriesAndCancelledOccurrenceMatchAppResults() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let series = weeklySeries(start: date(2020, 11, 2, hour: 9))
        let cancelledStart = date(2026, 11, 9, hour: 9)
        context.insert(SDCalendarEvent(domain: series))
        context.insert(SDCalendarEventException(domain: CalendarEventException(
            seriesID: series.id, originalStartDate: cancelledStart
        )))
        try context.save()
        let store = AppDataStore(container: persistence.container, startsBackgroundServices: false)
        let start = date(2026, 11, 2)
        let end = date(2026, 11, 17)

        let stored = try CalendarEventStorageQuery.events(in: context, from: start, to: end, calendar: calendar)
        let inApp = store.events(from: start, to: end, calendar: calendar)

        XCTAssertEqual(stored, inApp)
        XCTAssertEqual(stored.map(\.startDate), [date(2026, 11, 2, hour: 9), date(2026, 11, 16, hour: 9)])
        XCTAssertTrue(stored.allSatisfy { $0.occurrenceReference?.seriesID == series.id })
    }

    func testSharedStorageQuery_replacementMovedFromOutsideWindowIsIncluded() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let series = weeklySeries(start: date(2020, 11, 2, hour: 9))
        let original = date(2026, 11, 30, hour: 9)
        let replacement = CalendarEvent(
            title: "Moved meeting", startDate: date(2026, 11, 3, hour: 15),
            endDate: date(2026, 11, 3, hour: 16), calendarName: "Work"
        )
        context.insert(SDCalendarEvent(domain: series))
        context.insert(SDCalendarEventException(domain: CalendarEventException(
            seriesID: series.id, originalStartDate: original, replacement: replacement
        )))
        try context.save()

        let events = try CalendarEventStorageQuery.events(
            in: context, from: date(2026, 11, 3), to: date(2026, 11, 4), calendar: calendar
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.title, "Moved meeting")
        XCTAssertEqual(events.first?.occurrenceReference?.originalStartDate, original)
        let originalDay = try CalendarEventStorageQuery.events(
            in: context, from: date(2026, 11, 30), to: date(2026, 12, 1), calendar: calendar
        )
        XCTAssertTrue(originalDay.isEmpty)
    }

    func testExceptionChange_invalidatesCachedMonthAndDetail() async throws {
        let store = PerformanceTestStore.make()
        let day = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
        var series = weeklySeries(start: start)
        series.recurrenceRule?.weekdays = [Calendar.current.component(.weekday, from: start)]
        series.recurrenceRule?.timeZoneIdentifier = Calendar.current.timeZone.identifier
        store.addCalendarEvent(series)
        let viewModel = JournalViewModel(store: store, anchorDate: day)
        let occurrence = try XCTUnwrap(viewModel.calendarDetailSnapshot(for: day).events.first)
        XCTAssertEqual(viewModel.calendarDays(for: day).first { $0.date == day }?.events.count, 1)
        let invalidated = expectation(description: "Recurrence exception invalidates calendar")
        let observation = viewModel.$dataRevision.dropFirst().sink { _ in invalidated.fulfill() }

        store.deleteCalendarEvent(occurrence)
        await fulfillment(of: [invalidated], timeout: 2)

        XCTAssertTrue(viewModel.calendarDetailSnapshot(for: day).events.isEmpty)
        XCTAssertEqual(viewModel.calendarDays(for: day).first { $0.date == day }?.events.count, 0)
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: day)!
        XCTAssertEqual(viewModel.calendarDetailSnapshot(for: nextWeek).events.count, 1)
        withExtendedLifetime(observation) {}
    }

    func testEventList_extendableRecurrencesPreserveAllOrdinaryHistory() {
        let store = PerformanceTestStore.make()
        let now = date(2026, 11, 2)
        let old = CalendarEvent(title: "Old saved event", startDate: date(2010, 1, 1, hour: 9),
                                endDate: date(2010, 1, 1, hour: 10), calendarName: "Work")
        let future = CalendarEvent(title: "Future saved event", startDate: date(2040, 1, 1, hour: 9),
                                   endDate: date(2040, 1, 1, hour: 10), calendarName: "Work")
        let series = weeklySeries(start: date(2020, 11, 2, hour: 9))
        store.calendarEvents = [old, future, series]
        let viewModel = EventsViewModel(store: store, referenceDate: now)
        let initial = viewModel.allEvents

        XCTAssertTrue(initial.contains { $0.id == old.id })
        XCTAssertTrue(initial.contains { $0.id == future.id })
        XCTAssertTrue(initial.contains { $0.occurrenceReference != nil })
        XCTAssertFalse(initial.contains { $0.id == series.id })
        viewModel.loadMoreUpcomingEvents()
        let extendedFuture = viewModel.allEvents
        XCTAssertGreaterThan(extendedFuture.count, initial.count)
        viewModel.loadMorePastEvents()
        XCTAssertGreaterThan(viewModel.allEvents.count, extendedFuture.count)
        XCTAssertTrue(Set(initial.map(\.id)).isSubset(of: Set(viewModel.allEvents.map(\.id))))
    }

    func testEventList_cachedSectionReadsStaySilentAndSourceChangesRefreshContent() async {
        let store = PerformanceTestStore.make()
        var series = weeklySeries(start: date(2020, 11, 2, hour: 9))
        store.calendarEvents = [series]
        let viewModel = EventsViewModel(store: store, referenceDate: date(2026, 11, 2))
        let original = viewModel.allEvents
        var publications = 0
        let observation = viewModel.objectWillChange.sink { publications += 1 }

        for section in EventsViewModel.EventSection.allCases {
            _ = viewModel.events(for: section)
        }
        XCTAssertEqual(viewModel.allEvents, original)
        XCTAssertEqual(publications, 0)
        observation.cancel()

        let skipped = CalendarEventException(seriesID: series.id, originalStartDate: date(2026, 11, 2, hour: 9))
        store.calendarExceptions = [skipped]
        await nextMainQueueTurn()
        XCTAssertEqual(viewModel.allEvents.count, original.count - 1)
        XCTAssertFalse(viewModel.allEvents.contains { $0.id == skipped.occurrenceReference.occurrenceID })

        let external = CalendarEvent(title: "External", startDate: date(2026, 11, 2, hour: 12),
                                     endDate: date(2026, 11, 2, hour: 13), calendarName: "Work",
                                     sourceCalendarIdentifier: "external")
        store.externalCalendarEvents = [external]
        await nextMainQueueTurn()
        XCTAssertTrue(viewModel.allEvents.contains { $0.id == external.id })

        series.title = "Renamed series"
        store.calendarEvents = [series]
        await nextMainQueueTurn()
        XCTAssertTrue(viewModel.allEvents.filter { $0.occurrenceReference != nil }
            .allSatisfy { $0.title == "Renamed series" })
        XCTAssertFalse(viewModel.allEvents.contains { $0.id == skipped.occurrenceReference.occurrenceID })
    }

    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func weeklySeries(start: Date) -> CalendarEvent {
        CalendarEvent(
            title: "Weekly meeting", startDate: start, endDate: start.addingTimeInterval(3_600),
            calendarName: "Work", recurrenceRule: EventRecurrenceRule(
                frequency: .weekly, weekdays: [2], timeZoneIdentifier: "GMT"
            )
        )
    }
}
