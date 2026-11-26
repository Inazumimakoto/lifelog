import SwiftData
import XCTest
@testable import lifelify

@MainActor
final class InitialPermissionsEligibilityTests: XCTestCase {
    func testFreshInterruptedInstall_remainsEligibleAfterAutomaticDataAppears() {
        withDefaults { standard, shared in
            XCTAssertFalse(InitialPermissionsState.recordLaunch(standard: standard, shared: shared,
                                                               hasUserRecords: false, hasIntegrationData: false))
            XCTAssertTrue(standard.bool(forKey: InitialPermissionsState.featureSeenKey))
            XCTAssertFalse(standard.bool(forKey: InitialPermissionsState.completedKey))
            shared.set(true, forKey: AppDataStore.locationVisitTagsSeededDefaultsKey)
            shared.set(Data(), forKey: AppDataStore.externalCalendarEventsDefaultsKey)

            // This includes simulator sample records generated after the snapshot.
            XCTAssertFalse(InitialPermissionsState.recordLaunch(standard: standard, shared: shared,
                                                               hasUserRecords: true, hasIntegrationData: true))
        }
    }

    func testInterruptedLegacyOnboarding_ignoresSeededTagsAndIntegrationCaches() {
        withDefaults { standard, shared in
            standard.set(true, forKey: "initialPermissionsSetupFeatureSeenV1")
            shared.set(true, forKey: AppDataStore.locationVisitTagsSeededDefaultsKey)
            shared.set(Data(), forKey: AppDataStore.externalCalendarRangeDefaultsKey)
            XCTAssertFalse(InitialPermissionsState.recordLaunch(standard: standard, shared: shared,
                                                               hasUserRecords: false, hasIntegrationData: true))
        }
    }

    func testCompletedOrSkippedBeforeUpgrade_preservesCompletionOnEmptyStore() {
        withDefaults { standard, shared in
            standard.set(true, forKey: "initialPermissionsSetupCompletedV1")
            XCTAssertTrue(InitialPermissionsState.recordLaunch(standard: standard, shared: shared,
                                                              hasUserRecords: false, hasIntegrationData: false))
        }
    }

    func testInstallPredatingOnboarding_recognizesExistingSharedLegacyData() {
        withDefaults { standard, shared in
            shared.set(true, forKey: AppDataStore.locationVisitTagsSeededDefaultsKey)
            XCTAssertTrue(InitialPermissionsState.recordLaunch(standard: standard, shared: shared,
                                                              hasUserRecords: false, hasIntegrationData: false))
            XCTAssertFalse(standard.bool(forKey: InitialPermissionsState.completedKey))
        }
    }

    func testExistingSwiftDataTask_skipsSetupUsingStoredRecord() throws {
        let container = PersistenceController(inMemory: true).container
        container.mainContext.insert(SDTask(domain: Task(title: "Saved task")))
        try container.mainContext.save()
        let store = AppDataStore(container: container, startsBackgroundServices: false)
        withDefaults { standard, shared in
            store.recordInitialPermissionsFootprint(standard: standard, shared: shared)
            XCTAssertTrue(store.hasExistingUserFootprintForInitialPermissions)
        }
    }

    private func withDefaults(_ body: (UserDefaults, UserDefaults) -> Void) {
        let standardName = UUID().uuidString
        let sharedName = UUID().uuidString
        let standard = UserDefaults(suiteName: standardName)!
        let shared = UserDefaults(suiteName: sharedName)!
        defer {
            standard.removePersistentDomain(forName: standardName)
            shared.removePersistentDomain(forName: sharedName)
        }
        body(standard, shared)
    }
}
