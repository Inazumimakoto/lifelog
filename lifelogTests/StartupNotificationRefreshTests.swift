import SwiftData
import UserNotifications
import XCTest
@testable import lifelify

@MainActor
final class StartupNotificationRefreshTests: XCTestCase {
    func testRefreshRequestsBeforeStartup_doNotTouchNotificationsOrExpandOverview() async throws {
        try await withNotificationDefaults {
            let now = date(day: 8, hour: 7)
            let calendar = StartupNotificationRecorder(now: now)
            let daily = StartupNotificationRecorder(now: now)
            let store = try makeStore(events: [recurringEvent()], calendar: calendar, daily: daily)
            store.appState.diaryReminderEnabled = true

            for _ in 0..<3 {
                store.reapplyEventCategoryNotificationSettings(referenceDate: now)
                store.rescheduleExternalEventNotifications(referenceDate: now)
                store.refreshCalendarRemindersIfNeeded(referenceDate: now)
                store.rescheduleTodayOverviewReminderIfNeeded(referenceDate: now)
                store.rescheduleDiaryReminderIfNeeded(referenceDate: now)
            }
            await nextMainQueueTurn()

            XCTAssertTrue(calendar.submissions.isEmpty)
            XCTAssertTrue(calendar.cancellations.isEmpty)
            XCTAssertEqual(calendar.service.reconciliationCount, 0)
            XCTAssertTrue(daily.submissions.isEmpty)
            XCTAssertTrue(daily.cancellations.isEmpty)
            XCTAssertEqual(store.externalReminderRescheduleGeneration, 0)
            XCTAssertNil(store.nextExternalReminderRefreshDate)
            XCTAssertTrue(store.eventsCache.isEmpty)
        }
    }

    func testFirstStartupRefresh_usesLatestCalendarDataAndRegistersDailyRemindersOnce() async throws {
        try await withNotificationDefaults {
            let now = date(day: 8, hour: 7)
            let calendar = StartupNotificationRecorder(now: now)
            let daily = StartupNotificationRecorder(now: now)
            let localEvent = event(title: "Saved user title", hour: 9)
            let store = try makeStore(events: [localEvent], calendar: calendar, daily: daily)
            store.appState.diaryReminderEnabled = true
            store.appState.diaryReminderHour = 21
            store.appState.diaryReminderMinute = 30
            var external = event(title: "Older calendar snapshot", hour: 10, source: "startup-calendar")
            store.updateExternalCalendarEvents([external], referenceDate: now)
            external.title = "最新の利用者の予定"
            store.updateExternalCalendarEvents([external], referenceDate: now)

            XCTAssertTrue(calendar.submissions.isEmpty)
            XCTAssertTrue(daily.submissions.isEmpty)
            XCTAssertEqual(store.externalReminderRescheduleGeneration, 0)

            store.refreshNotificationsAfterStartup(referenceDate: now)
            await nextMainQueueTurn()

            XCTAssertEqual(store.externalReminderRescheduleGeneration, 1)
            XCTAssertEqual(calendar.service.reconciliationCount, 1)
            XCTAssertEqual(Set(calendar.pending.values.map { $0.content.body }),
                           Set([localEvent.title, external.title]))
            XCTAssertEqual(daily.submissions.map(\.identifier).sorted(),
                           ["diary-daily-reminder", "today-overview-reminder"])
            let overview = try XCTUnwrap(daily.pending["today-overview-reminder"])
            XCTAssertTrue(overview.content.body.contains(external.title))
            XCTAssertFalse(overview.content.body.contains("Older calendar snapshot"))
            let diary = try XCTUnwrap(daily.pending["diary-daily-reminder"])
            let trigger = try XCTUnwrap(diary.trigger as? UNCalendarNotificationTrigger)
            XCTAssertEqual(trigger.dateComponents,
                           Calendar.current.dateComponents([.year, .month, .day, .hour, .minute],
                                                           from: date(day: 8, hour: 21, minute: 30)))
        }
    }

    func testLaterActiveRefreshBeforeNextReminder_preservesExistingCalendarPlan() async throws {
        try await withNotificationDefaults {
            let now = date(day: 8, hour: 7)
            let calendar = StartupNotificationRecorder(now: now)
            let daily = StartupNotificationRecorder(now: now)
            let store = try makeStore(events: [recurringEvent()], calendar: calendar, daily: daily)

            store.refreshNotificationsAfterStartup(referenceDate: now)
            await nextMainQueueTurn()
            let pending = Set(calendar.pending.keys)
            let submissions = calendar.submissions.count
            XCTAssertFalse(pending.isEmpty)

            store.refreshNotificationsAfterStartup(referenceDate: now.addingTimeInterval(60))
            store.refreshNotificationsAfterStartup(referenceDate: now.addingTimeInterval(120))
            await nextMainQueueTurn()

            XCTAssertEqual(store.externalReminderRescheduleGeneration, 1)
            XCTAssertEqual(calendar.service.reconciliationCount, 1)
            XCTAssertEqual(calendar.submissions.count, submissions)
            XCTAssertEqual(Set(calendar.pending.keys), pending)
        }
    }

    func testOrdinaryInjectedStore_keepsManualReminderUpdatesImmediate() async throws {
        try await withNotificationDefaults {
            let now = date(day: 8, hour: 7)
            let calendar = StartupNotificationRecorder(now: now)
            let daily = StartupNotificationRecorder(now: now)
            let store = try makeStore(events: [recurringEvent()], calendar: calendar, daily: daily,
                                      defersUntilStartup: false)

            store.rescheduleExternalEventNotifications(referenceDate: now)
            store.rescheduleTodayOverviewReminderIfNeeded(referenceDate: now)
            await nextMainQueueTurn()

            XCTAssertEqual(store.externalReminderRescheduleGeneration, 1)
            XCTAssertFalse(calendar.pending.isEmpty)
            XCTAssertNotNil(daily.pending["today-overview-reminder"])
        }
    }

    func testWrittenDiaryBeforeStartup_schedulesFollowingDayUsingRefreshDate() async throws {
        try await withNotificationDefaults {
            let now = date(day: 8, hour: 7)
            let calendar = StartupNotificationRecorder(now: now)
            let daily = StartupNotificationRecorder(now: now)
            let store = try makeStore(events: [], calendar: calendar, daily: daily)
            store.appState.diaryReminderEnabled = true
            store.appState.diaryReminderHour = 21
            store.appState.diaryReminderMinute = 30
            store.diaryEntries = [DiaryEntry(date: now, text: "今日の日記を書き終えた")]

            store.refreshNotificationsAfterStartup(referenceDate: now)

            let diary = try XCTUnwrap(daily.pending["diary-daily-reminder"])
            let trigger = try XCTUnwrap(diary.trigger as? UNCalendarNotificationTrigger)
            XCTAssertEqual(trigger.dateComponents,
                           Calendar.current.dateComponents([.year, .month, .day, .hour, .minute],
                                                           from: date(day: 9, hour: 21, minute: 30)))
        }
    }

    func testWrittenDiaryOnSpringForwardDay_preservesRequestedTimeOnFollowingDay() async throws {
        try await withNotificationDefaults {
            let previousTimeZone = NSTimeZone.default
            defer { NSTimeZone.default = previousTimeZone }
            NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
            let localCalendar = Calendar.current
            let now = try XCTUnwrap(localCalendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 0)))
            let calendar = StartupNotificationRecorder(now: now)
            let daily = StartupNotificationRecorder(now: now)
            let store = try makeStore(events: [], calendar: calendar, daily: daily)
            store.appState.diaryReminderEnabled = true
            store.appState.diaryReminderHour = 2
            store.appState.diaryReminderMinute = 30
            store.diaryEntries = [DiaryEntry(date: now, text: "今日の日記を書き終えた")]

            store.refreshNotificationsAfterStartup(referenceDate: now)

            let diary = try XCTUnwrap(daily.pending["diary-daily-reminder"])
            let trigger = try XCTUnwrap(diary.trigger as? UNCalendarNotificationTrigger)
            // March 8 has no 02:30. Resolving that time on March 8 before
            // advancing the day would incorrectly carry 03:00 into March 9.
            let expected = try XCTUnwrap(localCalendar.date(from:
                DateComponents(year: 2026, month: 3, day: 9, hour: 2, minute: 30)))
            XCTAssertEqual(trigger.dateComponents,
                           localCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: expected))
        }
    }

    func testDisabledDailyReminders_preservesPendingUntilStartupThenCancelsThem() async throws {
        try await withNotificationDefaults {
            let now = date(day: 8, hour: 7)
            let calendar = StartupNotificationRecorder(now: now)
            let daily = StartupNotificationRecorder(now: now)
            let store = try makeStore(events: [], calendar: calendar, daily: daily)
            daily.service.scheduleDiaryReminder(hour: 21, minute: 0)
            daily.service.scheduleTodayOverviewReminder(fireDate: date(day: 8, hour: 8), body: "Previous overview")
            daily.submissions.removeAll()
            daily.cancellations.removeAll()
            NotificationSettingsManager.shared.isTodayOverviewNotificationEnabled = false

            store.rescheduleDiaryReminderIfNeeded(referenceDate: now)
            store.rescheduleTodayOverviewReminderIfNeeded(referenceDate: now)

            XCTAssertEqual(Set(daily.pending.keys), ["diary-daily-reminder", "today-overview-reminder"])
            XCTAssertTrue(daily.cancellations.isEmpty)

            store.refreshNotificationsAfterStartup(referenceDate: now)

            XCTAssertTrue(daily.pending.isEmpty)
            XCTAssertTrue(daily.submissions.isEmpty)
            XCTAssertEqual(Set(daily.cancellations.flatMap { $0 }),
                           ["diary-daily-reminder", "today-overview-reminder"])
        }
    }

    private func makeStore(events: [CalendarEvent], calendar: StartupNotificationRecorder,
                           daily: StartupNotificationRecorder, defersUntilStartup: Bool = true) throws -> AppDataStore {
        let persistence = PersistenceController(inMemory: true)
        for event in events { persistence.container.mainContext.insert(SDCalendarEvent(domain: event)) }
        try persistence.container.mainContext.save()
        return AppDataStore(container: persistence.container, startsBackgroundServices: false,
                            calendarNotificationService: calendar.service,
                            dailyNotificationService: daily.service,
                            defersNotificationUpdatesUntilStartup: defersUntilStartup)
    }

    private func event(title: String, hour: Int, source: String? = nil) -> CalendarEvent {
        CalendarEvent(title: title, startDate: date(day: 8, hour: hour), endDate: date(day: 8, hour: hour + 1),
                      calendarName: "Startup fixture", sourceCalendarIdentifier: source, reminderMinutes: 15)
    }

    private func recurringEvent() -> CalendarEvent {
        var result = event(title: "Recurring user title", hour: 9)
        result.recurrenceRule = EventRecurrenceRule(frequency: .daily, until: date(day: 10, hour: 0),
                                                    timeZoneIdentifier: Calendar.current.timeZone.identifier)
        return result
    }

    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2030, month: 3, day: day, hour: hour, minute: minute))!
    }

    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func withNotificationDefaults(_ body: () async throws -> Void) async rethrows {
        let keys = ["categoryNotificationSettings", "eventCategoryNotificationEnabled",
                    "todayOverviewNotificationEnabled", "todayOverviewNotificationHour",
                    "todayOverviewNotificationMinute", AppDataStore.externalCalendarEventsDefaultsKey]
        let defaults = [UserDefaults.standard,
                        UserDefaults(suiteName: PersistenceController.appGroupIdentifier) ?? .standard]
        let originals = defaults.map { store in keys.map { store.object(forKey: $0) } }
        defer {
            for (store, values) in zip(defaults, originals) {
                for (key, value) in zip(keys, values) {
                    if let value { store.set(value, forKey: key) }
                    else { store.removeObject(forKey: key) }
                }
            }
        }
        let manager = NotificationSettingsManager.shared
        manager.isEventCategoryNotificationEnabled = false
        manager.isTodayOverviewNotificationEnabled = true
        manager.todayOverviewNotificationHour = 8
        manager.todayOverviewNotificationMinute = 0
        try await body()
    }
}

@MainActor
private final class StartupNotificationRecorder {
    let now: Date
    var pending: [String: UNNotificationRequest] = [:]
    var submissions: [UNNotificationRequest] = []
    var cancellations: [[String]] = []
    lazy var service = StartupCountingNotificationService(
        referenceDate: { [unowned self] in self.now },
        requestHandler: { [unowned self] request in
            self.submissions.append(request)
            self.pending[request.identifier] = request
        }, cancellationHandler: { [unowned self] identifiers in
            self.cancellations.append(identifiers)
            for identifier in identifiers { self.pending.removeValue(forKey: identifier) }
        }
    )

    init(now: Date) { self.now = now }
}

@MainActor
private final class StartupCountingNotificationService: NotificationService {
    private(set) var reconciliationCount = 0

    override func reconcileReminders(ofTypes types: [NotificationType], requests: [UNNotificationRequest],
                                     shouldApply: @escaping () -> Bool) {
        reconciliationCount += 1
        super.reconcileReminders(ofTypes: types, requests: requests, shouldApply: shouldApply)
    }
}
