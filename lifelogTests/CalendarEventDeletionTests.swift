import SwiftData
import XCTest
@testable import lifelify

@MainActor
final class CalendarEventDeletionTests: XCTestCase {
    func testWeeklySingleOccurrence_hidesWeekScopeAndIgnoresOtherSeries() throws {
        let store = makeStore()
        let series = event()
        store.addCalendarEvent(series)
        store.addCalendarEvent(event(title: "Other daily series", frequency: .daily))
        let selected = try occurrence(in: store, series: series, on: 4)

        XCTAssertEqual(store.calendarOccurrencesInWeek(containing: selected, calendar: calendar).map(\.startDate), [date(4)])
        XCTAssertFalse(store.canDeleteCalendarWeek(containing: selected, calendar: calendar))
        XCTAssertEqual(store.calendarEvents.count, 2)
        XCTAssertTrue(store.calendarExceptions.isEmpty)
    }

    func testWeeklyMultipleWeekdays_showsWeekScopeAndSkipUsesTheSameOccurrences() throws {
        let store = makeStore()
        let series = event(weekdays: [2, 4])
        store.addCalendarEvent(series)
        let selected = try occurrence(in: store, series: series, on: 4)

        XCTAssertEqual(store.calendarOccurrencesInWeek(containing: selected, calendar: calendar).map(\.startDate), [date(4), date(6)])
        XCTAssertTrue(store.canDeleteCalendarWeek(containing: selected, calendar: calendar))
        XCTAssertTrue(store.canDeleteCalendarWeek(containing: series, calendar: calendar))

        store.skipCalendarWeek(containing: selected, calendar: calendar)

        XCTAssertEqual(Set(store.calendarExceptions.map(\.originalStartDate)), [date(4), date(6)])
        XCTAssertEqual(occurrences(in: store, series: series, from: 4, to: 15).map(\.startDate), [date(11), date(13)])
        XCTAssertEqual(store.calendarEvents, [series])
    }

    func testDailyAndBiweeklySeries_useActualOccurrencesInSelectedWeek() throws {
        let dailyStore = makeStore()
        let daily = event(frequency: .daily)
        dailyStore.addCalendarEvent(daily)
        let dailySelected = try occurrence(in: dailyStore, series: daily, on: 4)
        XCTAssertEqual(dailyStore.calendarOccurrencesInWeek(containing: dailySelected, calendar: calendar).count, 7)
        XCTAssertTrue(dailyStore.canDeleteCalendarWeek(containing: dailySelected, calendar: calendar))

        let biweeklyStore = makeStore()
        let biweekly = event(interval: 2, weekdays: [2, 4])
        biweeklyStore.addCalendarEvent(biweekly)
        let selected = try occurrence(in: biweeklyStore, series: biweekly, on: 4)
        XCTAssertEqual(biweeklyStore.calendarOccurrencesInWeek(containing: selected, calendar: calendar).map(\.startDate), [date(4), date(6)])
        XCTAssertTrue(biweeklyStore.canDeleteCalendarWeek(containing: selected, calendar: calendar))
        var staleOffWeekSelection = selected
        staleOffWeekSelection.startDate = date(11)
        staleOffWeekSelection.endDate = date(11, hour: 10)
        XCTAssertTrue(biweeklyStore.calendarOccurrencesInWeek(containing: staleOffWeekSelection, calendar: calendar).isEmpty)
        XCTAssertFalse(biweeklyStore.canDeleteCalendarWeek(containing: staleOffWeekSelection, calendar: calendar))
        let next = try occurrence(in: biweeklyStore, series: biweekly, on: 18)
        XCTAssertEqual(biweeklyStore.calendarOccurrencesInWeek(containing: next, calendar: calendar).map(\.startDate), [date(18), date(20)])
    }

    func testCancelledOccurrence_reducesWeekCountToOneWithoutChangingMasterURL() throws {
        let store = makeStore()
        let series = event(weekdays: [2, 4])
        store.addCalendarEvent(series)
        let monday = try occurrence(in: store, series: series, on: 4)
        let wednesday = try occurrence(in: store, series: series, on: 6)

        store.deleteCalendarEvent(wednesday)

        XCTAssertEqual(store.calendarOccurrencesInWeek(containing: monday, calendar: calendar).map(\.startDate), [date(4)])
        XCTAssertFalse(store.canDeleteCalendarWeek(containing: monday, calendar: calendar))
        XCTAssertEqual(store.calendarEvents, [series])
        XCTAssertEqual(store.calendarEvents.first?.urlString, series.urlString)
    }

    func testEndingSeriesWithinWeek_reducesWeekCountToOne() throws {
        let store = makeStore()
        let series = event(weekdays: [2, 4])
        store.addCalendarEvent(series)
        let monday = try occurrence(in: store, series: series, on: 4)
        let wednesday = try occurrence(in: store, series: series, on: 6)

        store.endCalendarSeries(startingAt: wednesday)

        XCTAssertEqual(store.calendarOccurrencesInWeek(containing: monday, calendar: calendar).map(\.startDate), [date(4)])
        XCTAssertFalse(store.canDeleteCalendarWeek(containing: monday, calendar: calendar))
        let retainedMonday = try occurrence(in: store, series: series, on: 4)
        XCTAssertEqual(retainedMonday.id, monday.id)
        XCTAssertEqual(retainedMonday.startDate, monday.startDate)
        XCTAssertEqual(retainedMonday.detail, monday.detail)
        XCTAssertEqual(retainedMonday.urlString, monday.urlString)
        XCTAssertEqual(store.calendarEvents.first?.urlString, series.urlString)
    }

    func testReplacementMovedOutOfWeek_removesItFromOriginalWeekCount() throws {
        let store = makeStore()
        let series = event(weekdays: [2, 4])
        store.addCalendarEvent(series)
        let monday = try occurrence(in: store, series: series, on: 4)
        var moved = try occurrence(in: store, series: series, on: 6)
        moved.startDate = date(12)
        moved.endDate = date(12, hour: 10)
        store.updateCalendarEvent(moved)

        XCTAssertEqual(store.calendarOccurrencesInWeek(containing: monday, calendar: calendar).map(\.startDate), [date(4)])
        XCTAssertFalse(store.canDeleteCalendarWeek(containing: monday, calendar: calendar))
        XCTAssertEqual(store.calendarOccurrencesInWeek(containing: moved, calendar: calendar).map(\.startDate), [date(11), date(12), date(13)])
        XCTAssertTrue(store.canDeleteCalendarWeek(containing: moved, calendar: calendar))
    }

    func testReplacementMovedIntoWeek_showsWeekScopeAndSkipsOriginalSlots() throws {
        let store = makeStore()
        let series = event()
        store.addCalendarEvent(series)
        var moved = try occurrence(in: store, series: series, on: 4)
        moved.startDate = date(12)
        moved.endDate = date(12, hour: 10)
        store.updateCalendarEvent(moved)

        XCTAssertEqual(store.calendarOccurrencesInWeek(containing: moved, calendar: calendar).map(\.startDate), [date(11), date(12)])
        XCTAssertTrue(store.canDeleteCalendarWeek(containing: moved, calendar: calendar))

        store.skipCalendarWeek(containing: moved, calendar: calendar)

        XCTAssertEqual(Set(store.calendarExceptions.map(\.originalStartDate)), [date(4), date(11)])
        XCTAssertEqual(occurrences(in: store, series: series, from: 4, to: 20).map(\.startDate), [date(18)])
        XCTAssertEqual(try occurrence(in: store, series: series, on: 18).urlString, series.urlString)
    }

    func testDisplayedTimeZoneAndWeekStart_controlWeekScope() throws {
        let store = makeStore()
        var series = event(weekdays: [1, 2])
        series.startDate = date(3, hour: 23)
        series.endDate = date(4, hour: 0)
        store.addCalendarEvent(series)
        let selected = try occurrence(in: store, series: series, on: 3)
        var tokyoMonday = calendar
        tokyoMonday.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var utcSunday = calendar
        utcSunday.firstWeekday = 1

        XCTAssertEqual(store.calendarOccurrencesInWeek(containing: selected, calendar: tokyoMonday).map(\.startDate), [date(3, hour: 23), date(4, hour: 23)])
        XCTAssertTrue(store.canDeleteCalendarWeek(containing: selected, calendar: tokyoMonday))
        XCTAssertFalse(store.canDeleteCalendarWeek(containing: selected, calendar: calendar))
        XCTAssertTrue(store.canDeleteCalendarWeek(containing: selected, calendar: utcSunday))
    }

    func testMultipleDayCarryInFromPreviousWeek_doesNotIncreaseWeekCount() throws {
        let store = makeStore()
        var series = event(weekdays: [1, 3])
        series.startDate = date(3)
        series.endDate = date(6)
        series.recurrenceRule?.until = date(5, hour: 0)
        store.addCalendarEvent(series)
        let selected = try occurrence(in: store, series: series, on: 5)

        XCTAssertEqual(store.calendarOccurrencesInWeek(containing: selected, calendar: calendar).map(\.startDate), [date(5)])
        XCTAssertFalse(store.canDeleteCalendarWeek(containing: selected, calendar: calendar))
    }

    func testDeleteEntireSeriesFromOccurrence_removesMasterAndExceptionsAndPreservesOtherSeries() throws {
        let store = makeStore()
        let series = event(title: "Delete", frequency: .daily)
        var other = event(title: "Keep", weekdays: [2, 4])
        other.urlString = "https://example.com/keep"
        store.addCalendarEvent(series)
        store.addCalendarEvent(other)
        store.deleteCalendarEvent(try occurrence(in: store, series: series, on: 4))
        var moved = try occurrence(in: store, series: series, on: 5)
        moved.startDate = date(12)
        moved.endDate = date(12, hour: 10)
        store.updateCalendarEvent(moved)
        let otherPast = try occurrence(in: store, series: other, on: 4)
        store.deleteCalendarEvent(try occurrence(in: store, series: other, on: 6))
        let selected = try occurrence(in: store, series: series, on: 6)

        store.deleteCalendarSeries(containing: selected)

        let reloaded = makeStore(container: store.modelContext.container)
        XCTAssertEqual(reloaded.calendarEvents, [other])
        XCTAssertEqual(reloaded.calendarExceptions.count, 1)
        XCTAssertEqual(reloaded.calendarExceptions.first?.seriesID, other.id)
        XCTAssertEqual(try occurrence(in: reloaded, series: other, on: 4), otherPast)
        XCTAssertEqual(try reloaded.modelContext.fetch(FetchDescriptor<SDCalendarEvent>()).map(\.id), [other.id])
        XCTAssertEqual(try reloaded.modelContext.fetch(FetchDescriptor<SDCalendarEventException>()).map(\.seriesID), [other.id])
        XCTAssertFalse(reloaded.events(from: date(1, hour: 0), to: date(25, hour: 0), calendar: calendar).contains { $0.occurrenceReference?.seriesID == series.id })
    }

    func testDefaultAndFutureDeletion_keepPastAndURLsWithExistingScopes() throws {
        let store = makeStore()
        let series = event()
        store.addCalendarEvent(series)
        let past = try occurrence(in: store, series: series, on: 4)
        store.deleteCalendarEvent(try occurrence(in: store, series: series, on: 11))

        XCTAssertEqual(store.calendarEvents, [series])
        XCTAssertEqual(try occurrence(in: store, series: series, on: 4), past)
        XCTAssertEqual(try occurrence(in: store, series: series, on: 18).urlString, series.urlString)

        store.endCalendarSeries(startingAt: try occurrence(in: store, series: series, on: 18))

        let retained = occurrences(in: store, series: series, from: 4, to: 25)
        XCTAssertEqual(retained.map(\.id), [past.id])
        XCTAssertEqual(retained.first?.startDate, past.startDate)
        XCTAssertEqual(retained.first?.detail, past.detail)
        XCTAssertEqual(retained.first?.reminderMinutes, past.reminderMinutes)
        XCTAssertEqual(retained.first?.urlString, past.urlString)
        XCTAssertEqual(store.calendarEvents.first?.urlString, series.urlString)
        XCTAssertEqual(store.calendarExceptions.count, 1)
    }

    func testReadonlyExternalAndSingleEvents_doNotOfferOrMutateWeekScope() throws {
        let store = makeStore()
        let series = event(weekdays: [2, 4])
        store.addCalendarEvent(series)
        var external = try occurrence(in: store, series: series, on: 4)
        external.sourceCalendarIdentifier = "readonly-calendar"
        store.externalCalendarEvents = [external]
        var single = event(title: "Single")
        single.recurrenceRule = nil
        store.addCalendarEvent(single)

        XCTAssertTrue(store.calendarOccurrencesInWeek(containing: external, calendar: calendar).isEmpty)
        XCTAssertFalse(store.canDeleteCalendarWeek(containing: external, calendar: calendar))
        XCTAssertFalse(store.canDeleteCalendarWeek(containing: single, calendar: calendar))
        store.skipCalendarWeek(containing: external, calendar: calendar)
        store.deleteCalendarSeries(containing: external)

        XCTAssertEqual(store.calendarEvents, [series, single])
        XCTAssertEqual(store.externalCalendarEvents, [external])
        XCTAssertTrue(store.calendarExceptions.isEmpty)
    }

    private func makeStore(container: ModelContainer? = nil) -> AppDataStore {
        AppDataStore(container: container ?? PersistenceController(inMemory: true).container,
                     startsBackgroundServices: false,
                     calendarNotificationService: NotificationService(requestHandler: { _ in }))
    }

    private func event(title: String = "Weekly", frequency: EventRecurrenceRule.Frequency = .weekly,
                       interval: Int = 1, weekdays: [Int] = [2]) -> CalendarEvent {
        CalendarEvent(title: title, detail: "Keep original memo", startDate: date(4), endDate: date(4, hour: 10),
                      calendarName: "Work", reminderMinutes: 15,
                      recurrenceRule: EventRecurrenceRule(frequency: frequency, interval: interval,
                                                          weekdays: weekdays, timeZoneIdentifier: "UTC"),
                      urlString: "https://example.com/original")
    }

    private func occurrence(in store: AppDataStore, series: CalendarEvent, on day: Int) throws -> CalendarEvent {
        try XCTUnwrap(occurrences(in: store, series: series, from: day, to: day + 1).first {
            calendar.isDate($0.displayStartDate(calendar: calendar), inSameDayAs: date(day))
        })
    }

    private func occurrences(in store: AppDataStore, series: CalendarEvent, from: Int, to: Int) -> [CalendarEvent] {
        store.events(from: date(from, hour: 0), to: date(to, hour: 0), calendar: calendar)
            .filter { $0.occurrenceReference?.seriesID == series.id }
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 2
        return value
    }

    private func date(_ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2030, month: 3, day: day, hour: hour))!
    }
}
