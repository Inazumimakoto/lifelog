import Foundation

/// Product limits shared by native capture and editing. Existing data is never truncated.
nonisolated struct MonetizationPolicy: Equatable, Sendable {
    static let isBillingTemporarilyDisabled = true
    static let freeHabitLimit = 3
    static let freeCountdownLimit = 1

    let isPremiumUnlocked: Bool

    init(billingDisabled: Bool = Self.isBillingTemporarilyDisabled,
         storefrontCountryCode: String, hasPremiumEntitlement: Bool) {
        isPremiumUnlocked = billingDisabled || storefrontCountryCode.uppercased() == "JP" || hasPremiumEntitlement
    }

    var activeHabitLimit: Int? { isPremiumUnlocked ? nil : Self.freeHabitLimit }
    // The existing native "countdown" screen counts all anniversary rows, including "since".
    var anniversaryLimit: Int? { isPremiumUnlocked ? nil : Self.freeCountdownLimit }
    var diaryPhotoLimit: Int? { nil }

    func canAddHabit(activeHabitCount: Int) -> Bool {
        activeHabitLimit.map { activeHabitCount < $0 } ?? true
    }

    func canAddCountdown(currentCount: Int) -> Bool {
        anniversaryLimit.map { currentCount < $0 } ?? true
    }
}
