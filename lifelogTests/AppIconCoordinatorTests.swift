import XCTest
@testable import lifelify

@MainActor
final class AppIconCoordinatorTests: XCTestCase {
    private final class Backend: AppIconBackend {
        var isApplicationActive = true
        var supportsAlternateIcons = true
        var alternateIconName: String?
        private(set) var requests: [String?] = []
        private var completion: (@MainActor (Bool) -> Void)?

        func setAlternateIconName(_ name: String?, completion: @escaping @MainActor (Bool) -> Void) {
            XCTAssertNil(self.completion, "Only one icon change may reach UIKit at a time")
            requests.append(name)
            self.completion = completion
        }

        func finish(succeeded: Bool = true, reflectInSystem: Bool = true) {
            guard let completion, let requested = requests.last else {
                XCTFail("Expected a pending icon change")
                return
            }
            if succeeded && reflectInSystem { alternateIconName = requested }
            self.completion = nil
            completion(succeeded)
        }
    }

    // The coordinator reads the last preference on the next main-queue turn.
    // Queue this continuation behind it; no time-based sleeps are needed.
    private func nextTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    func testLaunchWithMatchingIcon_skipsUIKitEvenAfterForegrounding() async {
        let backend = Backend()
        backend.alternateIconName = "Mint"
        let coordinator = AppIconCoordinator(backend: backend)
        coordinator.update(targetName: "Mint", isActive: true)
        await nextTurn()
        coordinator.update(targetName: "Mint", isActive: false)
        coordinator.update(targetName: "Mint", isActive: true)
        await nextTurn()
        XCTAssertTrue(backend.requests.isEmpty)
    }

    func testSettingsEdits_commitOnlyTheFinalChoiceWhenEveryEditorCloses() async {
        let backend = Backend()
        let coordinator = AppIconCoordinator(backend: backend)
        coordinator.update(targetName: "Mint", isActive: true)
        coordinator.beginEditing()
        coordinator.beginEditing()
        coordinator.update(targetName: "Sky", isActive: true)
        coordinator.update(targetName: "Rose", isActive: true)
        await nextTurn()
        coordinator.endEditing()
        await nextTurn()
        XCTAssertTrue(backend.requests.isEmpty)

        coordinator.endEditing()
        coordinator.update(targetName: "Forest", isActive: true)
        await nextTurn()
        XCTAssertEqual(backend.requests, ["Forest"])
        backend.finish()
        await nextTurn()
        XCTAssertEqual(backend.requests, ["Forest"])
    }

    func testToggleOffDuringChange_restoresPrimaryAfterSuccessEvenIfSystemValueLags() async {
        let backend = Backend()
        let coordinator = AppIconCoordinator(backend: backend)
        coordinator.update(targetName: "Mint", isActive: true)
        await nextTurn()
        coordinator.update(targetName: "Sky", isActive: true)
        coordinator.update(targetName: nil, isActive: true)
        await nextTurn()
        XCTAssertEqual(backend.requests, ["Mint"])

        backend.finish(reflectInSystem: false)
        await nextTurn()
        XCTAssertEqual(backend.requests, ["Mint", nil])
        backend.finish()
        await nextTurn()
        XCTAssertEqual(backend.requests, ["Mint", nil])
        XCTAssertNil(coordinator.failure)
    }

    func testSceneAndApplicationActivity_deferPendingChangesUntilBothAreActive() async {
        let backend = Backend()
        let coordinator = AppIconCoordinator(backend: backend)
        coordinator.update(targetName: "Sky", isActive: false)
        await nextTurn()
        XCTAssertTrue(backend.requests.isEmpty)
        backend.isApplicationActive = false
        coordinator.update(targetName: "Sky", isActive: true)
        await nextTurn()
        XCTAssertTrue(backend.requests.isEmpty)
        backend.isApplicationActive = true
        coordinator.update(targetName: "Rose", isActive: true)
        await nextTurn()
        XCTAssertEqual(backend.requests, ["Rose"])
    }

    func testFailedChange_isReportedOnceAndExplicitRetryCanSucceed() async {
        let backend = Backend()
        let coordinator = AppIconCoordinator(backend: backend)
        coordinator.update(targetName: "Mint", isActive: true)
        await nextTurn()
        backend.finish(succeeded: false)
        XCTAssertEqual(coordinator.failure, .changeFailed)
        coordinator.update(targetName: "Mint", isActive: false)
        coordinator.update(targetName: "Mint", isActive: true)
        await nextTurn()
        XCTAssertEqual(backend.requests, ["Mint"])
        XCTAssertEqual(coordinator.failure, .changeFailed)

        coordinator.retry()
        await nextTurn()
        backend.finish()
        await nextTurn()
        XCTAssertEqual(backend.requests, ["Mint", "Mint"])
        XCTAssertNil(coordinator.failure)
    }

    func testErrorAfterIconWasInstalled_recognizesAlternateAndPrimaryWithoutRetry() async {
        let backend = Backend()
        let coordinator = AppIconCoordinator(backend: backend)
        let choices: [String?] = ["Lavender", nil]
        for choice in choices {
            coordinator.update(targetName: choice, isActive: true)
            await nextTurn()
            backend.alternateIconName = choice
            backend.finish(succeeded: false)
            XCTAssertNil(coordinator.failure)
            await nextTurn()
        }
        XCTAssertEqual(backend.requests, choices)
    }

    func testOpeningSettingsAfterDelayedInstallation_clearsObsoleteError() async {
        let backend = Backend()
        let coordinator = AppIconCoordinator(backend: backend)
        coordinator.update(targetName: "Rose", isActive: true)
        await nextTurn()
        backend.finish(succeeded: false)
        XCTAssertEqual(coordinator.failure, .changeFailed)

        backend.alternateIconName = "Rose"
        coordinator.beginEditing()
        XCTAssertNil(coordinator.failure)
        coordinator.endEditing()
        await nextTurn()
        XCTAssertEqual(backend.requests, ["Rose"])
    }

    func testObsoleteFailure_isSupersededByNewestTarget() async {
        let backend = Backend()
        let coordinator = AppIconCoordinator(backend: backend)
        coordinator.update(targetName: "Mint", isActive: true)
        await nextTurn()
        coordinator.update(targetName: "Forest", isActive: true)
        backend.finish(succeeded: false)
        await nextTurn()
        XCTAssertNil(coordinator.failure)
        XCTAssertEqual(backend.requests, ["Mint", "Forest"])
    }

    func testUnsupportedDevice_reportsOnlyAChangeThatIsNeeded() async {
        let backend = Backend()
        backend.supportsAlternateIcons = false
        let coordinator = AppIconCoordinator(backend: backend)
        coordinator.update(targetName: nil, isActive: true)
        await nextTurn()
        XCTAssertNil(coordinator.failure)
        coordinator.update(targetName: "Rose", isActive: true)
        await nextTurn()
        XCTAssertEqual(coordinator.failure, .unsupported)
        coordinator.update(targetName: nil, isActive: true)
        await nextTurn()
        XCTAssertNil(coordinator.failure)
        XCTAssertTrue(backend.requests.isEmpty)
    }
}
