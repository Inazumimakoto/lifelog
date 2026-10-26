import Combine
import SwiftData
import XCTest
@testable import lifelify

@MainActor
final class CalendarEventSeriesGroupDeletionTests: XCTestCase {
    func testWeeklyThreeWeeksThenFutureDaily_deleteAllFromOldSegmentRemovesFamilyOnFirstCall() async throws {
        try await assertDeleteAllAfterWeeklyToDaily(selectingOldSegment: true, reloadBeforeDeleting: false)
    }

    func testWeeklyThreeWeeksThenFutureDaily_deleteAllFromReloadedNewSegmentRemovesFamilyOnFirstCall() async throws {
        try await assertDeleteAllAfterWeeklyToDaily(selectingOldSegment: false, reloadBeforeDeleting: true)
    }

    func testRepeatedFrequencyAndTitleSplits_keepOneFamilyForDeleteAll() throws {
        let fixture = try makeSplitFixture()
        let store = fixture.store
        let dailyMaster = try XCTUnwrap(store.calendarEvents.first {
            $0.id != fixture.originalSeriesID && $0.id != fixture.unrelatedSeriesID
        })
        let original = try occurrence(in: store, seriesID: dailyMaster.id, originalStart: date(15))
        var edited = original
        edited.title = "Different title after another split"
        edited.recurrenceRule?.frequency = .weekly
        edited.recurrenceRule?.weekdays = [6]
        let plan = try store.prepareCalendarEventEdit(original: original, edited: edited, scope: .future)
        try store.applyCalendarEventEdit(plan)
        let familyMasters = store.calendarEvents.filter { $0.id != fixture.unrelatedSeriesID }
        XCTAssertEqual(familyMasters.count, 3)
        XCTAssertTrue(familyMasters.allSatisfy { $0.recurrenceRule?.seriesGroupID == fixture.originalSeriesID })
        let newest = try XCTUnwrap(familyMasters.first { $0.title == edited.title })
        let selected = try occurrence(in: store, seriesID: newest.id, originalStart: date(15))

        store.deleteCalendarSeries(containing: selected)

        XCTAssertEqual(store.calendarEvents.map(\.id), [fixture.unrelatedSeriesID])
        XCTAssertEqual(store.calendarExceptions.map(\.id), [fixture.unrelatedExceptionID])
        let context = ModelContext(store.modelContext.container)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SDCalendarEvent>()).map(\.id), [fixture.unrelatedSeriesID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<SDCalendarEventException>()).map(\.id), [fixture.unrelatedExceptionID])
    }

    func testLegacySameNamedSeriesWithoutGroup_deleteAllDoesNotInferRelationship() throws {
        let first = weeklySeries()
        let second = weeklySeries()
        let store = try makeStore(series: [first, second])
        XCTAssertNil(first.recurrenceRule?.seriesGroupID)
        XCTAssertNil(second.recurrenceRule?.seriesGroupID)
        let selected = try occurrence(in: store, seriesID: first.id, originalStart: date(4))

        store.deleteCalendarSeries(containing: selected)

        XCTAssertEqual(store.calendarEvents, [second])
        let reloaded = AppDataStore(container: store.modelContext.container, startsBackgroundServices: false)
        XCTAssertEqual(reloaded.calendarEvents, [second])
    }

    private func assertDeleteAllAfterWeeklyToDaily(selectingOldSegment: Bool, reloadBeforeDeleting: Bool) async throws {
        let fixture = try makeSplitFixture()
        let originalStore = fixture.store
        let persistedBefore = try ModelContext(originalStore.modelContext.container)
            .fetch(FetchDescriptor<SDCalendarEvent>()).map { CalendarEvent(sd: $0) }
        let familyIDs = Set(persistedBefore.filter { $0.id != fixture.unrelatedSeriesID }.map(\.id))
        XCTAssertEqual(familyIDs.count, 2)
        XCTAssertTrue(persistedBefore.filter { familyIDs.contains($0.id) }
            .allSatisfy { $0.recurrenceRule?.seriesGroupID == fixture.originalSeriesID })
        let store = reloadBeforeDeleting
            ? AppDataStore(container: originalStore.modelContext.container, startsBackgroundServices: false,
                           calendarNotificationService: NotificationService(requestHandler: { _ in }))
            : originalStore
        let selectedSeriesID = selectingOldSegment ? fixture.originalSeriesID
            : try XCTUnwrap(familyIDs.first { $0 != fixture.originalSeriesID })
        let selected = try occurrence(in: store, seriesID: selectedSeriesID,
                                      originalStart: selectingOldSegment ? date(4) : date(14))
        let list = EventsViewModel(store: store, referenceDate: date(11))
        let journal = JournalViewModel(store: store, anchorDate: date(11), baseCalendar: calendar)
        _ = list.allEvents
        _ = journal.calendarDays(for: date(11))
        let updated = expectation(description: "Deleting one family refreshes cached calendar")
        let observation = journal.$dataRevision.dropFirst().sink { _ in updated.fulfill() }

        // Exactly one delete action, regardless of which physical segment opened it.
        store.deleteCalendarSeries(containing: selected)
        await fulfillment(of: [updated], timeout: 2)
        await nextMainQueueTurn()

        XCTAssertEqual(store.calendarEvents.map(\.id), [fixture.unrelatedSeriesID])
        XCTAssertEqual(store.calendarExceptions.map(\.id), [fixture.unrelatedExceptionID])
        XCTAssertFalse(list.allEvents.contains { event in
            event.occurrenceReference.map { familyIDs.contains($0.seriesID) } ?? false
        })
        XCTAssertFalse(journal.calendarDays(for: date(11)).flatMap(\.events).contains { event in
            event.occurrenceReference.map { familyIDs.contains($0.seriesID) } ?? false
        })
        let context = ModelContext(store.modelContext.container)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SDCalendarEvent>()).map(\.id), [fixture.unrelatedSeriesID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<SDCalendarEventException>()).map(\.id), [fixture.unrelatedExceptionID])
        let shared = try CalendarEventStorageQuery.events(in: context, from: date(1, hour: 0), to: date(31, hour: 23), calendar: calendar)
        XCTAssertEqual(shared.map(\.startDate), [date(4), date(18)])
        let reloaded = AppDataStore(container: store.modelContext.container, startsBackgroundServices: false)
        XCTAssertEqual(reloaded.events(from: date(1, hour: 0), to: date(31, hour: 23), calendar: calendar), shared)
        withExtendedLifetime(observation) {}
    }

    private struct SplitFixture {
        let store: AppDataStore
        let originalSeriesID: UUID
        let unrelatedSeriesID: UUID
        let unrelatedExceptionID: UUID
    }

    private func makeSplitFixture() throws -> SplitFixture {
        let series = weeklySeries()
        // Identical title, time and URL never establish a relationship.
        let unrelated = weeklySeries()
        let unrelatedException = CalendarEventException(seriesID: unrelated.id, originalStartDate: date(11))
        let store = try makeStore(series: [series, unrelated], exceptions: [unrelatedException])
        var old = try occurrence(in: store, seriesID: series.id, originalStart: date(4))
        old.detail = "Old segment's individual memo"
        store.updateCalendarEvent(old)
        let selected = try occurrence(in: store, seriesID: series.id, originalStart: date(11))
        var edited = selected
        edited.recurrenceRule?.frequency = .daily
        edited.recurrenceRule?.interval = 1
        edited.recurrenceRule?.weekdays = []
        let plan = try store.prepareCalendarEventEdit(original: selected, edited: edited, scope: .future)
        try store.applyCalendarEventEdit(plan)
        let tail = try XCTUnwrap(store.calendarEvents.first { $0.id != series.id && $0.id != unrelated.id })
        store.deleteCalendarEvent(try occurrence(in: store, seriesID: tail.id, originalStart: date(13)))
        var changed = try occurrence(in: store, seriesID: tail.id, originalStart: date(15))
        changed.urlString = "https://example.com/individual"
        store.updateCalendarEvent(changed)
        return SplitFixture(store: store, originalSeriesID: series.id,
                            unrelatedSeriesID: unrelated.id, unrelatedExceptionID: unrelatedException.id)
    }

    private func makeStore(series: [CalendarEvent], exceptions: [CalendarEventException] = []) throws -> AppDataStore {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        context.autosaveEnabled = false
        for event in series { context.insert(SDCalendarEvent(domain: event)) }
        for exception in exceptions { context.insert(SDCalendarEventException(domain: exception)) }
        try context.save()
        return AppDataStore(container: persistence.container, startsBackgroundServices: false,
                            calendarNotificationService: NotificationService(requestHandler: { _ in }))
    }

    private func weeklySeries() -> CalendarEvent {
        CalendarEvent(title: "Same recurring name", startDate: date(4), endDate: date(4, hour: 10), calendarName: "Work",
                      recurrenceRule: EventRecurrenceRule(frequency: .weekly, weekdays: [2], until: date(18, hour: 0),
                                                          timeZoneIdentifier: "UTC"),
                      urlString: "https://example.com/same")
    }

    private func occurrence(in store: AppDataStore, seriesID: UUID, originalStart: Date) throws -> CalendarEvent {
        try XCTUnwrap(store.events(from: date(1, hour: 0), to: date(31, hour: 23), calendar: calendar).first {
            $0.occurrenceReference?.seriesID == seriesID && $0.occurrenceReference?.originalStartDate == originalStart
        })
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
