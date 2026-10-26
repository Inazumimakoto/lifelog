import SwiftData
import XCTest
@testable import lifelify

@MainActor
final class CalendarEventScopedEditingTests: XCTestCase {
    func testFutureTitleEdit_keepsPastAndBiweeklyPhase() throws {
        let series = weeklySeries(interval: 2, weekdays: [2, 4])
        let store = try makeStore(series: series)
        let original = try occurrence(in: store, at: date(6))
        var edited = original
        edited.title = "Future title"

        let plan = try store.prepareCalendarEventEdit(original: original, edited: edited, scope: .future)
        try store.applyCalendarEventEdit(plan)

        let events = occurrences(in: store)
        XCTAssertEqual(events.map(\.startDate), [date(4), date(6), date(18), date(20)])
        XCTAssertEqual(events.first?.title, series.title)
        XCTAssertTrue(events.dropFirst().allSatisfy { $0.title == "Future title" })
        XCTAssertEqual(store.calendarEvents.count, 2)
    }

    func testSeriesDateAndTimeEdit_rebasesHistoricalMasterInsteadOfStartingAtSelectedDate() throws {
        let store = try makeStore(series: weeklySeries())
        let original = try occurrence(in: store, at: date(18))
        var edited = original
        edited.startDate = date(19, hour: 10)
        edited.endDate = date(19, hour: 11)
        edited.recurrenceRule?.weekdays = [3]

        let plan = try store.prepareCalendarEventEdit(original: original, edited: edited, scope: .series)
        try store.applyCalendarEventEdit(plan)

        XCTAssertEqual(store.calendarEvents.first?.startDate, date(5, hour: 10))
        XCTAssertEqual(occurrences(in: store).map(\.startDate),
                       [date(5, hour: 10), date(12, hour: 10), date(19, hour: 10), date(26, hour: 10)])
    }

    func testSeriesTitleEditFromURLOverride_preservesDefaultAndIndividualURLs() throws {
        var series = weeklySeries()
        series.urlString = "https://example.com/default"
        let store = try makeStore(series: series)
        var individual = try occurrence(in: store, at: date(11))
        individual.urlString = "https://example.com/individual"
        store.updateCalendarEvent(individual)
        let original = try occurrence(in: store, at: date(11))
        var edited = original
        edited.title = "New title for the series"

        let plan = try store.prepareCalendarEventEdit(original: original, edited: edited, scope: .series)
        try store.applyCalendarEventEdit(plan)

        XCTAssertEqual(store.calendarEvents.first?.urlString, series.urlString)
        XCTAssertEqual(try occurrence(in: store, at: date(4)).urlString, series.urlString)
        let changedIndividual = try occurrence(in: store, at: date(11))
        XCTAssertEqual(changedIndividual.title, edited.title)
        XCTAssertEqual(changedIndividual.urlString, individual.urlString)
    }

    func testSeriesAbsoluteReminderEdit_rebasesAlarmOntoHistoricalTemplateDate() throws {
        let store = try makeStore(series: weeklySeries())
        let original = try occurrence(in: store, at: date(18))
        var edited = original
        edited.reminderMinutes = nil
        edited.reminderDate = date(18, hour: 7)

        let plan = try store.prepareCalendarEventEdit(original: original, edited: edited, scope: .series)
        try store.applyCalendarEventEdit(plan)

        XCTAssertEqual(store.calendarEvents.first?.reminderDate, date(4, hour: 7))
        XCTAssertEqual(try occurrence(in: store, at: date(11)).reminderDate, date(11, hour: 7))
        XCTAssertEqual(try occurrence(in: store, at: date(18)).reminderDate, edited.reminderDate)
    }

    func testCompatibleExceptions_newTimeRemapsSlotsAndPreservesIndividualFields() throws {
        var series = weeklySeries()
        series.urlString = "https://example.com/default"
        let store = try makeStore(series: series)
        store.deleteCalendarEvent(try occurrence(in: store, at: date(11)))
        var changed = try occurrence(in: store, at: date(18))
        changed.title = "Individual title"
        changed.startDate = date(18, hour: 12)
        changed.endDate = date(18, hour: 13)
        changed.urlString = "https://example.com/individual"
        store.updateCalendarEvent(changed)
        let original = try occurrence(in: store, at: date(4))
        var edited = original
        edited.startDate = date(4, hour: 10)
        edited.endDate = date(4, hour: 11)

        let plan = try store.prepareCalendarEventEdit(original: original, edited: edited, scope: .series)
        XCTAssertTrue(plan.unmatchedExceptions.isEmpty)
        try store.applyCalendarEventEdit(plan)

        XCTAssertEqual(Set(store.calendarExceptions.map(\.originalStartDate)), [date(11, hour: 10), date(18, hour: 10)])
        XCTAssertFalse(occurrences(in: store).contains { $0.startDate == date(11, hour: 10) })
        let individual = try XCTUnwrap(occurrences(in: store).first { $0.title == "Individual title" })
        XCTAssertEqual(individual.startDate, changed.startDate)
        XCTAssertEqual(individual.urlString, changed.urlString)
    }

    func testUnmatchedExceptions_prepareDoesNotMutateAndAcceptedReviewKeepsChangedOccurrenceAsSingle() throws {
        let store = try makeStore(series: weeklySeries())
        store.deleteCalendarEvent(try occurrence(in: store, at: date(11)))
        var individual = try occurrence(in: store, at: date(18))
        individual.title = "Keep this original content"
        individual.urlString = "https://example.com/keep"
        store.updateCalendarEvent(individual)
        let original = try occurrence(in: store, at: date(4))
        var edited = original
        edited.recurrenceRule?.weekdays = [4]
        let beforeEvents = store.calendarEvents
        let beforeExceptions = store.calendarExceptions

        let plan = try store.prepareCalendarEventEdit(original: original, edited: edited, scope: .series)

        XCTAssertEqual(plan.unmatchedExceptions.count, 2)
        XCTAssertEqual(store.calendarEvents, beforeEvents)
        XCTAssertEqual(store.calendarExceptions, beforeExceptions)
        try store.applyCalendarEventEdit(plan)
        let standalone = try XCTUnwrap(store.calendarEvents.first { $0.recurrenceRule == nil })
        XCTAssertEqual(standalone.title, individual.title)
        XCTAssertEqual(standalone.urlString, individual.urlString)
        XCTAssertEqual(standalone.startDate, individual.startDate)
        XCTAssertNil(standalone.occurrenceReference)
        XCTAssertTrue(store.calendarExceptions.isEmpty)
    }

    func testUnmatchedChangedOccurrence_reviewCanDiscardIt() throws {
        let store = try makeStore(series: weeklySeries())
        var individual = try occurrence(in: store, at: date(18))
        individual.title = "Discard this occurrence"
        store.updateCalendarEvent(individual)
        let original = try occurrence(in: store, at: date(4))
        var edited = original
        edited.recurrenceRule?.weekdays = [4]
        let plan = try store.prepareCalendarEventEdit(original: original, edited: edited, scope: .series)
        XCTAssertEqual(plan.unmatchedExceptions.count, 1)

        try store.applyCalendarEventEdit(plan, preservingUnmatchedChanges: false)

        XCTAssertFalse(store.calendarEvents.contains { $0.recurrenceRule == nil })
        XCTAssertTrue(store.calendarExceptions.isEmpty)
    }

    func testPreservingUnmatchedSameSlotAfterChangingPatternTwice_keepsDistinctStandaloneIDs() throws {
        let store = try makeStore(series: weeklySeries())
        var first = try occurrence(in: store, at: date(18))
        first.title = "First preserved change"
        store.updateCalendarEvent(first)
        var master = try XCTUnwrap(store.calendarEvents.first { $0.recurrenceRule != nil })
        var edited = master
        edited.recurrenceRule?.weekdays = [4]
        var plan = try store.prepareCalendarEventEdit(original: master, edited: edited, scope: .series)
        try store.applyCalendarEventEdit(plan)

        master = try XCTUnwrap(store.calendarEvents.first { $0.recurrenceRule != nil })
        edited = master
        edited.recurrenceRule?.weekdays = [2]
        plan = try store.prepareCalendarEventEdit(original: master, edited: edited, scope: .series)
        try store.applyCalendarEventEdit(plan)
        var second = try occurrence(in: store, at: date(18))
        second.title = "Second preserved change"
        store.updateCalendarEvent(second)
        master = try XCTUnwrap(store.calendarEvents.first { $0.recurrenceRule != nil })
        edited = master
        edited.recurrenceRule?.weekdays = [4]
        plan = try store.prepareCalendarEventEdit(original: master, edited: edited, scope: .series)
        try store.applyCalendarEventEdit(plan)

        let standalone = store.calendarEvents.filter { $0.recurrenceRule == nil }
        XCTAssertEqual(Set(standalone.map(\.title)), [first.title, second.title])
        XCTAssertEqual(standalone.count, 2)
        XCTAssertEqual(Set(standalone.map(\.id)).count, 2)
    }

    func testRepeatNone_futureKeepsPastAndSelectedStandalone() throws {
        let store = try makeStore(series: weeklySeries())
        let original = try occurrence(in: store, at: date(11))
        var edited = original
        edited.title = "Standalone selected occurrence"
        edited.recurrenceRule = nil
        edited.urlString = "https://example.com/single"

        let plan = try store.prepareCalendarEventEdit(original: original, edited: edited, scope: .future)
        try store.applyCalendarEventEdit(plan)

        XCTAssertEqual(occurrences(in: store).map(\.startDate), [date(4), date(11)])
        let standalone = try XCTUnwrap(store.calendarEvents.first { $0.recurrenceRule == nil })
        XCTAssertEqual(standalone.startDate, edited.startDate)
        XCTAssertEqual(standalone.urlString, edited.urlString)
        XCTAssertNil(standalone.occurrenceReference)
    }

    func testRepeatNone_seriesKeepsExactlyOneSelectedStandalone() throws {
        let store = try makeStore(series: weeklySeries())
        let original = try occurrence(in: store, at: date(18))
        var edited = original
        edited.recurrenceRule = nil

        let plan = try store.prepareCalendarEventEdit(original: original, edited: edited, scope: .series)
        try store.applyCalendarEventEdit(plan)

        XCTAssertEqual(store.calendarEvents.count, 1)
        XCTAssertNil(store.calendarEvents.first?.recurrenceRule)
        XCTAssertNil(store.calendarEvents.first?.occurrenceReference)
        XCTAssertEqual(occurrences(in: store).map(\.startDate), [date(18)])
    }

    func testStalePlan_doesNotOverwriteAnInterveningSave() throws {
        let store = try makeStore(series: weeklySeries())
        let original = try occurrence(in: store, at: date(11))
        var edited = original
        edited.title = "Stale proposed title"
        let plan = try store.prepareCalendarEventEdit(original: original, edited: edited, scope: .series)
        var current = try XCTUnwrap(store.calendarEvents.first)
        current.title = "More recent saved title"
        store.updateCalendarEvent(current)

        XCTAssertThrowsError(try store.applyCalendarEventEdit(plan))

        XCTAssertEqual(store.calendarEvents, [current])
        XCTAssertEqual(try persistedEvents(in: store), [current])
    }

    func testFailedAtomicApply_preservesEventsAndUnrelatedPendingMainContextTask() throws {
        let series = weeklySeries()
        let store = try makeStore(series: series)
        let original = try occurrence(in: store, at: date(11))
        var edited = original
        edited.title = "Proposed future title"
        let plan = try store.prepareCalendarEventEdit(original: original, edited: edited, scope: .future)
        let pendingTask = SDTask(domain: Task(title: "Unrelated unsaved task"))
        store.modelContext.insert(pendingTask)
        XCTAssertTrue(store.modelContext.hasChanges)

        XCTAssertThrowsError(try store.applyCalendarEventEdit(plan, preservingUnmatchedChanges: true, save: { _ in
            throw ExpectedSaveFailure.failed
        }))

        XCTAssertEqual(store.calendarEvents, [series])
        XCTAssertTrue(store.calendarExceptions.isEmpty)
        XCTAssertEqual(try persistedEvents(in: store), [series])
        XCTAssertTrue(store.modelContext.hasChanges)
        XCTAssertTrue(try store.modelContext.fetch(FetchDescriptor<SDTask>()).contains { $0.id == pendingTask.id })
        XCTAssertTrue(try ModelContext(store.modelContext.container).fetch(FetchDescriptor<SDTask>()).isEmpty)
    }

    private enum ExpectedSaveFailure: Error {
        case failed
    }

    private func makeStore(series: CalendarEvent) throws -> AppDataStore {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        context.autosaveEnabled = false
        context.insert(SDCalendarEvent(domain: series))
        try context.save()
        return AppDataStore(container: persistence.container, startsBackgroundServices: false,
                            calendarNotificationService: NotificationService(requestHandler: { _ in }))
    }

    private func weeklySeries(interval: Int = 1, weekdays: [Int] = [2]) -> CalendarEvent {
        CalendarEvent(title: "Original series", startDate: date(4), endDate: date(4, hour: 10), calendarName: "Work",
                      recurrenceRule: EventRecurrenceRule(frequency: .weekly, interval: interval, weekdays: weekdays,
                                                          timeZoneIdentifier: "UTC"))
    }

    private func occurrence(in store: AppDataStore, at start: Date) throws -> CalendarEvent {
        try XCTUnwrap(occurrences(in: store).first { $0.occurrenceReference?.originalStartDate == start })
    }

    private func occurrences(in store: AppDataStore) -> [CalendarEvent] {
        store.events(from: date(1, hour: 0), to: date(31, hour: 23), calendar: calendar)
    }

    private func persistedEvents(in store: AppDataStore) throws -> [CalendarEvent] {
        try ModelContext(store.modelContext.container).fetch(FetchDescriptor<SDCalendarEvent>())
            .map { CalendarEvent(sd: $0) }
    }

    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private func date(_ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2030, month: 3, day: day, hour: hour))!
    }
}
