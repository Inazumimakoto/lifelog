import Foundation
@preconcurrency import UserNotifications
import os

/// Notification-center IPC never runs on the app's default MainActor.
/// Each burst reconciles with the OS, then serializes mutations through completion.
/// See docs/requirements.md §6 (responsive startup).
nonisolated final class NotificationRequestDispatcher: @unchecked Sendable {
    private enum Operation {
        case submit(UNNotificationRequest, String)
        case cancel([String])
        case reconcile([String], [UNNotificationRequest]?, NotificationMutationGuard)
    }

    private let backend: any NotificationRequestBackend
    private let queue = DispatchQueue(label: "lifelify.notifications", qos: .utility)
    private var operations: [Operation] = []
    private var isRunning = false
    private var pending: [String: UNNotificationRequest] = [:]
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lifelog", category: "notifications")

    init(backend: any NotificationRequestBackend = SystemNotificationRequestBackend()) {
        self.backend = backend
    }

    func submit(_ request: UNNotificationRequest, errorMessage: String) {
        enqueue(.submit(request, errorMessage))
    }

    func cancel(identifiers: [String]) {
        enqueue(.cancel(identifiers))
    }

    /// A nil desired plan means cancel the matching types. An empty plan means
    /// reconcile them to empty. Both preserve unrelated notification types.
    func reconcile(prefixes: [String], requests: [UNNotificationRequest]?, validation mutationGuard: NotificationMutationGuard) {
        enqueue(.reconcile(prefixes, requests, mutationGuard))
    }

    func requestAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: granted) }
                }
            }
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            queue.async {
                UNUserNotificationCenter.current().getNotificationSettings { settings in
                    continuation.resume(returning: settings.authorizationStatus)
                }
            }
        }
    }

    /// Also makes deterministic backend tests wait through asynchronous callbacks.
    func waitUntilIdle() async {
        await withCheckedContinuation { continuation in
            queue.async {
                if self.isRunning { self.idleWaiters.append(continuation) }
                else { continuation.resume() }
            }
        }
    }

    private func enqueue(_ operation: Operation) {
        queue.async {
            self.operations.append(operation)
            guard !self.isRunning else { return }
            self.isRunning = true
            self.backend.getPendingRequests { requests in
                self.queue.async {
                    self.pending = requests.reduce(into: [:]) { $0[$1.identifier] = $1 }
                    self.processNext()
                }
            }
        }
    }

    private func processNext() {
        guard !operations.isEmpty else {
            // Do not retain a process-local belief that a delivered/removed
            // notification still exists. The next burst reads the OS again.
            pending.removeAll()
            isRunning = false
            let waiters = idleWaiters
            idleWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
            return
        }
        switch operations.removeFirst() {
        case let .submit(request, errorMessage):
            submitIfChanged(request, errorMessage: errorMessage) { self.processNext() }
        case let .cancel(identifiers):
            removeExisting(identifiers)
            queue.async { self.processNext() }
        case let .reconcile(prefixes, requests, mutationGuard):
            // The predicate owns MainActor state (for example the calendar plan
            // generation). Pause this FIFO while validating after the OS read.
            DispatchQueue.main.async {
                let allowed = mutationGuard.shouldApply()
                self.queue.async {
                    guard allowed else { self.processNext(); return }
                    let desired = requests?.filter { request in
                        prefixes.contains { request.identifier.hasPrefix($0) }
                    } ?? []
                    let desiredIDs = Set(desired.map(\.identifier))
                    let obsolete = self.pending.keys.filter { identifier in
                        prefixes.contains { identifier.hasPrefix($0) } && !desiredIDs.contains(identifier)
                    }
                    self.removeExisting(obsolete)
                    self.submitPlan(desired, index: 0) {
                        DispatchQueue.main.async { mutationGuard.completeIfCurrent() }
                        self.processNext()
                    }
                }
            }
        }
    }

    private func submitPlan(_ requests: [UNNotificationRequest], index: Int, completion: @escaping @Sendable () -> Void) {
        guard index < requests.count else { completion(); return }
        submitIfChanged(requests[index], errorMessage: "通知スケジュールエラー") {
            self.submitPlan(requests, index: index + 1, completion: completion)
        }
    }

    private func submitIfChanged(_ request: UNNotificationRequest, errorMessage: String, completion: @escaping @Sendable () -> Void) {
        if let existing = pending[request.identifier], Self.hasSameReservation(existing, request) {
            // Continue on the queue without growing the stack for a large plan
            // containing only unchanged reservations.
            queue.async(execute: completion)
            return
        }
        backend.add(request) { error in
            self.queue.async {
                if let error {
                    Self.logger.error("\(errorMessage): \(error)")
                } else {
                    // A failed submission must remain eligible for retry, even
                    // when an identical request is queued in this same burst.
                    self.pending[request.identifier] = request
                }
                completion()
            }
        }
    }

    private func removeExisting(_ identifiers: [String]) {
        let existing = identifiers.filter { pending[$0] != nil }
        guard !existing.isEmpty else { return }
        backend.remove(identifiers: existing)
        for identifier in existing { pending.removeValue(forKey: identifier) }
    }

    static func hasSameReservation(_ lhs: UNNotificationRequest, _ rhs: UNNotificationRequest) -> Bool {
        guard lhs.identifier == rhs.identifier, lhs.content.isEqual(rhs.content) else { return false }
        switch (lhs.trigger, rhs.trigger) {
        case (nil, nil): return true
        case let (left?, right?): return left.isEqual(right)
        default: return false
        }
    }
}

@MainActor
final class NotificationMutationGuard {
    let shouldApply: () -> Bool
    private let completion: (() -> Void)?

    init(shouldApply: @escaping () -> Bool, completion: (() -> Void)? = nil) {
        self.shouldApply = shouldApply
        self.completion = completion
    }

    // No actor-bound teardown; match NotificationService on older Swift runtimes.
    nonisolated deinit {}

    func completeIfCurrent() {
        guard shouldApply() else { return }
        completion?()
    }
}

/// Injectable at the IPC boundary; service request/cancellation handlers remain
/// synchronous for domain tests that record generated notification plans.
nonisolated protocol NotificationRequestBackend: Sendable {
    func getPendingRequests(completion: @escaping @Sendable ([UNNotificationRequest]) -> Void)
    func add(_ request: UNNotificationRequest, completion: @escaping @Sendable (Error?) -> Void)
    func remove(identifiers: [String])
}

nonisolated struct SystemNotificationRequestBackend: NotificationRequestBackend {
    func getPendingRequests(completion: @escaping @Sendable ([UNNotificationRequest]) -> Void) {
        UNUserNotificationCenter.current().getPendingNotificationRequests(completionHandler: completion)
    }

    func add(_ request: UNNotificationRequest, completion: @escaping @Sendable (Error?) -> Void) {
        UNUserNotificationCenter.current().add(request, withCompletionHandler: completion)
    }

    func remove(identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
