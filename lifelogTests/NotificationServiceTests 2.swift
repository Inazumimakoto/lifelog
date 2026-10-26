import XCTest
import UserNotifications
@testable import lifelify

@MainActor
final class NotificationServiceTests: XCTestCase {
    func testRelativeAndAbsoluteEventReminders_keepSameRequestAndFireTime() throws {
        var requests: [UNNotificationRequest] = []
        let now = date(day: 8, hour: 12)
        let service = NotificationService(referenceDate: { now }, requestHandler: { requests.append($0) })
        let id = UUID()
        let start = date(day: 9, hour: 14)
        let fireDate = start.addingTimeInterval(-30 * 60)

        service.scheduleEventReminder(eventId: id, title: "User's title", startDate: start, minutesBefore: 30)
        service.scheduleEventReminderAtDate(eventId: id, title: "User's title", reminderDate: fireDate)

        XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertEqual(request.identifier, "event-\(id.uuidString)")
            XCTAssertEqual(request.content.title, String(localized: "予定のリマインダー"))
            XCTAssertEqual(request.content.body, "User's title")
            XCTAssertNotNil(request.content.sound)
            let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
            XCTAssertFalse(trigger.repeats)
            XCTAssertEqual(trigger.dateComponents, components(fireDate))
        }
    }

    func testPastEqualAndDisabledReminders_doNotSubmitRequests() {
        var requests: [UNNotificationRequest] = []
        let now = date(day: 8, hour: 12)
        let service = NotificationService(referenceDate: { now }, requestHandler: { requests.append($0) })
        let id = UUID()
        service.scheduleEventReminder(eventId: id, title: "Event", startDate: now.addingTimeInterval(60), minutesBefore: 0)
        service.scheduleExternalEventReminder(externalEventKey: "external", title: "External", startDate: now, minutesBefore: -1)
        service.scheduleEventReminderAtDate(eventId: id, title: "Event", reminderDate: now)
        service.scheduleExternalEventReminderAtDate(externalEventKey: "external", title: "External", reminderDate: now.addingTimeInterval(-60))
        service.scheduleTaskReminder(taskId: id, title: "Task", reminderDate: now)
        service.scheduleAnniversaryReminderAtDate(anniversaryId: id, title: "Anniversary", reminderDate: now)
        XCTAssertTrue(requests.isEmpty)
    }

    func testDistinctReminderKinds_preserveIdentifiersAndUserContent() {
        var requests: [UNNotificationRequest] = []
        var cancelled: [String] = []
        let now = date(day: 8, hour: 12)
        let future = date(day: 9, hour: 14)
        let service = NotificationService(referenceDate: { now }, requestHandler: { requests.append($0) },
                                          cancellationHandler: { cancelled.append(contentsOf: $0) })
        let id = UUID()
        service.scheduleExternalEventReminder(externalEventKey: "calendar|event", title: "外部の原文", startDate: future, minutesBefore: 15)
        service.scheduleTaskReminder(taskId: id, title: "Task原文", reminderDate: future)
        service.scheduleAnniversaryReminderAtDate(anniversaryId: id, title: "記念日の原文", reminderDate: future)
        service.cancelEventReminder(eventId: id)
        service.cancelTaskReminder(taskId: id)
        service.cancelAnniversaryReminder(anniversaryId: id)

        XCTAssertEqual(requests.map(\.identifier), ["external-event-calendar|event", "task-\(id.uuidString)", "anniversary-\(id.uuidString)"])
        XCTAssertEqual(requests.map { $0.content.body }, ["外部の原文", "Task原文", "記念日の原文"])
        XCTAssertEqual(cancelled, ["event-\(id.uuidString)", "task-\(id.uuidString)", "anniversary-\(id.uuidString)"])
    }

    func testYearlyAnniversary_omitsYearWhileOneTimeReminderIncludesYear() throws {
        var requests: [UNNotificationRequest] = []
        let now = date(day: 8, hour: 12)
        let service = NotificationService(referenceDate: { now }, requestHandler: { requests.append($0) })
        let id = UUID()
        for repeats in [true, false] {
            service.scheduleAnniversaryReminder(anniversaryId: id, title: "Anniversary", targetDate: date(day: 20, hour: 0),
                                                daysBefore: 7, time: date(day: 8, hour: 9), repeatsYearly: repeats)
        }
        XCTAssertEqual(requests.count, 2)
        let yearly = try XCTUnwrap(requests[0].trigger as? UNCalendarNotificationTrigger)
        let oneTime = try XCTUnwrap(requests[1].trigger as? UNCalendarNotificationTrigger)
        XCTAssertTrue(yearly.repeats)
        XCTAssertNil(yearly.dateComponents.year)
        XCTAssertFalse(oneTime.repeats)
        XCTAssertEqual(oneTime.dateComponents.year, 2030)
        for trigger in [yearly, oneTime] {
            XCTAssertEqual(trigger.dateComponents.month, 3)
            XCTAssertEqual(trigger.dateComponents.day, 13)
            XCTAssertEqual(trigger.dateComponents.hour, 9)
        }
    }

    func testDiaryReminder_rollsPastTimeForwardAndSharesExplicitDateRequest() throws {
        var requests: [UNNotificationRequest] = []
        var cancelled: [String] = []
        let now = date(day: 8, hour: 12)
        let service = NotificationService(referenceDate: { now }, requestHandler: { requests.append($0) },
                                          cancellationHandler: { cancelled.append(contentsOf: $0) })
        service.scheduleDiaryReminder(hour: 11, minute: 0)
        service.scheduleDiaryReminder(components: components(date(day: 9, hour: 11)))
        service.scheduleDiaryReminder(hour: 13, minute: 0)

        XCTAssertEqual(cancelled, ["diary-daily-reminder", "diary-daily-reminder"])
        XCTAssertEqual(requests.map(\.identifier), Array(repeating: "diary-daily-reminder", count: 3))
        let triggers = try requests.map { try XCTUnwrap($0.trigger as? UNCalendarNotificationTrigger) }
        XCTAssertEqual(triggers[0].dateComponents, triggers[1].dateComponents)
        XCTAssertEqual(triggers[0].dateComponents, components(date(day: 9, hour: 11)))
        XCTAssertEqual(triggers[2].dateComponents, components(date(day: 8, hour: 13)))
        XCTAssertEqual(requests[0].content.title, requests[1].content.title)
        XCTAssertEqual(requests[0].content.body, requests[1].content.body)
        XCTAssertTrue(triggers.allSatisfy { !$0.repeats })
    }

    func testOverviewReminder_checksFutureDateBeforeReplacingExistingRequest() {
        var operations: [String] = []
        let now = date(day: 8, hour: 12)
        let service = NotificationService(referenceDate: { now }, requestHandler: { operations.append("add:\($0.identifier)") },
                                          cancellationHandler: { operations.append("cancel:\($0.joined(separator: ","))") })
        service.scheduleTodayOverviewReminder(fireDate: now, body: "Ignored")
        XCTAssertTrue(operations.isEmpty)
        service.scheduleTodayOverviewReminder(fireDate: date(day: 9, hour: 12), body: "Today")
        XCTAssertEqual(operations, ["cancel:today-overview-reminder", "add:today-overview-reminder"])
    }

    func testCommonCalendarRequest_preservesLetterUserInfoWithoutApplyingReminderDatePolicy() throws {
        var requests: [UNNotificationRequest] = []
        let now = date(day: 8, hour: 12)
        let service = NotificationService(referenceDate: { now }, requestHandler: { requests.append($0) })
        let letterID = UUID().uuidString
        let pastComponents = components(date(day: 7, hour: 12))
        service.scheduleCalendarNotification(identifier: "letter-\(letterID)", title: "Letter", body: "User content",
                                             components: pastComponents, userInfo: ["letterID": letterID], errorMessage: "test")
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.content.userInfo["letterID"] as? String, letterID)
        XCTAssertEqual((request.trigger as? UNCalendarNotificationTrigger)?.dateComponents, pastComponents)
        XCTAssertEqual(request.identifier, "letter-\(letterID)")
    }

    private func date(day: Int, hour: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2030, month: 3, day: day, hour: hour))!
    }

    private func components(_ date: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }
}
