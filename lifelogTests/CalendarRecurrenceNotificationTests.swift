import XCTest
import SwiftData
import UserNotifications
@testable import lifelify

@MainActor
final class CalendarRecurrenceNotificationTests: XCTestCase {
    func testSkipAndRestore_replacesOccurrenceNotificationsAndRetainsUserTitle() async throws {
        let recorder = Recorder(now: date(3))
        let store = AppDataStore(container: PersistenceController(inMemory: true).container,
                                 startsBackgroundServices: false, calendarNotificationService: recorder.service)
        let series = event()
        store.addCalendarEvent(series)
        store.rescheduleExternalEventNotifications(referenceDate: date(3))
        await drainPlan()
        let occurrence = try XCTUnwrap(store.events(from: date(4, hour: 0), to: date(5, hour: 0), calendar: calendar).first)
        let identifier = "recurring-event-\(occurrence.id.uuidString)"
        XCTAssertEqual(recorder.requests[identifier]?.content.body, series.title)
        XCTAssertFalse(try XCTUnwrap(recorder.requests[identifier]?.trigger as? UNCalendarNotificationTrigger).repeats)

        store.deleteCalendarEvent(occurrence)
        store.rescheduleExternalEventNotifications(referenceDate: date(3))
        await drainPlan()
        XCTAssertNil(recorder.requests[identifier])
        XCTAssertTrue(recorder.requests.values.contains { $0.content.body == series.title })

        store.restoreCalendarException(try XCTUnwrap(store.calendarExceptions.first))
        store.rescheduleExternalEventNotifications(referenceDate: date(3))
        await drainPlan()
        XCTAssertEqual(recorder.requests[identifier]?.content.body, series.title)
    }

    func testExternalAndRecurringNotifications_shareNearest48Budget() async {
        let recorder = Recorder(now: date(3))
        let store = AppDataStore(container: PersistenceController(inMemory: true).container,
                                 startsBackgroundServices: false, calendarNotificationService: recorder.service)
        var series = event()
        series.recurrenceRule?.frequency = .daily
        store.addCalendarEvent(series)
        store.externalCalendarEvents = [CalendarEvent(title: "External user title", startDate: date(3, hour: 18),
                                                       endDate: date(3, hour: 19), calendarName: "Work",
                                                       sourceCalendarIdentifier: "calendar", reminderMinutes: 15)]

        store.rescheduleExternalEventNotifications(referenceDate: date(3))
        await drainPlan()

        XCTAssertEqual(recorder.requests.count, 48)
        XCTAssertEqual(recorder.requests.values.filter { $0.identifier.hasPrefix("external-event-") }.count, 1)
        XCTAssertEqual(recorder.requests.values.filter { $0.identifier.hasPrefix("recurring-event-") }.count, 47)
    }

    func testConvertingSeriesToSingle_cancelsQueuedOccurrences() async {
        let recorder = Recorder(now: date(3))
        let store = AppDataStore(container: PersistenceController(inMemory: true).container,
                                 startsBackgroundServices: false, calendarNotificationService: recorder.service)
        var series = event()
        store.addCalendarEvent(series)
        store.rescheduleExternalEventNotifications(referenceDate: date(3))
        await drainPlan()
        XCTAssertFalse(recorder.requests.isEmpty)

        series.recurrenceRule = nil
        store.updateCalendarEvent(series)
        await drainPlan()

        XCTAssertFalse(recorder.requests.keys.contains { $0.hasPrefix("recurring-event-") })
        XCTAssertNotNil(recorder.requests["event-\(series.id.uuidString)"])
    }

    private func drainPlan() async {
        let settled = expectation(description: "Notification plan applied")
        DispatchQueue.main.async { settled.fulfill() }
        await fulfillment(of: [settled], timeout: 2)
    }

    private func event() -> CalendarEvent {
        CalendarEvent(title: "利用者の予定タイトル", startDate: date(4), endDate: date(4).addingTimeInterval(3_600),
                      calendarName: "Work", reminderMinutes: 30,
                      recurrenceRule: EventRecurrenceRule(frequency: .weekly, weekdays: [2], timeZoneIdentifier: "UTC"))
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

@MainActor
private final class Recorder {
    var requests: [String: UNNotificationRequest] = [:]
    let now: Date
    lazy var service = NotificationService(referenceDate: { [unowned self] in self.now },
                                           requestHandler: { [unowned self] in self.requests[$0.identifier] = $0 },
                                           cancellationHandler: { [unowned self] ids in
        for id in ids { self.requests.removeValue(forKey: id) }
    })

    init(now: Date) { self.now = now }
}
