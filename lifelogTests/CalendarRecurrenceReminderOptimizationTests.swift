import SwiftData
import UserNotifications
import XCTest
@testable import lifelify

@MainActor
final class CalendarRecurrenceReminderOptimizationTests: XCTestCase {
    func testEditingSeriesMemoAndURL_preservesReminderPlanWhileSavingContent() throws {
        let store = makeStore()
        var series = event()
        store.addCalendarEvent(series)
        let generation = store.externalReminderRescheduleGeneration

        series.detail = "Changed memo only"
        series.urlString = "https://example.com/new-reservation"
        store.updateCalendarEvent(series)

        XCTAssertEqual(store.externalReminderRescheduleGeneration, generation)
        let reader = ModelContext(store.modelContext.container)
        let saved = try XCTUnwrap(reader.fetch(FetchDescriptor<SDCalendarEvent>()).first)
        XCTAssertEqual(CalendarEvent(sd: saved), series)
        XCTAssertEqual(store.events(from: date(4, hour: 0), to: date(5, hour: 0), calendar: calendar).first?.urlString,
                       series.urlString)

        series.title = "Changed reminder title"
        store.updateCalendarEvent(series)
        XCTAssertEqual(store.externalReminderRescheduleGeneration, generation + 1)
        series.recurrenceRule?.until = date(8, hour: 0)
        store.updateCalendarEvent(series)
        XCTAssertEqual(store.externalReminderRescheduleGeneration, generation + 2)
    }

    func testNoReminders_doesNotKeepRefreshingUnnotifiedSeries() async {
        let manager = NotificationSettingsManager.shared
        let wasEnabled = manager.isEventCategoryNotificationEnabled
        manager.isEventCategoryNotificationEnabled = false
        defer { manager.isEventCategoryNotificationEnabled = wasEnabled }
        var requests: [UNNotificationRequest] = []
        let service = NotificationService(referenceDate: { self.date(3) }, requestHandler: { requests.append($0) })
        let store = makeStore(service: service)
        var series = event()
        series.reminderMinutes = nil
        store.calendarEvents = [series]

        store.rescheduleExternalEventNotifications(referenceDate: date(3))
        await nextMainQueueTurn()

        XCTAssertTrue(requests.isEmpty)
        XCTAssertNil(store.nextExternalReminderRefreshDate)
        let generation = store.externalReminderRescheduleGeneration
        store.refreshCalendarRemindersIfNeeded(referenceDate: date(10))
        XCTAssertEqual(store.externalReminderRescheduleGeneration, generation)
    }

    func testUnnotifiedSeries_stillSchedulesIndividuallyEnabledOccurrence() async throws {
        let manager = NotificationSettingsManager.shared
        let wasEnabled = manager.isEventCategoryNotificationEnabled
        manager.isEventCategoryNotificationEnabled = false
        defer { manager.isEventCategoryNotificationEnabled = wasEnabled }
        var requests: [UNNotificationRequest] = []
        let service = NotificationService(referenceDate: { self.date(3) }, requestHandler: { requests.append($0) })
        let store = makeStore(service: service)
        var series = event()
        series.reminderMinutes = nil
        store.addCalendarEvent(series)
        var occurrence = try XCTUnwrap(store.events(from: date(5, hour: 0), to: date(6, hour: 0), calendar: calendar).first)
        occurrence.reminderMinutes = 30
        store.updateCalendarEvent(occurrence)
        requests.removeAll()

        store.rescheduleExternalEventNotifications(referenceDate: date(3))
        await nextMainQueueTurn()

        XCTAssertEqual(requests.map(\.identifier), ["recurring-event-\(occurrence.id.uuidString)"])
        XCTAssertEqual(requests.first?.content.body, series.title)
    }

    private func makeStore(service: NotificationService? = nil) -> AppDataStore {
        AppDataStore(container: PersistenceController(inMemory: true).container, startsBackgroundServices: false,
                     calendarNotificationService: service ?? NotificationService(requestHandler: { _ in }))
    }

    private func event() -> CalendarEvent {
        CalendarEvent(title: "Daily schedule", startDate: date(4), endDate: date(4).addingTimeInterval(3_600),
                      calendarName: "Optimization fixture", reminderMinutes: 15,
                      recurrenceRule: EventRecurrenceRule(frequency: .daily, timeZoneIdentifier: "UTC"))
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
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
