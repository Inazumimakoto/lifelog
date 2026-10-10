import Foundation
import Combine
import SwiftUI
import UIKit

/// Bought items leave the saved list immediately; only animation and undo snapshots remain.
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
        let item: ShoppingItem
        let expiresAt: Date

        var title: String { item.title }
    }

    private struct PurchaseAnimation {
        let token: UUID
        let item: ShoppingItem
    }

    @Published private(set) var items: [ShoppingItem] = []
    @Published private(set) var places: [ShoppingPlace] = []
    @Published private(set) var loadError: String?
    @Published private(set) var filter: PlaceFilter = .all
    @Published private(set) var draftPlaceID: UUID?
    @Published private(set) var purchaseUndo: PurchaseUndo?
    @Published var errorMessage: String?
    @Published private var purchaseAnimations: [UUID: PurchaseAnimation] = [:]

    let shoppingStore: ShoppingStore
    private let now: () -> Date
    private var cancellables = Set<AnyCancellable>()
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

    var pendingItems: [ShoppingItem] {
        let savedIDs = Set(items.map(\.id))
        let checkingItems = purchaseAnimations.values
            .map(\.item)
            .filter { !savedIDs.contains($0.id) }
        return (items + checkingItems).filter(matchesFilter).sorted(by: addedOrder)
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

    func isChecking(_ id: UUID) -> Bool {
        purchaseAnimations[id] != nil
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

    func rememberAdditionPlace(_ id: UUID?) {
        // The addition sheet keeps its own purchase place without changing list filters.
        draftPlaceID = id
    }

    @discardableResult
    func togglePurchase(_ item: ShoppingItem) -> Bool {
        if let animation = purchaseAnimations[item.id] {
            // A rapid second tap cancels the check while its row is still visible.
            return restoreCheckedItem(animation.item)
        }
        // Ignore a stale row after its animation has ended or it was deleted elsewhere.
        guard let current = items.first(where: { $0.id == item.id }) else { return false }
        let animation = PurchaseAnimation(token: UUID(), item: current)
        purchaseAnimations[current.id] = animation
        do {
            try applyPurchaseChange { try shoppingStore.deleteItem(current.id) }
            schedulePurchaseAnimation(for: current.id, token: animation.token)
            let undo = PurchaseUndo(id: UUID(), item: current, expiresAt: now().addingTimeInterval(6))
            purchaseUndo = undo
            scheduleUndoExpiration(token: undo.id)
            return true
        } catch {
            purchaseAnimations.removeValue(forKey: current.id)
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func undoPurchase(_ token: UUID) -> Bool {
        guard let undo = purchaseUndo, undo.id == token else { return false }
        guard undo.expiresAt > now(), canRestore(undo.item) else {
            expirePurchaseUndo(token: token)
            return false
        }
        return restoreCheckedItem(undo.item)
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
        guard items.contains(where: { $0.id == item.id }) else { return }
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

    private func matchesFilter(_ item: ShoppingItem) -> Bool {
        switch filter {
        case .all: return true
        case .unassigned: return item.placeID == nil
        case .place(let id): return item.placeID == id
        }
    }

    private func addedOrder(_ lhs: ShoppingItem, _ rhs: ShoppingItem) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func canRestore(_ item: ShoppingItem) -> Bool {
        !items.contains { $0.id == item.id }
    }

    private func restoreCheckedItem(_ item: ShoppingItem) -> Bool {
        guard canRestore(item) else { return false }
        do {
            try applyPurchaseChange { try shoppingStore.restoreItem(item) }
            completePurchaseAnimation(for: item.id)
            if let undo = purchaseUndo, undo.item.id == item.id { expirePurchaseUndo(token: undo.id) }
            return true
        } catch {
            // A failed save leaves the latest snapshot and deadline available for retry.
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func applyPurchaseChange(_ operation: () throws -> Void) throws {
        isApplyingPurchaseChange = true
        defer { isApplyingPurchaseChange = false }
        try operation()
    }

    private func completePurchaseAnimation(for id: UUID, token: UUID) {
        guard purchaseAnimations[id]?.token == token else { return }
        animationTasks.removeValue(forKey: id)?.cancel()
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 0.2)) {
            _ = purchaseAnimations.removeValue(forKey: id)
        }
    }

    private func finishPendingPurchaseAnimations() {
        for task in animationTasks.values { task.cancel() }
        animationTasks.removeAll()
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 0.2)) {
            purchaseAnimations.removeAll()
        }
    }

    private func schedulePurchaseAnimation(for id: UUID, token: UUID) {
        animationTasks[id]?.cancel()
        animationTasks[id] = _Concurrency.Task { [weak self] in
            do { try await _Concurrency.Task.sleep(nanoseconds: 350_000_000) }
            catch { return }
            self?.completePurchaseAnimation(for: id, token: token)
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
        for id in purchaseAnimations.keys where items.contains(where: { $0.id == id }) {
            completePurchaseAnimation(for: id)
        }
        if let undo = purchaseUndo, !canRestore(undo.item) { expirePurchaseUndo(token: undo.id) }
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
                if case .place(let id) = self.filter, !places.contains(where: { $0.id == id }) {
                    self.filter = .all
                }
            }
            .store(in: &cancellables)

        shoppingStore.$loadError
            .sink { [weak self] in self?.loadError = $0 }
            .store(in: &cancellables)
    }
}
