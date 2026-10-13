import XCTest
@testable import lifelify

#if DEBUG && targetEnvironment(simulator)
@MainActor
final class SimulatorDemoModeTests: XCTestCase {
    func testFreshDebugSimulatorLaunch_enablesDemoWithoutLaunchArguments() {
        XCTAssertTrue(preference())
    }

    func testExplicitOptOut_usesNormalStoreAndWinsOverOptIn() {
        XCTAssertFalse(preference(arguments: ["-simulator-demo-off", "-simulator-demo-data"], stored: true))
    }

    func testOptOutPreference_survivesOrdinaryRelaunch() {
        XCTAssertFalse(preference(stored: false))
    }

    func testExplicitOptIn_restoresDemoAfterOptOut() {
        XCTAssertTrue(preference(arguments: ["-simulator-demo-data"], stored: false))
    }

    func testScreenshotLaunch_usesIsolatedDemo() {
        XCTAssertTrue(preference(arguments: ["-screenshots-mode"], stored: false))
        XCTAssertTrue(preference(arguments: ["-ScreenshotsMode"], stored: false))
    }

    func testWidget_followsHostPreferenceAndIgnoresLaunchArguments() {
        XCTAssertFalse(preference(arguments: ["-simulator-demo-data"], isExtension: true))
        XCTAssertTrue(preference(arguments: ["-simulator-demo-off"], stored: true, isExtension: true))
        XCTAssertFalse(preference(stored: false, isExtension: true))
    }

    func testXCTestHost_neverEnablesOrSeedsDemo() {
        XCTAssertFalse(preference(arguments: ["-simulator-demo-data"], stored: true, isTesting: true))
        XCTAssertFalse(preference(isTesting: true))
    }

    func testActualXCTestHost_doesNotChangePersistedDemoPreference() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "group.lifelog.screenshots"))
        let before = defaults.object(forKey: "lifelog.simulatorDemoMode") as? Bool

        XCTAssertFalse(PersistenceController.isSimulatorDemoMode)

        XCTAssertEqual(defaults.object(forKey: "lifelog.simulatorDemoMode") as? Bool, before)
    }

    private func preference(arguments: Set<String> = [], stored: Bool? = nil,
                            isExtension: Bool = false, isTesting: Bool = false) -> Bool {
        PersistenceController.simulatorDemoModePreference(arguments: arguments, storedPreference: stored,
                                                        isRunningInExtension: isExtension, isRunningTests: isTesting)
    }
}
#endif
