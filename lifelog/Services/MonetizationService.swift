//
//  MonetizationService.swift
//  lifelog
//
//  Created by Codex on 2026/02/06.
//

import Foundation
import Combine
import StoreKit

@MainActor
final class MonetizationService: ObservableObject {
    static let shared = MonetizationService()

    // Replace these IDs with the final App Store Connect product IDs.
    private let subscriptionProductIDs: Set<String> = [
        "com.inazumimakoto.lifelog.premium.monthly",
        "com.inazumimakoto.lifelog.premium.yearly"
    ]
    private let lifetimeProductID = "com.inazumimakoto.lifelog.premium.lifetime"
    // Temporary release mode: all premium features are unlocked and billing is disabled.
    private let isBillingTemporarilyDisabled = true

    private var allPremiumProductIDs: Set<String> {
        var ids = subscriptionProductIDs
        ids.insert(lifetimeProductID)
        return ids
    }

    private var transactionUpdatesTask: _Concurrency.Task<Void, Never>?

    @Published private(set) var storefrontCountryCode: String = "JP"
    @Published private(set) var hasPremiumEntitlement: Bool = false
    @Published private(set) var availableProducts: [Product] = []
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var isRefreshingStatus: Bool = false
    @Published private(set) var hasLoadedProducts: Bool = false
    @Published var errorMessage: String?

    let freeHabitLimit = 3
    let freeCountdownLimit = 1
    let freeDiaryPhotoLimit = 3
    let premiumDiaryPhotoLimit = 10

#if DEBUG
    private let debugStorefrontCountryCodeKey = "debug.monetization.storefrontCountryCode"
    private let debugForcePremiumEntitlementKey = "debug.monetization.forcePremiumEntitlement"
#endif

    var isJapanStorefront: Bool {
        storefrontCountryCode.uppercased() == "JP"
    }

    var isBillingDisabled: Bool {
        isBillingTemporarilyDisabled
    }

    var isPremiumUnlocked: Bool {
        isBillingDisabled || isJapanStorefront || hasPremiumEntitlement
    }

    var canUseHabitGrass: Bool {
        isPremiumUnlocked
    }

    var canUseReviewMap: Bool {
        isPremiumUnlocked
    }

    var canUseDiaryLocation: Bool {
        isPremiumUnlocked
    }

    var canUseLetters: Bool {
        isPremiumUnlocked
    }

    var diaryPhotoLimit: Int {
        isPremiumUnlocked ? premiumDiaryPhotoLimit : freeDiaryPhotoLimit
    }

    private init() {
        refreshStorefrontCountry()
        startTransactionListener()
        _Concurrency.Task {
            await refreshStatus()
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func refreshStatus() async {
        isRefreshingStatus = true
        errorMessage = nil
        refreshStorefrontCountry()
        if isBillingDisabled {
            hasPremiumEntitlement = true
            availableProducts = []
            hasLoadedProducts = true
            isRefreshingStatus = false
            return
        }
        await refreshEntitlements()
        if isJapanStorefront == false {
            await loadProductsIfNeeded(force: false)
        } else {
            availableProducts = []
            // Force a fresh fetch if storefront later switches from JP to non-JP.
            hasLoadedProducts = false
        }
        isRefreshingStatus = false
    }

    func canAddHabit(activeHabitCount: Int) -> Bool {
        guard isPremiumUnlocked == false else { return true }
        return activeHabitCount < freeHabitLimit
    }

    func canAddCountdown(currentCount: Int) -> Bool {
        guard isPremiumUnlocked == false else { return true }
        return currentCount < freeCountdownLimit
    }

    func habitLimitMessage() -> String {
        "海外版の無料プランでは習慣は\(freeHabitLimit)件までです。プレミアムで無制限になります。"
    }

    func countdownLimitMessage() -> String {
        "海外版の無料プランではカウントダウンは\(freeCountdownLimit)件までです。プレミアムで無制限になります。"
    }

    func diaryPhotoLimitMessage() -> String {
        "海外版の無料プランでは日記写真は\(freeDiaryPhotoLimit)枚までです。プレミアムで\(premiumDiaryPhotoLimit)枚まで追加できます。"
    }

    func diaryLocationMessage() -> String {
        "日記の場所保存はプレミアム機能です。"
    }

    func reviewMapMessage() -> String {
        "振り返りカレンダーの地図表示はプレミアム機能です。"
    }

    func lettersMessage() -> String {
        "手紙機能はプレミアム機能です。"
    }

    func habitGrassMessage() -> String {
        "習慣の草表示はプレミアム機能です。"
    }

    func loadProductsIfNeeded(force: Bool) async {
        if isBillingDisabled {
            availableProducts = []
            hasLoadedProducts = true
            return
        }

        if isJapanStorefront {
            availableProducts = []
            // Keep products disabled in JP while allowing non-JP to fetch later.
            hasLoadedProducts = false
            return
        }

        if isLoadingProducts {
            return
        }
        if hasLoadedProducts && force == false {
            return
        }

        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let products = try await Product.products(for: Array(allPremiumProductIDs))
            availableProducts = sortProducts(products)
            hasLoadedProducts = true
        } catch {
            errorMessage = "プラン情報の取得に失敗しました。時間をおいて再試行してください。"
        }
    }

    func purchase(_ product: Product) async -> Bool {
        if isBillingDisabled {
            return true
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verify(verification)
                await transaction.finish()
                await refreshEntitlements()
                return isPremiumUnlocked
            case .pending:
                errorMessage = "購入は保留中です。承認後に有効化されます。"
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = "購入に失敗しました。通信状態を確認して再試行してください。"
            return false
        }
    }

    func restorePurchases() async -> Bool {
        if isBillingDisabled {
            return true
        }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if isPremiumUnlocked == false {
                errorMessage = "復元できる購入が見つかりませんでした。"
            }
            return isPremiumUnlocked
        } catch {
            errorMessage = "購入の復元に失敗しました。しばらくして再試行してください。"
            return false
        }
    }

    private func refreshStorefrontCountry() {
#if DEBUG
        if let debugCode = debugStorefrontCountryCode, debugCode.isEmpty == false {
            storefrontCountryCode = debugCode
            return
        }
#endif

        if let code = SKPaymentQueue.default().storefront?.countryCode,
           code.isEmpty == false {
            storefrontCountryCode = code.uppercased()
            return
        }

        storefrontCountryCode = (Locale.current.region?.identifier ?? "JP").uppercased()
    }

    private func refreshEntitlements() async {
        if isBillingDisabled {
            hasPremiumEntitlement = true
            return
        }

        var premium = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if allPremiumProductIDs.contains(transaction.productID) {
                premium = true
                break
            }
        }
#if DEBUG
        if debugForcePremiumEntitlement {
            premium = true
        }
#endif
        hasPremiumEntitlement = premium
    }

    private func sortProducts(_ products: [Product]) -> [Product] {
        products.sorted { lhs, rhs in
            if lhs.type == .autoRenewable && rhs.type != .autoRenewable {
                return true
            }
            if lhs.type != .autoRenewable && rhs.type == .autoRenewable {
                return false
            }
            return decimalNumber(from: lhs.price).compare(decimalNumber(from: rhs.price)) == .orderedAscending
        }
    }

    private func decimalNumber(from decimal: Decimal) -> NSDecimalNumber {
        NSDecimalNumber(decimal: decimal)
    }

    private func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw MonetizationError.unverifiedTransaction
        }
    }

    private func startTransactionListener() {
        if isBillingDisabled {
            transactionUpdatesTask?.cancel()
            transactionUpdatesTask = nil
            return
        }

        transactionUpdatesTask = _Concurrency.Task {
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await refreshEntitlements()
            }
        }
    }
}

private enum MonetizationError: Error {
    case unverifiedTransaction
}

#if DEBUG
extension MonetizationService {
    var debugStorefrontCountryCode: String? {
        get {
            let value = UserDefaults.standard.string(forKey: debugStorefrontCountryCodeKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            guard let value, value.isEmpty == false else { return nil }
            return value
        }
        set {
            let normalized = newValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            if let normalized, normalized.isEmpty == false {
                UserDefaults.standard.set(normalized, forKey: debugStorefrontCountryCodeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: debugStorefrontCountryCodeKey)
            }
        }
    }

    var debugForcePremiumEntitlement: Bool {
        get { UserDefaults.standard.bool(forKey: debugForcePremiumEntitlementKey) }
        set { UserDefaults.standard.set(newValue, forKey: debugForcePremiumEntitlementKey) }
    }

    func applyDebugStorefrontCountryCode(_ code: String?) {
        debugStorefrontCountryCode = code
        _Concurrency.Task {
            await refreshStatus()
        }
    }

    func applyDebugForcePremiumEntitlement(_ enabled: Bool) {
        debugForcePremiumEntitlement = enabled
        _Concurrency.Task {
            await refreshStatus()
        }
    }
}
#endif
