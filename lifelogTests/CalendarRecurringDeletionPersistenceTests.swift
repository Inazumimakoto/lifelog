import Combine
import SwiftData
import XCTest
@testable import lifelify

@MainActor
final class CalendarRecurringDeletionPersistenceTests: XCTestCase {
    func testWeeklyToDailyFutureSplit_deleteAllFromDailyOccurrenceWorksOnFirstAttempt() throws {
        let fixture = try makeSplit()
        let daily = try occurrence(in: fixture.store, seriesID: fixture.futureID, day: 19)
        let pendingTask = SDTask(domain: Task(title: "Unrelated pending task"))
        fixture.store.modelContext.insert(pendingTask)

        fixture.store.deleteCalendarSeries(containing: daily)

        try assertOnlyUnrelatedRemains(fixture)
        XCTAssertTrue(try ModelContext(fixture.store.modelContext.container).fetch(FetchDescriptor<SDTask>()).isEmpty)
        XCTAssertTrue(fixture.store.modelContext.insertedModelsArray.contains { ($0 as? SDTask)?.id == pendingTask.id })
        try fixture.store.modelContext.save()
        try assertOnlyUnrelatedRemains(fixture)
        withExtendedLifetime(fixture.registeredRows) {}
    }

    func testWeeklyToDailyFutureSplit_deleteAllFromOriginalPastOccurrenceAlsoRemovesDailyFuture() throws {
        let fixture = try makeSplit()
        let past = try occurrence(in: fixture.store, seriesID: fixture.originalID, day: 4)

        fixture.store.deleteCalendarSeries(containing: past)

        try assertOnlyUnrelatedRemains(fixture)
    }

    func testDeletePhysicalFutureSegment_removesFreshRowsAndExceptionsWithoutChangingPast() throws {
        let fixture = try makeSplit()
        let past = try occurrence(in: fixture.store, seriesID: fixture.originalID, day: 11)

        fixture.store.deleteCalendarEvent(fixture.futureID)

        XCTAssertEqual(Set(fixture.store.calendarEvents.map(\.id)), [fixture.originalID, fixture.unrelatedID])
        XCTAssertFalse(fixture.store.calendarExceptions.contains { $0.seriesID == fixture.futureID })
        XCTAssertEqual(Set(try storedEvents(fixture.store).map(\.id)), [fixture.originalID, fixture.unrelatedID])
        XCTAssertTrue(try storedExceptions(fixture.store).isEmpty)
        XCTAssertEqual(try occurrence(in: fixture.store, seriesID: fixture.originalID, day: 11), past)
    }

    func testBatchDeletion_savesAndPublishesEachCollectionAndReplansOnlyOnce() throws {
        let fixture = try makeSplit()
        var eventPublications = 0, exceptionPublications = 0, saves = 0
        let events = fixture.store.$calendarEvents.dropFirst().sink { _ in eventPublications += 1 }
        let exceptions = fixture.store.$calendarExceptions.dropFirst().sink { _ in exceptionPublications += 1 }
        let generation = fixture.store.externalReminderRescheduleGeneration

        try fixture.store.deleteCalendarEvents(withIDs: [fixture.originalID, fixture.futureID], save: { context in
            saves += 1
            try context.save()
        })

        XCTAssertEqual(saves, 1)
        XCTAssertEqual(eventPublications, 1)
        XCTAssertEqual(exceptionPublications, 1)
        XCTAssertEqual(fixture.store.externalReminderRescheduleGeneration, generation + 1)
        try assertOnlyUnrelatedRemains(fixture)
        withExtendedLifetime((events, exceptions)) {}
    }

    func testFailedDeletion_doesNotPublishOrRemovePersistedRowsAndCanRetry() throws {
        let fixture = try makeSplit()
        _ = fixture.store.events(on: date(19))
        let beforeEvents = fixture.store.calendarEvents
        let beforeExceptions = fixture.store.calendarExceptions
        let cache = fixture.store.eventsCache
        let generation = fixture.store.externalReminderRescheduleGeneration
        let pendingTask = SDTask(domain: Task(title: "Preserve pending edit"))
        fixture.store.modelContext.insert(pendingTask)

        XCTAssertThrowsError(try fixture.store.deleteCalendarEvents(withIDs: [fixture.originalID, fixture.futureID], save: { _ in
            throw SaveFailure.expected
        }))

        XCTAssertEqual(fixture.store.calendarEvents, beforeEvents)
        XCTAssertEqual(fixture.store.calendarExceptions, beforeExceptions)
        XCTAssertEqual(fixture.store.eventsCache, cache)
        XCTAssertEqual(fixture.store.externalReminderRescheduleGeneration, generation)
        XCTAssertEqual(Set(try storedEvents(fixture.store)), Set(beforeEvents))
        XCTAssertEqual(Set(try storedExceptions(fixture.store)), Set(beforeExceptions))
        XCTAssertTrue(fixture.store.modelContext.insertedModelsArray.contains { ($0 as? SDTask)?.id == pendingTask.id })
        fixture.store.deleteCalendarEvents(withIDs: [fixture.originalID, fixture.futureID])
        try assertOnlyUnrelatedRemains(fixture)
    }

    func testPendingTargetInsertion_isCancelledWithoutSavingUnrelatedTaskOrLaterResurrection() throws {
        let fixture = try makeSplit()
        let pending = CalendarEvent(title: "Unsaved target", startDate: date(4), endDate: date(4, hour: 10), calendarName: "Work",
                                    recurrenceRule: EventRecurrenceRule(frequency: .daily, timeZoneIdentifier: "UTC"))
        let exception = CalendarEventException(seriesID: pending.id, originalStartDate: pending.startDate)
        fixture.store.modelContext.insert(SDCalendarEvent(domain: pending))
        fixture.store.modelContext.insert(SDCalendarEventException(domain: exception))
        fixture.store.calendarEvents.append(pending)
        fixture.store.calendarExceptions.append(exception)
        let pendingTask = SDTask(domain: Task(title: "Keep pending task"))
        fixture.store.modelContext.insert(pendingTask)

        fixture.store.deleteCalendarEvents(withIDs: [pending.id])

        XCTAssertFalse(fixture.store.calendarEvents.contains { $0.id == pending.id })
        XCTAssertFalse(fixture.store.calendarExceptions.contains { $0.seriesID == pending.id })
        XCTAssertTrue(try ModelContext(fixture.store.modelContext.container).fetch(FetchDescriptor<SDTask>()).isEmpty)
        try fixture.store.modelContext.save()
        XCTAssertFalse(try storedEvents(fixture.store).contains { $0.id == pending.id })
        XCTAssertFalse(try storedExceptions(fixture.store).contains { $0.seriesID == pending.id })
        XCTAssertEqual(try ModelContext(fixture.store.modelContext.container).fetch(FetchDescriptor<SDTask>()).map(\.id), [pendingTask.id])
    }

    func testPendingTargetUpdate_cannotRecreateDeletedSegmentDuringLaterMainSave() throws {
        let fixture = try makeSplit()
        let pendingTarget = try XCTUnwrap(fixture.registeredRows.first { $0.id == fixture.futureID })
        pendingTarget.title = "Pending target change"
        let pendingTask = SDTask(domain: Task(title: "Unrelated pending task"))
        fixture.store.modelContext.insert(pendingTask)

        fixture.store.deleteCalendarEvents(withIDs: [fixture.futureID])
        try fixture.store.modelContext.save()

        XCTAssertEqual(Set(try storedEvents(fixture.store).map(\.id)), [fixture.originalID, fixture.unrelatedID])
        XCTAssertTrue(try storedExceptions(fixture.store).isEmpty)
        XCTAssertEqual(try ModelContext(fixture.store.modelContext.container).fetch(FetchDescriptor<SDTask>()).map(\.id), [pendingTask.id])
    }

    func testPendingMigratedExceptionWithOldRegisteredSeriesID_cannotSurviveFutureSegmentDeletion() throws {
        let fixture = try makeSplit()
        let pending = try XCTUnwrap(fixture.registeredExceptionRows.first)
        // The isolated split changed the persisted seriesID. A main-context
        // registration can still carry the original segment while edited.
        pending.seriesID = fixture.originalID
        var replacement = try XCTUnwrap(CalendarEventException(sd: pending).replacement)
        replacement.detail = "Pending change in a stale registration"
        pending.replacementData = try JSONEncoder().encode(replacement)

        fixture.store.deleteCalendarEvents(withIDs: [fixture.futureID])
        try fixture.store.modelContext.save()

        XCTAssertTrue(try storedExceptions(fixture.store).isEmpty)
        XCTAssertEqual(Set(try storedEvents(fixture.store).map(\.id)), [fixture.originalID, fixture.unrelatedID])
    }

    func testDeletingBothSplitSegments_survivesClosingAndReopeningSQLiteStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("recurring-delete-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.store")
        var unrelatedID: UUID?
        try autoreleasepool {
            let container = try diskContainer(url: url)
            let fixture = try makeSplit(container: container)
            unrelatedID = fixture.unrelatedID
            fixture.store.deleteCalendarSeries(containing: try occurrence(in: fixture.store, seriesID: fixture.futureID, day: 19))
            try assertOnlyUnrelatedRemains(fixture)
        }

        let reopened = try diskContainer(url: url)
        let events = try ModelContext(reopened).fetch(FetchDescriptor<SDCalendarEvent>())
        XCTAssertEqual(events.map(\.id), [try XCTUnwrap(unrelatedID)])
        XCTAssertTrue(try ModelContext(reopened).fetch(FetchDescriptor<SDCalendarEventException>()).isEmpty)
    }

    private enum SaveFailure: Error { case expected }

    private struct Fixture {
        let store: AppDataStore
        let originalID: UUID
        let futureID: UUID
        let unrelatedID: UUID
        let registeredRows: [SDCalendarEvent]
        let registeredExceptionRows: [SDCalendarEventException]
    }

    private func makeSplit(container: ModelContainer? = nil) throws -> Fixture {
        let container = container ?? PersistenceController(inMemory: true).container
        let context = container.mainContext
        context.autosaveEnabled = false
        let rule = EventRecurrenceRule(frequency: .weekly, weekdays: [2], timeZoneIdentifier: "UTC")
        let original = CalendarEvent(title: "Same title", startDate: date(4), endDate: date(4, hour: 10), calendarName: "Work",
                                     recurrenceRule: rule, urlString: "https://example.com/original")
        let unrelated = CalendarEvent(title: original.title, startDate: date(4), endDate: date(4, hour: 10), calendarName: "Work",
                                      recurrenceRule: rule, urlString: "https://example.com/unrelated")
        context.insert(SDCalendarEvent(domain: original))
        context.insert(SDCalendarEvent(domain: unrelated))
        try context.save()
        let store = AppDataStore(container: container, startsBackgroundServices: false,
                                 calendarNotificationService: NotificationService(requestHandler: { _ in }))
        var changed = try occurrence(in: store, seriesID: original.id, day: 25)
        changed.urlString = "https://example.com/changed-once"
        store.updateCalendarEvent(changed)
        let registeredExceptions = try context.fetch(FetchDescriptor<SDCalendarEventException>())
        let thirdWeek = try occurrence(in: store, seriesID: original.id, day: 18)
        var edited = thirdWeek
        edited.recurrenceRule = EventRecurrenceRule(frequency: .daily, timeZoneIdentifier: "UTC")
        let plan = try store.prepareCalendarEventEdit(original: thirdWeek, edited: edited, scope: .future)
        try store.applyCalendarEventEdit(plan)
        let future = try XCTUnwrap(store.calendarEvents.first { $0.recurrenceRule?.frequency == .daily })
        // Keep the same main-context registrations alive across deletion.
        let rows = try context.fetch(FetchDescriptor<SDCalendarEvent>())
        return Fixture(store: store, originalID: original.id, futureID: future.id, unrelatedID: unrelated.id,
                       registeredRows: rows, registeredExceptionRows: registeredExceptions)
    }

    private func assertOnlyUnrelatedRemains(_ fixture: Fixture, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(fixture.store.calendarEvents.map(\.id), [fixture.unrelatedID], file: file, line: line)
        XCTAssertTrue(fixture.store.calendarExceptions.isEmpty, file: file, line: line)
        XCTAssertEqual(try storedEvents(fixture.store).map(\.id), [fixture.unrelatedID], file: file, line: line)
        XCTAssertTrue(try storedExceptions(fixture.store).isEmpty, file: file, line: line)
        let reloaded = AppDataStore(container: fixture.store.modelContext.container, startsBackgroundServices: false)
        XCTAssertEqual(reloaded.calendarEvents.map(\.id), [fixture.unrelatedID], file: file, line: line)
    }

    private func occurrence(in store: AppDataStore, seriesID: UUID, day: Int) throws -> CalendarEvent {
        try XCTUnwrap(store.events(from: date(day, hour: 0), to: date(day + 1, hour: 0), calendar: calendar)
            .first { $0.occurrenceReference?.seriesID == seriesID })
    }

    private func storedEvents(_ store: AppDataStore) throws -> [CalendarEvent] {
        try ModelContext(store.modelContext.container).fetch(FetchDescriptor<SDCalendarEvent>()).map { CalendarEvent(sd: $0) }
    }

    private func storedExceptions(_ store: AppDataStore) throws -> [CalendarEventException] {
        try ModelContext(store.modelContext.container).fetch(FetchDescriptor<SDCalendarEventException>()).map { CalendarEventException(sd: $0) }
    }

    private func diskContainer(url: URL) throws -> ModelContainer {
        let schema = PersistenceController.localSchema
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2030, month: 3, day: day, hour: hour))!
    }
}
