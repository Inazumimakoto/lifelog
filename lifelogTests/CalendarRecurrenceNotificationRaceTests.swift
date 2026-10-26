import SwiftData
import UserNotifications
import XCTest
@testable import lifelify

@MainActor
final class CalendarRecurrenceNotificationRaceTests: XCTestCase {
    func testOlderPendingReadAfterNewSkippedPlan_doesNotCancelNewPlan() async throws {
        let now = date(day: 8, hour: 12)
        let recording = NotificationRecording()
        let service = DelayedCalendarNotificationService(now: now, recording: recording)
        let store = AppDataStore(container: PersistenceController(inMemory: true).container,
                                 startsBackgroundServices: false, calendarNotificationService: service)
        let series = series()
        store.calendarEvents = [series]
        store.rescheduleExternalEventNotifications(referenceDate: now)
        service.finishCancellation(at: 0)
        await nextMainQueueTurn()
        let initialRequests = recording.pending.filter { $0.key.hasPrefix("recurring-event-") }
        XCTAssertEqual(initialRequests.count, 3)
        let taskID = UUID()
        service.scheduleTaskReminder(taskId: taskID, title: "Unrelated task", reminderDate: date(day: 9, hour: 8))

        // Both reads captured the same old identifiers, as can happen when the
        // notification center completes asynchronous snapshots out of order.
        store.rescheduleExternalEventNotifications(referenceDate: now)
        let skipped = CalendarEventException(seriesID: series.id, originalStartDate: series.startDate)
        store.calendarExceptions = [skipped]
        store.rescheduleExternalEventNotifications(referenceDate: now)
        service.finishCancellation(at: 2)
        await nextMainQueueTurn()
        let newestRequests = recording.pending
        XCTAssertEqual(newestRequests.filter { $0.key.hasPrefix("recurring-event-") }.count, 2)

        service.finishCancellation(at: 1)
        await nextMainQueueTurn()

        XCTAssertEqual(Set(recording.pending.keys), Set(newestRequests.keys))
        XCTAssertEqual(service.ignoredStaleCancellations, 1)
        XCTAssertNotNil(recording.pending["task-\(taskID.uuidString)"])
        XCTAssertNil(recording.pending["recurring-event-\(skipped.occurrenceReference.occurrenceID.uuidString)"])
    }

    func testOlderPlanAfterSeriesDeleted_doesNotRestoreReminders() async {
        let now = date(day: 8, hour: 12)
        let recording = NotificationRecording()
        let service = DelayedCalendarNotificationService(now: now, recording: recording)
        let store = AppDataStore(container: PersistenceController(inMemory: true).container,
                                 startsBackgroundServices: false, calendarNotificationService: service)
        store.calendarEvents = [series()]
        store.rescheduleExternalEventNotifications(referenceDate: now)
        service.finishCancellation(at: 0)
        await nextMainQueueTurn()
        XCTAssertEqual(recording.pending.count, 3)

        store.rescheduleExternalEventNotifications(referenceDate: now)
        store.calendarEvents = []
        store.rescheduleExternalEventNotifications(referenceDate: now)
        service.finishCancellation(at: 2)
        await nextMainQueueTurn()
        service.finishCancellation(at: 1)
        await nextMainQueueTurn()

        XCTAssertTrue(recording.pending.isEmpty)
        XCTAssertEqual(service.ignoredStaleCancellations, 1)
    }

    private func series() -> CalendarEvent {
        CalendarEvent(title: "Daily event", startDate: date(day: 9, hour: 9),
                      endDate: date(day: 9, hour: 10), calendarName: "Work", reminderMinutes: 30,
                      recurrenceRule: EventRecurrenceRule(frequency: .daily, until: date(day: 11, hour: 0),
                                                          timeZoneIdentifier: Calendar.current.timeZone.identifier))
    }

    private func date(day: Int, hour: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2030, month: 3, day: day, hour: hour))!
    }

    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

@MainActor
private final class NotificationRecording {
    var pending: [String: UNNotificationRequest] = [:]
}

@MainActor
private final class DelayedCalendarNotificationService: NotificationService {
    private let recording: NotificationRecording
    private var cancellations: [() -> Void] = []
    private(set) var ignoredStaleCancellations = 0

    init(now: Date, recording: NotificationRecording) {
        self.recording = recording
        super.init(referenceDate: { now }, requestHandler: { recording.pending[$0.identifier] = $0 },
                   cancellationHandler: { identifiers in
            for identifier in identifiers { recording.pending.removeValue(forKey: identifier) }
        })
    }

    override func cancelAllReminders(ofTypes types: [NotificationType], shouldCancel: @escaping () -> Bool,
                                     completion: (() -> Void)?) {
        let prefixes = types.map { $0.rawValue + "-" }
        let identifiers = recording.pending.keys.filter { identifier in
            prefixes.contains { identifier.hasPrefix($0) }
        }
        cancellations.append { [weak self] in
            guard let self else { return }
            guard shouldCancel() else {
                self.ignoredStaleCancellations += 1
                return
            }
            for identifier in identifiers { self.recording.pending.removeValue(forKey: identifier) }
            completion?()
        }
    }

    func finishCancellation(at index: Int) {
        cancellations[index]()
    }
}
