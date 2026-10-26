import SwiftData
import XCTest
@testable import lifelify

@MainActor
final class CalendarEventScopedReminderTests: XCTestCase {
    func testSeriesStartOnlyEdit_keepsUnchangedAbsoluteAlarmShownInPicker() throws {
        let (store, series) = try makeStore()
        let original = try occurrence(in: store, day: 18)
        var edited = original
        edited.startDate = date(18, hour: 10)
        edited.endDate = date(18, hour: 11)
        XCTAssertEqual(edited.reminderDate, date(18, hour: 8))

        let plan = try store.prepareCalendarEventEdit(original: original, edited: edited, scope: .series)
        try store.applyCalendarEventEdit(plan)

        let master = try XCTUnwrap(store.calendarEvents.first { $0.id == series.id })
        XCTAssertEqual(master.startDate, date(4, hour: 10))
        XCTAssertEqual(master.reminderDate, date(4, hour: 8))
        XCTAssertEqual(try occurrence(in: store, day: 18).reminderDate, date(18, hour: 8))
        XCTAssertEqual(try sharedOccurrence(in: store, day: 18).reminderDate, date(18, hour: 8))
    }

    func testFutureStartOnlyEdit_keepsUnchangedAbsoluteAlarmAndPastTimes() throws {
        let (store, series) = try makeStore()
        let original = try occurrence(in: store, day: 18)
        var edited = original
        edited.startDate = date(18, hour: 10)
        edited.endDate = date(18, hour: 11)

        let plan = try store.prepareCalendarEventEdit(original: original, edited: edited, scope: .future)
        try store.applyCalendarEventEdit(plan)

        let future = try XCTUnwrap(store.calendarEvents.first { $0.id != series.id })
        XCTAssertEqual(future.startDate, date(18, hour: 10))
        XCTAssertEqual(future.reminderDate, date(18, hour: 8))
        XCTAssertEqual(try occurrence(in: store, day: 11).startDate, date(11, hour: 9))
        XCTAssertEqual(try occurrence(in: store, day: 11).reminderDate, date(11, hour: 8))
        XCTAssertEqual(try occurrence(in: store, day: 18).reminderDate, date(18, hour: 8))
        XCTAssertEqual(try sharedOccurrence(in: store, day: 18).reminderDate, date(18, hour: 8))
    }

    private func makeStore() throws -> (AppDataStore, CalendarEvent) {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let series = CalendarEvent(title: "Weekly", startDate: date(4, hour: 9), endDate: date(4, hour: 10),
                                   calendarName: "Work", reminderDate: date(4, hour: 8),
                                   recurrenceRule: EventRecurrenceRule(frequency: .weekly, weekdays: [2], timeZoneIdentifier: "UTC"))
        context.insert(SDCalendarEvent(domain: series))
        try context.save()
        let store = AppDataStore(container: persistence.container, startsBackgroundServices: false,
                                 calendarNotificationService: NotificationService(requestHandler: { _ in }))
        return (store, series)
    }

    private func occurrence(in store: AppDataStore, day: Int) throws -> CalendarEvent {
        try XCTUnwrap(store.events(from: date(day, hour: 0), to: date(day + 1, hour: 0), calendar: calendar).first)
    }

    private func sharedOccurrence(in store: AppDataStore, day: Int) throws -> CalendarEvent {
        try XCTUnwrap(CalendarEventStorageQuery.events(in: ModelContext(store.modelContext.container),
                                                       from: date(day, hour: 0), to: date(day + 1, hour: 0), calendar: calendar).first)
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2030, month: 3, day: day, hour: hour))!
    }
}
