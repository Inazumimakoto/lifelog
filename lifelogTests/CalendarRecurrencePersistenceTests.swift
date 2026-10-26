import XCTest
import SwiftData
@testable import lifelify

@MainActor
final class CalendarRecurrencePersistenceTests: XCTestCase {
    func testSkipOccurrence_survivesReloadWithoutRemovingSeriesOrChangingCadence() throws {
        let series = event(interval: 2)
        let store = makeStore()
        store.addCalendarEvent(series)
        let first = try XCTUnwrap(occurrences(store, from: 4, to: 30).first)
        _ = store.events(on: first.startDate)

        store.deleteCalendarEvent(first)

        let reloaded = AppDataStore(container: store.modelContext.container, startsBackgroundServices: false)
        XCTAssertEqual(reloaded.calendarEvents, [series])
        XCTAssertEqual(reloaded.calendarExceptions.count, 1)
        XCTAssertEqual(occurrences(reloaded, from: 4, to: 30).map(\.startDate), [date(18)])
        XCTAssertTrue(store.events(on: first.startDate).isEmpty)

        reloaded.restoreCalendarException(try XCTUnwrap(reloaded.calendarExceptions.first))
        XCTAssertEqual(occurrences(reloaded, from: 4, to: 30).map(\.id), [first.id, occurrences(store, from: 4, to: 30)[0].id])
        XCTAssertTrue(try reloaded.modelContext.fetch(FetchDescriptor<SDCalendarEventException>()).isEmpty)
    }

    func testEditOccurrence_keepsIdentityAndPersistsOnlyException() throws {
        let store = makeStore()
        let series = event()
        store.addCalendarEvent(series)
        var first = try XCTUnwrap(occurrences(store, from: 4, to: 20).first)
        let originalID = first.id
        first.title = "Changed only once"
        first.startDate = date(12)
        first.endDate = date(12).addingTimeInterval(3_600)

        store.updateCalendarEvent(first)

        let reloaded = AppDataStore(container: store.modelContext.container, startsBackgroundServices: false)
        XCTAssertEqual(reloaded.calendarEvents, [series])
        let result = occurrences(reloaded, from: 4, to: 20)
        XCTAssertFalse(result.contains { $0.startDate == date(4) })
        XCTAssertEqual(result.first { $0.id == originalID }?.startDate, date(12))
        XCTAssertEqual(result.first { $0.startDate == date(11) }?.title, series.title)
        XCTAssertEqual(try store.modelContext.fetch(FetchDescriptor<SDCalendarEvent>()).count, 1)
    }

    func testSkipWeek_skipsSelectedSeriesAndPreservesBiweeklyAnchor() throws {
        let store = makeStore()
        let series = event(interval: 2, weekdays: [2, 4])
        store.addCalendarEvent(series)
        store.addCalendarEvent(event(title: "Other series"))
        let first = try XCTUnwrap(occurrences(store, from: 4, to: 30).first { $0.title == series.title })

        store.skipCalendarWeek(containing: first)

        XCTAssertEqual(store.calendarExceptions.count, 2)
        XCTAssertEqual(occurrences(store, from: 4, to: 30).filter { $0.title == series.title }.map(\.startDate),
                       [date(18), date(20)])
        XCTAssertTrue(occurrences(store, from: 4, to: 30).contains { $0.title == "Other series" && $0.startDate == date(4) })
    }

    func testEndSeries_preservesPastAndSuppressesFutureReplacement() throws {
        let store = makeStore()
        store.addCalendarEvent(event())
        let selected = try XCTUnwrap(occurrences(store, from: 11, to: 12).first)
        var later = try XCTUnwrap(occurrences(store, from: 18, to: 19).first)
        later.startDate = date(5)
        later.endDate = date(5).addingTimeInterval(3_600)
        store.updateCalendarEvent(later)

        store.endCalendarSeries(startingAt: selected)

        XCTAssertEqual(occurrences(store, from: 4, to: 30).map(\.startDate), [date(4)])
        let reloaded = AppDataStore(container: store.modelContext.container, startsBackgroundServices: false)
        XCTAssertEqual(occurrences(reloaded, from: 4, to: 30).map(\.startDate), [date(4)])
    }

    func testSkipWeek_usesDisplayedWeekAcrossTimeZones() throws {
        let store = makeStore()
        var series = event(weekdays: [1, 2])
        series.startDate = date(3, hour: 23)
        series.endDate = series.startDate.addingTimeInterval(3_600)
        store.addCalendarEvent(series)
        let selected = try XCTUnwrap(occurrences(store, from: 3, to: 5).first)
        var displayCalendar = calendar
        displayCalendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        displayCalendar.firstWeekday = 2

        store.skipCalendarWeek(containing: selected, calendar: displayCalendar)

        XCTAssertEqual(Set(store.calendarExceptions.map(\.originalStartDate)), [date(3, hour: 23), date(4, hour: 23)])
        XCTAssertTrue(occurrences(store, from: 3, to: 12).contains { $0.startDate == date(10, hour: 23) })
    }

    func testSkipWeek_includesReplacementMovedIntoSelectedWeek() throws {
        let store = makeStore()
        store.addCalendarEvent(event())
        var moved = try XCTUnwrap(occurrences(store, from: 4, to: 5).first)
        moved.startDate = date(12)
        moved.endDate = date(12).addingTimeInterval(3_600)
        store.updateCalendarEvent(moved)
        var displayCalendar = calendar
        displayCalendar.firstWeekday = 2

        store.skipCalendarWeek(containing: moved, calendar: displayCalendar)

        XCTAssertEqual(Set(store.calendarExceptions.map(\.originalStartDate)), [date(4), date(11)])
        XCTAssertEqual(occurrences(store, from: 4, to: 20).map(\.startDate), [date(18)])
    }

    func testDeleteWholeSeries_removesItsExceptionsAndLeavesOtherSeries() throws {
        let store = makeStore()
        let series = event()
        let other = event(title: "Keep")
        store.addCalendarEvent(series)
        store.addCalendarEvent(other)
        store.deleteCalendarEvent(try XCTUnwrap(occurrences(store, from: 4, to: 5).first { $0.title == series.title }))

        store.deleteCalendarEvent(series.id)

        let reloaded = AppDataStore(container: store.modelContext.container, startsBackgroundServices: false)
        XCTAssertEqual(reloaded.calendarEvents, [other])
        XCTAssertTrue(reloaded.calendarExceptions.isEmpty)
    }

    func testCategoryRename_updatesReplacementWithoutChangingIndividualReminder() throws {
        let store = makeStore()
        store.addCalendarEvent(event())
        var occurrence = try XCTUnwrap(occurrences(store, from: 4, to: 5).first)
        occurrence.reminderMinutes = 5
        store.updateCalendarEvent(occurrence)

        store.renameCalendarCategory(from: "Work", to: "New category")

        let reloaded = AppDataStore(container: store.modelContext.container, startsBackgroundServices: false)
        let result = try XCTUnwrap(occurrences(reloaded, from: 4, to: 5).first)
        XCTAssertEqual(result.calendarName, "New category")
        XCTAssertEqual(result.reminderMinutes, 5)
    }

    private func makeStore() -> AppDataStore {
        AppDataStore(container: PersistenceController(inMemory: true).container, startsBackgroundServices: false,
                     calendarNotificationService: NotificationService(requestHandler: { _ in }))
    }

    private func event(title: String = "Weekly", interval: Int = 1, weekdays: [Int] = [2]) -> CalendarEvent {
        CalendarEvent(title: title, startDate: date(4), endDate: date(4).addingTimeInterval(3_600), calendarName: "Work",
                      recurrenceRule: EventRecurrenceRule(frequency: .weekly, interval: interval,
                                                          weekdays: weekdays, timeZoneIdentifier: "UTC"))
    }

    private func occurrences(_ store: AppDataStore, from: Int, to: Int) -> [CalendarEvent] {
        store.events(from: date(from, hour: 0), to: date(to, hour: 0), calendar: calendar)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2030, month: 3, day: day, hour: hour))!
    }
}
