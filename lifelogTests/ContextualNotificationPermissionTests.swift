import Combine
import SwiftData
import UserNotifications
import XCTest
@testable import lifelify

@MainActor
final class ContextualNotificationPermissionTests: XCTestCase {
    func testCheckingSettings_doesNotAskForPermission() async {
        let service = TestNotificationService()

        let status = await service.refreshAuthorizationStatus()

        XCTAssertEqual(status, .notDetermined)
        XCTAssertEqual(service.authorizationStatus, .notDetermined)
        XCTAssertEqual(service.requests, 0)
    }

    func testConcurrentOptIns_requestOnceAndUseSystemDecision() async {
        let service = TestNotificationService()
        service.response = .denied

        async let first = service.authorizationForUserAction()
        async let second = service.authorizationForUserAction()
        let results = await [first, second]

        XCTAssertEqual(results, [.denied, .denied])
        XCTAssertEqual(service.requests, 1)
        XCTAssertEqual(service.authorizationStatus, .denied)
    }

    func testExistingAuthorization_preservesDecisionWithoutPrompting() async {
        let service = TestNotificationService()
        for existingStatus in [UNAuthorizationStatus.denied, .authorized, .provisional, .ephemeral] {
            service.status = existingStatus
            let result = await service.authorizationForUserAction()
            XCTAssertEqual(result, existingStatus)
        }
        XCTAssertEqual(service.requests, 0)
    }

    func testGrantAfterUndetermined_reportsAccessAndRestoresExistingNotifications() async {
        let service = TestNotificationService()
        var restorations = 0
        let observation = service.authorizationBecameAvailable.sink { _ in restorations += 1 }
        defer { observation.cancel() }
        let result = await service.authorizationForUserAction()
        XCTAssertEqual(result, .authorized)
        XCTAssertEqual(restorations, 1)
    }

    func testGrantInSystemSettingsAcrossLaunches_restoresOnceWithoutPrompting() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let firstLaunch = TestNotificationService(authorizationDefaults: defaults)
        firstLaunch.status = .denied
        await firstLaunch.refreshAuthorizationStatus()

        let nextLaunch = TestNotificationService(authorizationDefaults: defaults)
        nextLaunch.status = .authorized
        var restorations = 0
        let observation = nextLaunch.authorizationBecameAvailable.sink { _ in restorations += 1 }
        defer { observation.cancel() }

        await nextLaunch.refreshAuthorizationStatus()
        await nextLaunch.refreshAuthorizationStatus()
        XCTAssertEqual(restorations, 1)
        XCTAssertEqual(nextLaunch.requests, 0)
    }

    func testUpgradeWithDefaultsOnly_schedulesDiaryWithoutRewritingSwiftData() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "diaryReminderEnabled")
        defaults.set(20, forKey: "diaryReminderHour")
        let container = PersistenceController(inMemory: true).container
        let syncDate = Date(timeIntervalSince1970: 1_000)
        container.mainContext.insert(SDAppState(lastCalendarSyncDate: syncDate, diaryReminderMinute: 15))
        try container.mainContext.save()
        let now = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2030, month: 5, day: 1, hour: 9)))
        var requests: [UNNotificationRequest] = []
        let notifications = NotificationService(referenceDate: { now }, requestHandler: { requests.append($0) })
        let store = AppDataStore(container: container, startsBackgroundServices: false,
                                 calendarNotificationService: notifications, dailyNotificationService: notifications,
                                 diaryReminderDefaults: defaults, defersNotificationUpdatesUntilStartup: true)

        store.refreshNotificationsAfterStartup(referenceDate: now)

        let diary = try XCTUnwrap(requests.first { $0.identifier == "diary-daily-reminder" })
        let trigger = try XCTUnwrap(diary.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.hour, 20)
        XCTAssertEqual(trigger.dateComponents.minute, 15)
        let reader = ModelContext(container)
        let saved = try XCTUnwrap(reader.fetch(FetchDescriptor<SDAppState>()).first)
        XCTAssertFalse(saved.diaryReminderEnabled)
        XCTAssertEqual(saved.lastCalendarSyncDate, syncDate)
    }

    func testEditingAfterFailedRead_preservesOtherStoredStateAndKeepsUserChoice() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = PersistenceController(inMemory: true).container
        let syncDate = Date(timeIntervalSince1970: 1_000)
        container.mainContext.insert(SDAppState(lastCalendarSyncDate: syncDate, diaryReminderEnabled: true))
        try container.mainContext.save()
        let notifications = NotificationService(requestHandler: { _ in }, cancellationHandler: { _ in })
        let store = AppDataStore(container: container, startsBackgroundServices: false,
                                 dailyNotificationService: notifications, diaryReminderDefaults: defaults)
        XCTAssertFalse(store.loadAppState(fetch: { throw CocoaError(.fileReadUnknown) }))
        store.appState = AppState()

        store.updateDiaryReminder(enabled: false, hour: 18, minute: 5)

        let reader = ModelContext(container)
        let saved = try XCTUnwrap(reader.fetch(FetchDescriptor<SDAppState>()).first)
        XCTAssertTrue(saved.diaryReminderEnabled)
        XCTAssertEqual(saved.lastCalendarSyncDate, syncDate)
        XCTAssertTrue(store.loadAppState())
        XCTAssertFalse(store.diaryReminderEnabled)
        XCTAssertEqual(store.diaryReminderHour, 18)
        XCTAssertEqual(store.diaryReminderMinute, 5)
    }

    private final class TestNotificationService: NotificationService {
        var status: UNAuthorizationStatus = .notDetermined
        var response: UNAuthorizationStatus = .authorized
        var requests = 0

        override func getAuthorizationStatus() async -> UNAuthorizationStatus { status }

        override func requestAuthorization() async -> Bool {
            requests += 1
            status = response
            return response == .authorized
        }
    }
}
