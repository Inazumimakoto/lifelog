import Foundation
import UserNotifications
import XCTest
@testable import lifelify

@MainActor
final class NotificationRequestDispatcherTests: XCTestCase {
    func testPersistedIdenticalReservation_skipsSubmissionAcrossDispatcherInstances() async {
        let existing = request("diary-daily-reminder")
        let backend = RecordingNotificationBackend(pending: [existing])
        let firstLaunch = NotificationRequestDispatcher(backend: backend)
        firstLaunch.submit(request(existing.identifier), errorMessage: "test")
        await firstLaunch.waitUntilIdle()
        let nextLaunch = NotificationRequestDispatcher(backend: backend)
        nextLaunch.submit(request(existing.identifier), errorMessage: "test")
        await nextLaunch.waitUntilIdle()

        XCTAssertEqual(backend.snapshot().readCount, 2)
        XCTAssertTrue(backend.snapshot().added.isEmpty)
        XCTAssertTrue(backend.snapshot().removed.isEmpty)
    }

    func testChangedContentTriggerAndUserInfo_eachReplaceExistingReservation() async {
        let backend = RecordingNotificationBackend(pending: [request("letter-one")])
        let dispatcher = NotificationRequestDispatcher(backend: backend)
        for desired in [request("letter-one", body: "Changed"),
                        request("letter-one", body: "Changed", hour: 12),
                        request("letter-one", body: "Changed", hour: 12, userInfo: ["letterID": "one"])] {
            dispatcher.submit(desired, errorMessage: "test")
            await dispatcher.waitUntilIdle()
        }

        XCTAssertEqual(backend.snapshot().added.count, 3)
        XCTAssertTrue(backend.snapshot().removed.isEmpty)
        XCTAssertEqual(backend.snapshot().pending["letter-one"]?.content.userInfo["letterID"] as? String, "one")
    }

    func testDeliveredBetweenBursts_identicalRequestIsSubmittedAgain() async {
        let backend = RecordingNotificationBackend()
        let dispatcher = NotificationRequestDispatcher(backend: backend)
        let desired = request("task-one")
        dispatcher.submit(desired, errorMessage: "test")
        await dispatcher.waitUntilIdle()
        backend.simulateDelivery(identifier: desired.identifier)

        dispatcher.submit(request(desired.identifier), errorMessage: "test")
        await dispatcher.waitUntilIdle()

        XCTAssertEqual(backend.snapshot().added.count, 2)
        XCTAssertNotNil(backend.snapshot().pending[desired.identifier])
    }

    func testFailedSubmission_doesNotSuppressIdenticalRetryInSameBurst() async {
        let backend = RecordingNotificationBackend(failures: 1)
        let dispatcher = NotificationRequestDispatcher(backend: backend)
        let desired = request("task-one")
        dispatcher.submit(desired, errorMessage: "expected failure")
        dispatcher.submit(desired, errorMessage: "retry")
        await dispatcher.waitUntilIdle()

        XCTAssertEqual(backend.snapshot().added.count, 2)
        XCTAssertNotNil(backend.snapshot().pending[desired.identifier])
    }

    func testRapidReplaceCancelAndAdd_waitForPreviousAddCompletionAndKeepLatestRequest() async {
        let firstStarted = expectation(description: "first add started")
        let secondStarted = expectation(description: "second add started")
        let backend = RecordingNotificationBackend(holdsAdds: true, addObserver: { count in
            if count == 1 { firstStarted.fulfill() }
            if count == 2 { secondStarted.fulfill() }
        })
        let dispatcher = NotificationRequestDispatcher(backend: backend)
        dispatcher.submit(request("task-one", body: "Old"), errorMessage: "test")
        dispatcher.cancel(identifiers: ["task-one"])
        dispatcher.submit(request("task-one", body: "Newest"), errorMessage: "test")
        await fulfillment(of: [firstStarted], timeout: 2)
        XCTAssertTrue(backend.snapshot().removed.isEmpty)
        XCTAssertEqual(backend.snapshot().added.count, 1)

        backend.finishNextAdd()
        await fulfillment(of: [secondStarted], timeout: 2)
        XCTAssertEqual(backend.snapshot().removed, ["task-one"])
        backend.finishNextAdd()
        await dispatcher.waitUntilIdle()

        XCTAssertEqual(backend.snapshot().pending["task-one"]?.content.body, "Newest")
        XCTAssertEqual(backend.snapshot().events, ["read", "add:Old", "remove:task-one", "add:Newest"])
    }

    func testReconcilePlan_updatesOnlyChangedOrMissingRequestsAndRemovesOnlyObsoleteType() async {
        let keep = request("external-event-keep")
        let changed = request("recurring-event-change", body: "Old")
        let obsolete = request("external-event-obsolete")
        let unrelated = request("task-unrelated")
        let backend = RecordingNotificationBackend(pending: [keep, changed, obsolete, unrelated])
        let dispatcher = NotificationRequestDispatcher(backend: backend)
        dispatcher.reconcile(prefixes: ["external-event-", "recurring-event-"],
                             requests: [request(keep.identifier), request(changed.identifier, body: "New"), request("recurring-event-missing")],
                             validation: NotificationMutationGuard(shouldApply: { true }))
        await dispatcher.waitUntilIdle()

        XCTAssertEqual(backend.snapshot().removed, [obsolete.identifier])
        XCTAssertEqual(Set(backend.snapshot().added.map(\.identifier)), Set([changed.identifier, "recurring-event-missing"]))
        XCTAssertEqual(Set(backend.snapshot().pending.keys), Set([keep.identifier, changed.identifier, "recurring-event-missing", unrelated.identifier]))
    }

    func testStaleReconciliationAfterDelayedRead_cannotReplaceNewerPlan() async {
        let readStarted = expectation(description: "pending read started")
        let backend = RecordingNotificationBackend(pending: [request("recurring-event-old"), request("task-unrelated")],
                                                   holdsReads: true, readObserver: { readStarted.fulfill() })
        let dispatcher = NotificationRequestDispatcher(backend: backend)
        var generation = 1
        dispatcher.reconcile(prefixes: ["recurring-event-"], requests: [request("recurring-event-stale")],
                             validation: NotificationMutationGuard(shouldApply: { generation == 1 }))
        await fulfillment(of: [readStarted], timeout: 2)
        generation = 2
        dispatcher.reconcile(prefixes: ["recurring-event-"], requests: [request("recurring-event-newest")],
                             validation: NotificationMutationGuard(shouldApply: { generation == 2 }))
        backend.finishNextRead()
        await dispatcher.waitUntilIdle()

        XCTAssertEqual(backend.snapshot().added.map(\.identifier), ["recurring-event-newest"])
        XCTAssertEqual(backend.snapshot().removed, ["recurring-event-old"])
        XCTAssertEqual(Set(backend.snapshot().pending.keys), Set(["recurring-event-newest", "task-unrelated"]))
    }

    func testCancellationSkipsMissingIdentifiersAndBackendOperationsRunOffMain() async {
        let backend = RecordingNotificationBackend(pending: [request("task-remove")])
        let dispatcher = NotificationRequestDispatcher(backend: backend)
        dispatcher.cancel(identifiers: ["task-missing", "task-remove"])
        dispatcher.submit(request("task-new"), errorMessage: "test")
        await dispatcher.waitUntilIdle()

        XCTAssertEqual(backend.snapshot().removed, ["task-remove"])
        XCTAssertFalse(backend.snapshot().calledOnMain)
        XCTAssertEqual(Set(backend.snapshot().pending.keys), Set(["task-new"]))
    }

    func testCancelAllAfterDelayedRead_rechecksGenerationAndDoesNotCallStaleCompletion() async {
        let readStarted = expectation(description: "pending read started")
        let backend = RecordingNotificationBackend(pending: [request("recurring-event-current")],
                                                   holdsReads: true, readObserver: { readStarted.fulfill() })
        let dispatcher = NotificationRequestDispatcher(backend: backend)
        let service = NotificationService(requestDispatcher: dispatcher)
        var isCurrent = true
        var didComplete = false
        service.cancelAllReminders(ofTypes: [.recurringEvent], shouldCancel: { isCurrent },
                                    completion: { didComplete = true })
        await fulfillment(of: [readStarted], timeout: 2)
        isCurrent = false
        backend.finishNextRead()
        await dispatcher.waitUntilIdle()

        XCTAssertFalse(didComplete)
        XCTAssertTrue(backend.snapshot().removed.isEmpty)
        XCTAssertNotNil(backend.snapshot().pending["recurring-event-current"])
    }

    func testServiceRealPath_repeatedDiaryAndOverviewSkipUnchangedOSRequests() async {
        let backend = RecordingNotificationBackend()
        let dispatcher = NotificationRequestDispatcher(backend: backend)
        let now = Calendar.current.date(from: DateComponents(year: 2030, month: 3, day: 8, hour: 8))!
        let service = NotificationService(referenceDate: { now }, requestDispatcher: dispatcher)
        for _ in 0..<2 {
            service.scheduleDiaryReminder(hour: 21, minute: 0)
            service.scheduleTodayOverviewReminder(fireDate: now.addingTimeInterval(3_600), body: "Same overview")
            await dispatcher.waitUntilIdle()
        }

        XCTAssertEqual(backend.snapshot().added.count, 2)
        XCTAssertTrue(backend.snapshot().removed.isEmpty)
        XCTAssertFalse(backend.snapshot().calledOnMain)
    }

    func testLetterOpeningDuringDelayedReadAndSubmission_cancelsQueuedLetterAndPreservesUnrelatedRequest() async {
        let readStarted = expectation(description: "pending read started")
        let addStarted = expectation(description: "letter add started")
        let backend = RecordingNotificationBackend(pending: [request("task-unrelated")], holdsAdds: true, holdsReads: true,
                                                   addObserver: { _ in addStarted.fulfill() },
                                                   readObserver: { readStarted.fulfill() })
        let dispatcher = NotificationRequestDispatcher(backend: backend)
        let service = NotificationService(requestDispatcher: dispatcher)
        let letterID = UUID()
        let identifier = "letter-\(letterID.uuidString)"
        service.scheduleCalendarNotification(identifier: identifier, title: "Letter", body: "Sealed letter",
                                             components: DateComponents(year: 2030, month: 3, day: 9, hour: 9),
                                             userInfo: ["letterID": letterID.uuidString], errorMessage: "test")
        service.cancelLetterReminder(letterID: letterID)
        await fulfillment(of: [readStarted], timeout: 2)
        XCTAssertTrue(backend.snapshot().added.isEmpty)
        backend.finishNextRead()
        await fulfillment(of: [addStarted], timeout: 2)
        XCTAssertTrue(backend.snapshot().removed.isEmpty)
        backend.finishNextAdd()
        await dispatcher.waitUntilIdle()

        XCTAssertEqual(backend.snapshot().added.map(\.identifier), [identifier])
        XCTAssertEqual(backend.snapshot().removed, [identifier])
        XCTAssertEqual(Set(backend.snapshot().pending.keys), Set(["task-unrelated"]))
        XCTAssertFalse(backend.snapshot().calledOnMain)
    }

    private func request(_ identifier: String, body: String = "Body", hour: Int = 9,
                         userInfo: [AnyHashable: Any] = [:]) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Reminder"
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(year: 2030, month: 3, day: 9, hour: hour, minute: 0), repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }
}

/// Reads capture a snapshot immediately; writes take effect when their callback
/// completes. This exposes races hidden by synchronous request-only recorders.
nonisolated private final class RecordingNotificationBackend: NotificationRequestBackend, @unchecked Sendable {
    struct Snapshot {
        var pending: [String: UNNotificationRequest]
        var added: [UNNotificationRequest]
        var removed: [String]
        var readCount: Int
        var calledOnMain: Bool
        var events: [String]
    }

    private let lock = NSLock()
    private var state: Snapshot
    private let holdsAdds: Bool
    private let holdsReads: Bool
    private var failures: Int
    private let addObserver: (@Sendable (Int) -> Void)?
    private let readObserver: (@Sendable () -> Void)?
    private var heldReads: [(@Sendable ([UNNotificationRequest]) -> Void, [UNNotificationRequest])] = []
    private var heldAdds: [(UNNotificationRequest, @Sendable (Error?) -> Void)] = []

    init(pending: [UNNotificationRequest] = [], failures: Int = 0, holdsAdds: Bool = false, holdsReads: Bool = false,
         addObserver: (@Sendable (Int) -> Void)? = nil, readObserver: (@Sendable () -> Void)? = nil) {
        state = Snapshot(pending: pending.reduce(into: [:]) { $0[$1.identifier] = $1 }, added: [], removed: [], readCount: 0, calledOnMain: false, events: [])
        self.failures = failures
        self.holdsAdds = holdsAdds
        self.holdsReads = holdsReads
        self.addObserver = addObserver
        self.readObserver = readObserver
    }

    func getPendingRequests(completion: @escaping @Sendable ([UNNotificationRequest]) -> Void) {
        lock.lock()
        state.calledOnMain = state.calledOnMain || Thread.isMainThread
        state.readCount += 1
        state.events.append("read")
        let captured = Array(state.pending.values)
        if holdsReads { heldReads.append((completion, captured)) }
        lock.unlock()
        readObserver?()
        if !holdsReads { completion(captured) }
    }

    func add(_ request: UNNotificationRequest, completion: @escaping @Sendable (Error?) -> Void) {
        lock.lock()
        state.calledOnMain = state.calledOnMain || Thread.isMainThread
        state.added.append(request)
        state.events.append("add:" + request.content.body)
        let count = state.added.count
        if holdsAdds { heldAdds.append((request, completion)) }
        let fails = failures > 0
        if fails { failures -= 1 }
        if !holdsAdds && !fails { state.pending[request.identifier] = request }
        lock.unlock()
        addObserver?(count)
        if !holdsAdds { completion(fails ? NSError(domain: "NotificationTest", code: 1) : nil) }
    }

    func remove(identifiers: [String]) {
        lock.lock()
        defer { lock.unlock() }
        state.calledOnMain = state.calledOnMain || Thread.isMainThread
        state.removed.append(contentsOf: identifiers)
        for identifier in identifiers {
            state.pending.removeValue(forKey: identifier)
            state.events.append("remove:" + identifier)
        }
    }

    func finishNextRead() {
        lock.lock()
        let next = heldReads.removeFirst()
        lock.unlock()
        next.0(next.1)
    }

    func finishNextAdd() {
        lock.lock()
        let next = heldAdds.removeFirst()
        state.pending[next.0.identifier] = next.0
        lock.unlock()
        next.1(nil)
    }

    func simulateDelivery(identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        state.pending.removeValue(forKey: identifier)
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return state
    }
}
