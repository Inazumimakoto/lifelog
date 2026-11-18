import XCTest
@testable import lifelify

@MainActor final class MonetizationPolicyTests: XCTestCase {
    nonisolated deinit {}
    func testCurrentBillingDisabledRelease_preservesUnlimitedListsAndDiaryMediaInEveryStorefront() {
        XCTAssertTrue(MonetizationPolicy.isBillingTemporarilyDisabled)
        for country in ["JP", "US", "KR", "CN", "TW", ""] {
            let policy = MonetizationPolicy(storefrontCountryCode: country, hasPremiumEntitlement: false)
            XCTAssertTrue(policy.isPremiumUnlocked)
            XCTAssertTrue(policy.canAddHabit(activeHabitCount: 10_000))
            XCTAssertTrue(policy.canAddCountdown(currentCount: 10_000))
            XCTAssertNil(policy.activeHabitLimit); XCTAssertNil(policy.anniversaryLimit)
            XCTAssertNil(policy.diaryPhotoLimit)
        }
    }

    func testDormantFreePolicy_keepsListLimitsAndUnlimitedDiaryMedia() {
        let policy = MonetizationPolicy(billingDisabled: false, storefrontCountryCode: "US", hasPremiumEntitlement: false)
        XCTAssertFalse(policy.isPremiumUnlocked)
        XCTAssertTrue(policy.canAddHabit(activeHabitCount: 2)); XCTAssertFalse(policy.canAddHabit(activeHabitCount: 3))
        XCTAssertTrue(policy.canAddCountdown(currentCount: 0)); XCTAssertFalse(policy.canAddCountdown(currentCount: 1))
        XCTAssertNil(policy.diaryPhotoLimit)
    }

    func testJapanOrVerifiedNativeEntitlement_unlocksListsAndUnlimitedDiaryMedia() {
        for policy in [
            MonetizationPolicy(billingDisabled: false, storefrontCountryCode: "jp", hasPremiumEntitlement: false),
            MonetizationPolicy(billingDisabled: false, storefrontCountryCode: "US", hasPremiumEntitlement: true)
        ] {
            XCTAssertTrue(policy.isPremiumUnlocked)
            XCTAssertTrue(policy.canAddHabit(activeHabitCount: 100)); XCTAssertTrue(policy.canAddCountdown(currentCount: 100))
            XCTAssertNil(policy.diaryPhotoLimit)
        }
    }
}
