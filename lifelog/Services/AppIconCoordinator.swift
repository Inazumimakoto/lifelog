import Combine
import OSLog
import UIKit

@MainActor
protocol AppIconBackend {
    var isApplicationActive: Bool { get }
    var supportsAlternateIcons: Bool { get }
    var alternateIconName: String? { get }
    func setAlternateIconName(_ name: String?, completion: @escaping @MainActor (Bool) -> Void)
}

private struct UIKitAppIconBackend: AppIconBackend {
    var isApplicationActive: Bool { UIApplication.shared.applicationState == .active }
    var supportsAlternateIcons: Bool { UIApplication.shared.supportsAlternateIcons }
    var alternateIconName: String? { UIApplication.shared.alternateIconName }

    func setAlternateIconName(_ name: String?, completion: @escaping @MainActor (Bool) -> Void) {
        UIApplication.shared.setAlternateIconName(name) { error in
            if let error {
                let issue = error as NSError
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "lifelify", category: "AppIcon")
                    .error("Could not apply icon \(name ?? "primary", privacy: .public): \(issue.domain, privacy: .public) \(issue.code) — \(issue.localizedDescription, privacy: .public)")
            }
            let succeeded = error == nil
            _Concurrency.Task { @MainActor in completion(succeeded) }
        }
    }
}

/// SpringBoard changes the icon for the entire app and can show a confirmation
/// for each write. Commit only the final choice once all theme editors close.
@MainActor
final class AppIconCoordinator: ObservableObject {
    enum Failure: Equatable {
        case unsupported
        case changeFailed
    }

    // A nil name is a real target (the primary icon). A nil Target means no
    // request has been made yet.
    private struct Target: Equatable {
        let name: String?
    }

    @Published private(set) var failure: Failure?
    private let backend: AppIconBackend
    private var foregroundNotification: AnyCancellable?
    private var desired: Target?
    private var inFlight: Target?
    private var failed: Target?
    private var lastSuccess: Target?
    private var editorCount = 0
    private var isActive = false
    private var isQueued = false

    convenience init() {
        self.init(backend: UIKitAppIconBackend())
        // The scene may report active just before UIApplication does.
        foregroundNotification = NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleUpdate() }
    }

    init(backend: AppIconBackend) {
        self.backend = backend
    }

    func update(targetName: String?, isActive: Bool) {
        let target = Target(name: targetName)
        if target != desired {
            desired = target
            clearFailure()
        }
        self.isActive = isActive
        scheduleUpdate()
    }

    func beginEditing() {
        editorCount += 1
        // SpringBoard may publish the new icon after the UIKit completion.
        if let failed, backend.alternateIconName == failed.name {
            clearFailure()
        }
    }

    func endEditing() {
        guard editorCount > 0 else { return }
        editorCount -= 1
        scheduleUpdate()
    }

    func retry() {
        clearFailure()
        scheduleUpdate()
    }

    private func clearFailure() {
        failed = nil
        if failure != nil { failure = nil }
    }

    private var canApply: Bool {
        isActive && editorCount == 0 && backend.isApplicationActive
    }

    private func scheduleUpdate() {
        guard !isQueued, inFlight == nil, desired != nil, canApply else { return }
        isQueued = true
        // SwiftUI can deliver the final preference and onDisappear in either
        // order. Read the latest preference on the next main-queue turn.
        DispatchQueue.main.async { [weak self] in self?.applyIfNeeded() }
    }

    private func applyIfNeeded() {
        isQueued = false
        guard canApply, inFlight == nil, let desired else { return }
        let installed = Target(name: backend.alternateIconName)
        // UIKit can finish before alternateIconName reflects the change.
        // Trust that completion until the system value catches up.
        if installed == lastSuccess { lastSuccess = nil }
        guard desired != (lastSuccess ?? installed) else {
            clearFailure()
            return
        }
        guard failed != desired else { return }
        guard backend.supportsAlternateIcons else {
            failed = desired
            failure = .unsupported
            return
        }
        inFlight = desired
        backend.setAlternateIconName(desired.name) { [weak self] succeeded in
            guard let self else { return }
            self.inFlight = nil
            // SpringBoard can install the icon even when presenting its
            // confirmation fails. Check the actual icon before reporting an error.
            if succeeded || self.backend.alternateIconName == desired.name {
                self.lastSuccess = desired
            } else if self.desired == desired && self.canApply {
                self.failed = desired
                self.failure = .changeFailed
                return
            }
            self.scheduleUpdate()
        }
    }
}
