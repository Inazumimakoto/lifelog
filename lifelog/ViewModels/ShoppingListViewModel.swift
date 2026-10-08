import Foundation
import Combine
import SwiftUI
import UIKit

/// Briefly keeps checked rows in place, then offers undo for the latest purchase.
/// See docs/requirements.md: Shopping list and docs/ui-guidelines.md: Shopping.
@MainActor
final class ShoppingListViewModel: ObservableObject {
    enum PlaceFilter: Hashable {
        case all
        case unassigned
        case place(UUID)
    }

    struct PendingGroup: Identifiable {
        let id: String
        let title: String
        let items: [ShoppingItem]
    }

    struct PurchaseUndo: Identifiable {
        let id: UUID
        let itemID: UUID
        let title: String
        let previousPurchasedAt: Date?
        let previousPurchaseCount: Int
        let expectedPurchasedAt: Date
        let expectedPurchaseCount: Int
        let familyID: UUID
        let familyMemberIDs: Set<UUID>
        let expiresAt: Date
    }

    private struct PurchaseAnimation {
        let token: UUID
        let purchasedAt: Date
        let purchaseCount: Int
    }

    @Published private(set) var items: [ShoppingItem] = []
    @Published private(set) var places: [ShoppingPlace] = []
    @Published private(set) var loadError: String?
    @Published private(set) var filter: PlaceFilter = .all
    @Published private(set) var draftPlaceID: UUID?
    @Published private(set) var sessionPurchasedIDs: Set<UUID> = []
    @Published private(set) var purchaseUndo: PurchaseUndo?
    @Published var titleDraft = ""
    @Published var errorMessage: String?

    let shoppingStore: ShoppingStore
    private let now: () -> Date
    private var cancellables = Set<AnyCancellable>()
    private var purchaseAnimations: [UUID: PurchaseAnimation] = [:]
    private var animationTasks: [UUID: _Concurrency.Task<Void, Never>] = [:]
    private var undoExpirationTask: _Concurrency.Task<Void, Never>?
    private var isApplyingPurchaseChange = false

    init(shoppingStore: ShoppingStore, now: @escaping () -> Date = Date.init) {
        self.shoppingStore = shoppingStore
        self.now = now
        items = shoppingStore.items
        places = shoppingStore.places
        loadError = shoppingStore.loadError
        bind()
    }

    // No actor-isolated cleanup is needed; avoid Swift's implicit-deinit runtime bug.
    // https://github.com/swiftlang/swift/issues/87316
    nonisolated deinit {}

    var canAdd: Bool {
        loadError == nil && !titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var pendingItems: [ShoppingItem] {
        filteredItems
            .filter { !$0.isPurchased || sessionPurchasedIDs.contains($0.id) }
            .sorted(by: addedOrder)
    }

    var purchasedItems: [ShoppingItem] {
        let purchaseCounts = items.reduce(into: [UUID: Int]()) { counts, item in
            counts[item.effectiveFamilyID, default: 0] += item.purchaseCount
        }
        return filteredItems
            .filter { $0.isPurchased && !sessionPurchasedIDs.contains($0.id) }
            .sorted { lhs, rhs in
                let lhsCount = purchaseCounts[lhs.effectiveFamilyID, default: 0]
                let rhsCount = purchaseCounts[rhs.effectiveFamilyID, default: 0]
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                let lhsDate = lhs.purchasedAt ?? lhs.createdAt
                let rhsDate = rhs.purchasedAt ?? rhs.createdAt
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    var pendingGroups: [PendingGroup] {
        let pending = pendingItems
        if filter != .all {
            return pending.isEmpty ? [] : [PendingGroup(id: "filtered",
                                                       title: String(localized: "買うもの"),
                                                       items: pending)]
        }
        var groups = places
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex { return lhs.orderIndex < rhs.orderIndex }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .compactMap { place -> PendingGroup? in
                let items = pending.filter { $0.placeID == place.id }
                guard !items.isEmpty else { return nil }
                return PendingGroup(id: place.id.uuidString, title: place.name, items: items)
            }
        let unassigned = pending.filter { $0.placeID == nil }
        if !unassigned.isEmpty {
            groups.append(PendingGroup(id: "unassigned", title: String(localized: "未指定"), items: unassigned))
        }
        return groups
    }

    func selectFilter(_ filter: PlaceFilter) {
        if self.filter != filter { finishPendingPurchaseAnimations() }
        self.filter = filter
        switch filter {
        case .all:
            // Preserve the last purchase place when adding several items across all places.
            break
        case .unassigned:
            draftPlaceID = nil
        case .place(let id):
            draftPlaceID = id
        }
    }

    func selectDraftPlace(_ id: UUID?) {
        if filter != .all {
            selectFilter(id.map(PlaceFilter.place) ?? .unassigned)
        }
        draftPlaceID = id
    }

    func rememberAdditionPlace(_ id: UUID?) {
        // The addition sheet keeps its own purchase place without changing list filters.
        draftPlaceID = id
    }

    @discardableResult
    func addDraft() -> Bool {
        guard canAdd else { return false }
        do {
            _ = try shoppingStore.addItem(title: titleDraft,
                                         quantity: "",
                                         note: "",
                                         placeID: draftPlaceID)
            titleDraft = ""
            return true
        } catch {
            // Clear a draft only after its offline save succeeds.
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func togglePurchased(_ item: ShoppingItem) -> Bool {
        // Rows may carry an older value after a quick repeated tap or an external edit.
        guard let current = items.first(where: { $0.id == item.id }) else { return false }
        if current.isPurchased { return unpurchase(current) }

        // Pin before publishing the saved snapshot, so the check animation can finish.
        sessionPurchasedIDs.insert(current.id)
        do {
            try applyPurchaseChange { try shoppingStore.togglePurchased(current.id) }
            guard let purchased = items.first(where: { $0.id == current.id }),
                  let purchasedAt = purchased.purchasedAt else {
                sessionPurchasedIDs.remove(current.id)
                return false
            }
            let animation = PurchaseAnimation(token: UUID(), purchasedAt: purchasedAt,
                                              purchaseCount: purchased.purchaseCount)
            purchaseAnimations[current.id] = animation
            schedulePurchaseAnimation(for: current.id, token: animation.token)
            let undo = PurchaseUndo(id: UUID(), itemID: current.id, title: purchased.title,
                                    previousPurchasedAt: current.purchasedAt,
                                    previousPurchaseCount: current.purchaseCount,
                                    expectedPurchasedAt: purchasedAt,
                                    expectedPurchaseCount: purchased.purchaseCount,
                                    familyID: purchased.effectiveFamilyID,
                                    familyMemberIDs: familyMemberIDs(for: purchased.effectiveFamilyID),
                                    expiresAt: now().addingTimeInterval(6))
            purchaseUndo = undo
            scheduleUndoExpiration(token: undo.id)
            return true
        } catch {
            sessionPurchasedIDs.remove(current.id)
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func undoPurchase(_ token: UUID) -> Bool {
        guard let undo = purchaseUndo, undo.id == token else { return false }
        guard undo.expiresAt > now(), matchesUndo(undo) else {
            expirePurchaseUndo(token: token)
            return false
        }
        do {
            try applyPurchaseChange {
                try shoppingStore.restorePurchaseState(for: undo.itemID,
                                                       purchasedAt: undo.previousPurchasedAt,
                                                       purchaseCount: undo.previousPurchaseCount)
            }
            completePurchaseAnimation(for: undo.itemID)
            expirePurchaseUndo(token: token)
            return true
        } catch {
            // A failed save leaves the original undo and its deadline available for retry.
            errorMessage = error.localizedDescription
            return false
        }
    }

    func expirePurchaseUndo(token: UUID) {
        guard purchaseUndo?.id == token else { return }
        undoExpirationTask?.cancel()
        undoExpirationTask = nil
        purchaseUndo = nil
    }

    func completePurchaseAnimation(for id: UUID) {
        guard let animation = purchaseAnimations[id] else { return }
        completePurchaseAnimation(for: id, token: animation.token)
    }

    func finishPurchaseInteractions() {
        finishPendingPurchaseAnimations()
        if let token = purchaseUndo?.id { expirePurchaseUndo(token: token) }
    }

    func delete(_ item: ShoppingItem) {
        do {
            try shoppingStore.deleteItem(item.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() {
        do {
            try shoppingStore.reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var filteredItems: [ShoppingItem] {
        switch filter {
        case .all:
            return items
        case .unassigned:
            return items.filter { $0.placeID == nil }
        case .place(let id):
            return items.filter { $0.placeID == id }
        }
    }

    private func addedOrder(_ lhs: ShoppingItem, _ rhs: ShoppingItem) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func unpurchase(_ item: ShoppingItem) -> Bool {
        let undo = purchaseUndo
        do {
            try applyPurchaseChange {
                if let undo, sessionPurchasedIDs.contains(item.id),
                   undo.itemID == item.id, undo.expiresAt > now(), matchesUndo(undo) {
                    // A second tap during the check animation cancels a mistaken check.
                    // Tapping a row in purchase history schedules it again and retains its count.
                    try shoppingStore.restorePurchaseState(for: item.id,
                                                           purchasedAt: undo.previousPurchasedAt,
                                                           purchaseCount: undo.previousPurchaseCount)
                } else {
                    try shoppingStore.togglePurchased(item.id)
                }
            }
            completePurchaseAnimation(for: item.id)
            if let undo, undo.itemID == item.id { expirePurchaseUndo(token: undo.id) }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func applyPurchaseChange(_ operation: () throws -> Void) throws {
        isApplyingPurchaseChange = true
        defer { isApplyingPurchaseChange = false }
        try operation()
    }

    private func familyMemberIDs(for familyID: UUID) -> Set<UUID> {
        Set(items.lazy.filter { $0.effectiveFamilyID == familyID }.map(\.id))
    }

    private func matchesUndo(_ undo: PurchaseUndo) -> Bool {
        guard let item = items.first(where: { $0.id == undo.itemID }) else { return false }
        return item.purchasedAt == undo.expectedPurchasedAt
            && item.purchaseCount == undo.expectedPurchaseCount
            && item.effectiveFamilyID == undo.familyID
            && familyMemberIDs(for: undo.familyID) == undo.familyMemberIDs
    }

    private func schedulePurchaseAnimation(for id: UUID, token: UUID) {
        animationTasks[id]?.cancel()
        animationTasks[id] = _Concurrency.Task { [weak self] in
            do { try await _Concurrency.Task.sleep(nanoseconds: 350_000_000) }
            catch { return }
            self?.completePurchaseAnimation(for: id, token: token)
        }
    }

    private func completePurchaseAnimation(for id: UUID, token: UUID) {
        guard purchaseAnimations[id]?.token == token else { return }
        animationTasks.removeValue(forKey: id)?.cancel()
        purchaseAnimations.removeValue(forKey: id)
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 0.2)) {
            _ = sessionPurchasedIDs.remove(id)
        }
    }

    private func finishPendingPurchaseAnimations() {
        for task in animationTasks.values { task.cancel() }
        animationTasks.removeAll()
        purchaseAnimations.removeAll()
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 0.2)) {
            sessionPurchasedIDs.removeAll()
        }
    }

    private func scheduleUndoExpiration(token: UUID) {
        undoExpirationTask?.cancel()
        undoExpirationTask = _Concurrency.Task { [weak self] in
            do { try await _Concurrency.Task.sleep(nanoseconds: 6_000_000_000) }
            catch { return }
            self?.expirePurchaseUndo(token: token)
        }
    }

    private func reconcilePurchaseInteractions() {
        for (id, animation) in purchaseAnimations {
            guard let item = items.first(where: { $0.id == id }),
                  item.purchasedAt == animation.purchasedAt,
                  item.purchaseCount == animation.purchaseCount else {
                completePurchaseAnimation(for: id, token: animation.token)
                continue
            }
        }
        if let undo = purchaseUndo, !matchesUndo(undo) { expirePurchaseUndo(token: undo.id) }
    }

    private func bind() {
        shoppingStore.$items
            .sink { [weak self] items in
                guard let self else { return }
                self.items = items
                if !self.isApplyingPurchaseChange { self.reconcilePurchaseInteractions() }
            }
            .store(in: &cancellables)

        shoppingStore.$places
            .sink { [weak self] places in
                guard let self else { return }
                self.places = places
                if let id = self.draftPlaceID, !places.contains(where: { $0.id == id }) {
                    self.draftPlaceID = nil
                }
                if case .place(let id) = self.filter,
                   !places.contains(where: { $0.id == id }) {
                    self.filter = .unassigned
                }
            }
            .store(in: &cancellables)

        shoppingStore.$loadError
            .sink { [weak self] in self?.loadError = $0 }
            .store(in: &cancellables)
    }
}
