import Combine
import SwiftData
import XCTest
@testable import lifelify

@MainActor
final class CalendarRecurrenceMutationPerformanceTests: XCTestCase {
    func testSkippingSevenDayWeek_savesAndPublishesOnceAndRetainsFollowingWeek() throws {
        let series = dailySeries()
        let store = try makeStore(series: [series])
        let selected = try XCTUnwrap(weekOccurrences(in: store).first)
        let day = Calendar.current.startOfDay(for: selected.startDate)
        store.eventsCache[day] = [selected]
        var publications = 0
        var saves = 0
        let publication = store.$calendarExceptions.dropFirst().sink { _ in publications += 1 }
        let save = NotificationCenter.default.publisher(for: ModelContext.didSave, object: store.modelContext)
            .sink { _ in saves += 1 }
        let previousGeneration = store.externalReminderRescheduleGeneration

        store.skipCalendarWeek(containing: selected, calendar: calendar)

        XCTAssertEqual(publications, 1)
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(store.externalReminderRescheduleGeneration, previousGeneration + 1)
        XCTAssertEqual(store.calendarExceptions.count, 7)
        XCTAssertTrue(store.eventsCache.isEmpty)
        XCTAssertTrue(weekOccurrences(in: store).isEmpty)
        XCTAssertEqual(store.events(from: date(11, hour: 0), to: date(18, hour: 0), calendar: calendar).count, 7)
        XCTAssertEqual(try persistedExceptions(in: store).count, 7)

        // Repeating the operation is a persistence retry, not another UI update.
        store.eventsCache[day] = []
        store.skipCalendarWeek(containing: selected, calendar: calendar)
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(store.eventsCache[day], [])
        XCTAssertEqual(store.externalReminderRescheduleGeneration, previousGeneration + 1)
        withExtendedLifetime((publication, save)) {}
    }

    func testEqualExceptionWrite_preservesCacheAndDoesNotPublishSaveOrReplan() throws {
        let series = dailySeries()
        let exception = CalendarEventException(seriesID: series.id, originalStartDate: date(4))
        let store = try makeStore(series: [series], exceptions: [exception])
        let day = Calendar.current.startOfDay(for: date(4))
        store.eventsCache[day] = []
        var publications = 0
        var saves = 0
        let publication = store.$calendarExceptions.dropFirst().sink { _ in publications += 1 }
        let save = NotificationCenter.default.publisher(for: ModelContext.didSave, object: store.modelContext)
            .sink { _ in saves += 1 }
        let generation = store.externalReminderRescheduleGeneration

        store.saveCalendarException(seriesID: series.id, originalStart: date(4), replacement: nil)

        XCTAssertEqual(publications, 0)
        XCTAssertEqual(saves, 0)
        XCTAssertEqual(store.eventsCache[day], [])
        XCTAssertFalse(store.modelContext.hasChanges)
        XCTAssertEqual(store.externalReminderRescheduleGeneration, generation)
        XCTAssertEqual(try persistedExceptions(in: store), [exception])
        withExtendedLifetime((publication, save)) {}
    }

    func testExceptionRetry_memoryAlreadyUpdatedInsertsOneStableRowWithoutPublishing() throws {
        let series = dailySeries()
        let store = try makeStore(series: [series])
        let exception = CalendarEventException(seriesID: series.id, originalStartDate: date(4))
        store.calendarExceptions = [exception]
        var publications = 0
        let publication = store.$calendarExceptions.dropFirst().sink { _ in publications += 1 }
        let generation = store.externalReminderRescheduleGeneration

        store.saveCalendarException(seriesID: series.id, originalStart: date(4), replacement: nil)
        store.saveCalendarException(seriesID: series.id, originalStart: date(4), replacement: nil)

        XCTAssertEqual(publications, 0)
        XCTAssertEqual(store.calendarExceptions, [exception])
        XCTAssertEqual(try persistedExceptions(in: store), [exception])
        XCTAssertEqual(store.externalReminderRescheduleGeneration, generation)
        withExtendedLifetime(publication) {}
    }

    func testExceptionRetry_equalMemorySnapshotSavesPendingRowWithoutPublishing() throws {
        let series = dailySeries()
        let store = try makeStore(series: [series])
        store.modelContext.autosaveEnabled = false
        let exception = CalendarEventException(seriesID: series.id, originalStartDate: date(4))
        store.modelContext.insert(SDCalendarEventException(domain: exception))
        store.calendarExceptions = [exception]
        XCTAssertTrue(store.modelContext.hasChanges)
        var publications = 0
        let publication = store.$calendarExceptions.dropFirst().sink { _ in publications += 1 }

        store.saveCalendarException(seriesID: series.id, originalStart: date(4), replacement: nil)

        XCTAssertFalse(store.modelContext.hasChanges)
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(try persistedExceptions(in: store), [exception])
        withExtendedLifetime(publication) {}
    }

    func testWeekSkip_replacesChangedSlotsOnceAndKeepsOtherExceptions() throws {
        let series = dailySeries()
        let otherSeries = dailySeries(title: "Other series")
        let cancelled = CalendarEventException(seriesID: series.id, originalStartDate: date(4))
        let replacement = CalendarEvent(title: "Changed occurrence", startDate: date(5, hour: 15),
                                        endDate: date(5, hour: 16), calendarName: "Work",
                                        urlString: "https://example.com/changed")
        let changed = CalendarEventException(seriesID: series.id, originalStartDate: date(5), replacement: replacement)
        let later = CalendarEventException(seriesID: series.id, originalStartDate: date(18))
        let other = CalendarEventException(seriesID: otherSeries.id, originalStartDate: date(4))
        let store = try makeStore(series: [series, otherSeries], exceptions: [cancelled, changed, later, other])
        let selected = try XCTUnwrap(weekOccurrences(in: store).first { $0.occurrenceReference?.seriesID == series.id })
        var publications = 0
        let publication = store.$calendarExceptions.dropFirst().sink { _ in publications += 1 }

        store.skipCalendarWeek(containing: selected, calendar: calendar)

        XCTAssertEqual(publications, 1)
        XCTAssertEqual(store.calendarExceptions.first { $0.id == cancelled.id }, cancelled)
        XCTAssertNil(store.calendarExceptions.first { $0.id == changed.id }?.replacement)
        XCTAssertEqual(store.calendarExceptions.first { $0.id == later.id }, later)
        XCTAssertEqual(store.calendarExceptions.first { $0.id == other.id }, other)
        let targetWeek = weekOccurrences(in: store).filter { $0.occurrenceReference?.seriesID == series.id }
        XCTAssertTrue(targetWeek.isEmpty)
        XCTAssertFalse(weekOccurrences(in: store).filter { $0.occurrenceReference?.seriesID == otherSeries.id }.isEmpty)
        let persisted = try persistedExceptions(in: store)
        XCTAssertEqual(persisted.count, 9)
        XCTAssertEqual(Set(persisted.map(\.occurrenceReference)).count, persisted.count)
        withExtendedLifetime(publication) {}
    }

    func testURLAndDetailOnlyOverrideAndRestore_keepReminderPlan() throws {
        var series = dailySeries()
        series.reminderDate = series.startDate.addingTimeInterval(-1_800)
        let store = try makeStore(series: [series])
        var selected = try XCTUnwrap(weekOccurrences(in: store).first { $0.startDate == date(5) })
        let generation = store.externalReminderRescheduleGeneration
        selected.urlString = "https://example.com/book"
        selected.detail = "New memo only"

        store.updateCalendarEvent(selected)

        XCTAssertEqual(store.externalReminderRescheduleGeneration, generation)
        let exception = try XCTUnwrap(store.calendarExceptions.first)
        XCTAssertEqual(exception.replacement?.urlString, selected.urlString)
        XCTAssertEqual(exception.replacement?.reminderDate, selected.reminderDate)
        store.restoreCalendarException(exception)
        XCTAssertEqual(store.externalReminderRescheduleGeneration, generation)
        XCTAssertTrue(store.calendarExceptions.isEmpty)
    }

    func testDuplicateLogicalExceptionRows_areReconciledWithoutLosingStableIdentity() throws {
        let series = dailySeries()
        let retained = CalendarEventException(seriesID: series.id, originalStartDate: date(4))
        let duplicate = CalendarEventException(seriesID: series.id, originalStartDate: date(4))
        let store = try makeStore(series: [series], exceptions: [retained, duplicate])
        store.calendarExceptions = [retained]

        store.saveCalendarException(seriesID: series.id, originalStart: date(4), replacement: nil)

        XCTAssertEqual(store.calendarExceptions, [retained])
        XCTAssertEqual(try persistedExceptions(in: store), [retained])
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

    private func persistedExceptions(in store: AppDataStore) throws -> [CalendarEventException] {
        try ModelContext(store.modelContext.container).fetch(FetchDescriptor<SDCalendarEventException>())
            .map { CalendarEventException(sd: $0) }
    }

    private func weekOccurrences(in store: AppDataStore) -> [CalendarEvent] {
        store.events(from: date(4, hour: 0), to: date(11, hour: 0), calendar: calendar)
    }

    private func dailySeries(title: String = "Daily") -> CalendarEvent {
        CalendarEvent(title: title, startDate: date(4), endDate: date(4, hour: 10), calendarName: "Work",
                      recurrenceRule: EventRecurrenceRule(frequency: .daily, timeZoneIdentifier: "UTC"))
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2030, month: 3, day: day, hour: hour))!
    }
}
