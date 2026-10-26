import XCTest
@testable import lifelify

@MainActor final class MonetizationPolicyTests: XCTestCase {
    nonisolated deinit {}
    func testCurrentBillingDisabledRelease_preservesUnlimitedListsAndTenPhotoCapInEveryStorefront() {
        XCTAssertTrue(MonetizationPolicy.isBillingTemporarilyDisabled)
        for country in ["JP", "US", "KR", "CN", "TW", ""] {
            let policy = MonetizationPolicy(storefrontCountryCode: country, hasPremiumEntitlement: false)
            XCTAssertTrue(policy.isPremiumUnlocked)
            XCTAssertTrue(policy.canAddHabit(activeHabitCount: 10_000))
            XCTAssertTrue(policy.canAddCountdown(currentCount: 10_000))
            XCTAssertNil(policy.activeHabitLimit); XCTAssertNil(policy.anniversaryLimit)
            XCTAssertEqual(policy.diaryPhotoLimit, 10)
        }
    }

    func testDormantFreePolicy_keepsExistingThreeHabitOneAnniversaryAndThreePhotoRules() {
        let policy = MonetizationPolicy(billingDisabled: false, storefrontCountryCode: "US", hasPremiumEntitlement: false)
        XCTAssertFalse(policy.isPremiumUnlocked)
        XCTAssertTrue(policy.canAddHabit(activeHabitCount: 2)); XCTAssertFalse(policy.canAddHabit(activeHabitCount: 3))
        XCTAssertTrue(policy.canAddCountdown(currentCount: 0)); XCTAssertFalse(policy.canAddCountdown(currentCount: 1))
        XCTAssertEqual(policy.diaryPhotoLimit, 3)
    }

    func testJapanOrVerifiedNativeEntitlement_unlocksListsWhileRetainingTenPhotoCap() {
        for policy in [
            MonetizationPolicy(billingDisabled: false, storefrontCountryCode: "jp", hasPremiumEntitlement: false),
            MonetizationPolicy(billingDisabled: false, storefrontCountryCode: "US", hasPremiumEntitlement: true)
        ] {
            XCTAssertTrue(policy.isPremiumUnlocked)
            XCTAssertTrue(policy.canAddHabit(activeHabitCount: 100)); XCTAssertTrue(policy.canAddCountdown(currentCount: 100))
            XCTAssertEqual(policy.diaryPhotoLimit, 10)
        }
    }
}
