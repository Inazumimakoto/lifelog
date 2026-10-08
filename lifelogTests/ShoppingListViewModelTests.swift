import XCTest
import SwiftData
@testable import lifelify

@MainActor
final class ShoppingListViewModelTests: XCTestCase {
    func testCheckingBrieflyPinsRows_thenMovesToHistoryAndUndoRestoresPurchaseCount() throws {
        let store = ShoppingStore(container: try makeContainer())
        let supermarket = try store.addPlace(name: "スーパー")
        let pharmacy = try store.addPlace(name: "ドラッグストア")
        let milk = try store.addItem(title: "牛乳", placeID: supermarket.id)
        _ = try store.addItem(title: "卵", placeID: supermarket.id)
        _ = try store.addItem(title: "薬", placeID: pharmacy.id)
        let model = ShoppingListViewModel(shoppingStore: store, now: { Date(timeIntervalSince1970: 1_000) })
        let originalGroups = model.pendingGroups.map { $0.items.map(\.id) }
        let originalGroupIDs = model.pendingGroups.map(\.id)

        XCTAssertTrue(model.togglePurchased(milk))
        XCTAssertEqual(model.pendingGroups.map(\.id), originalGroupIDs)
        XCTAssertEqual(model.pendingGroups.map { $0.items.map(\.id) }, originalGroups)
        XCTAssertTrue(model.purchasedItems.isEmpty)
        XCTAssertTrue(model.sessionPurchasedIDs.contains(milk.id))
        XCTAssertEqual(model.items.first { $0.id == milk.id }?.purchaseCount, 1)
        let undo = try XCTUnwrap(model.purchaseUndo)
        XCTAssertEqual(undo.itemID, milk.id)

        model.selectFilter(.all)
        XCTAssertEqual(model.pendingGroups.map { $0.items.map(\.id) }, originalGroups)
        XCTAssertTrue(model.sessionPurchasedIDs.contains(milk.id))

        model.completePurchaseAnimation(for: milk.id)
        XCTAssertFalse(model.pendingItems.contains { $0.id == milk.id })
        XCTAssertEqual(model.purchasedItems.map(\.id), [milk.id])
        XCTAssertTrue(model.sessionPurchasedIDs.isEmpty)
        XCTAssertTrue(model.undoPurchase(undo.id))
        XCTAssertFalse(try XCTUnwrap(model.items.first { $0.id == milk.id }).isPurchased)
        XCTAssertEqual(model.items.first { $0.id == milk.id }?.purchaseCount, 0)
        XCTAssertTrue(model.sessionPurchasedIDs.isEmpty)
        XCTAssertNil(model.purchaseUndo)
        XCTAssertEqual(model.pendingGroups.map { $0.items.map(\.id) }, originalGroups)

        XCTAssertTrue(model.togglePurchased(milk))
        // A rapid second tap can pass the row's older, unchecked value.
        XCTAssertTrue(model.togglePurchased(milk))
        XCTAssertFalse(try XCTUnwrap(model.items.first { $0.id == milk.id }).isPurchased)
        XCTAssertEqual(model.items.first { $0.id == milk.id }?.purchaseCount, 0)
        XCTAssertNil(model.purchaseUndo)

        XCTAssertTrue(model.togglePurchased(milk))
        model.completePurchaseAnimation(for: milk.id)
        // Returning from purchase history is a new shopping cycle, even during the undo window.
        let historyItem = try XCTUnwrap(model.purchasedItems.first)
        XCTAssertTrue(model.togglePurchased(historyItem))
        XCTAssertEqual(model.pendingItems.first { $0.id == milk.id }?.purchaseCount, 1)
        XCTAssertNil(model.purchaseUndo)
        XCTAssertTrue(model.togglePurchased(historyItem))
        XCTAssertEqual(model.items.first { $0.id == milk.id }?.purchaseCount, 2)
        let nextUndo = try XCTUnwrap(model.purchaseUndo)
        XCTAssertTrue(model.undoPurchase(nextUndo.id))
        XCTAssertEqual(model.items.first { $0.id == milk.id }?.purchaseCount, 1)
    }

    func testConsecutiveChecks_replaceUndoAndIgnoreOlderExpirationAndUndoTokens() throws {
        let store = ShoppingStore(container: try makeContainer())
        let supermarket = try store.addPlace(name: "スーパー")
        let milk = try store.addItem(title: "牛乳", placeID: supermarket.id)
        let eggs = try store.addItem(title: "卵", placeID: supermarket.id)
        var clock = Date(timeIntervalSince1970: 1_000)
        let model = ShoppingListViewModel(shoppingStore: store, now: { clock })
        model.selectFilter(.place(supermarket.id))
        let originalOrder = model.pendingItems.map(\.id)

        XCTAssertTrue(model.togglePurchased(milk))
        let firstUndo = try XCTUnwrap(model.purchaseUndo)
        XCTAssertEqual(firstUndo.expiresAt, clock.addingTimeInterval(6))
        model.selectFilter(.place(supermarket.id))
        XCTAssertEqual(model.pendingItems.map(\.id), originalOrder)
        XCTAssertTrue(model.purchasedItems.isEmpty)

        clock = clock.addingTimeInterval(1)
        XCTAssertTrue(model.togglePurchased(eggs))
        let latestUndo = try XCTUnwrap(model.purchaseUndo)
        XCTAssertEqual(latestUndo.itemID, eggs.id)
        XCTAssertEqual(latestUndo.expiresAt, clock.addingTimeInterval(6))
        model.expirePurchaseUndo(token: firstUndo.id)
        XCTAssertEqual(model.purchaseUndo?.id, latestUndo.id)
        XCTAssertFalse(model.undoPurchase(firstUndo.id))
        XCTAssertEqual(model.purchaseUndo?.id, latestUndo.id)

        model.completePurchaseAnimation(for: milk.id)
        model.completePurchaseAnimation(for: eggs.id)
        XCTAssertTrue(model.pendingItems.isEmpty)
        clock = latestUndo.expiresAt
        XCTAssertFalse(model.undoPurchase(latestUndo.id))
        XCTAssertNil(model.purchaseUndo)
        XCTAssertTrue(model.items.allSatisfy(\.isPurchased))
        XCTAssertTrue(model.items.allSatisfy { $0.purchaseCount == 1 })
    }

    func testFailedPurchaseAndUndo_preserveLatestUndoAndEditsUntilSaveSucceeds() throws {
        let container = try makeContainer()
        var failSave = false
        let store = ShoppingStore(container: container) { context in
            if failSave { throw SaveFailure.injected }
            try context.save()
        }
        let milk = try store.addItem(title: "牛乳")
        let eggs = try store.addItem(title: "卵")
        try store.restorePurchaseState(for: milk.id, purchasedAt: nil, purchaseCount: 2)
        let model = ShoppingListViewModel(shoppingStore: store)
        XCTAssertTrue(model.togglePurchased(milk))
        let undo = try XCTUnwrap(model.purchaseUndo)

        failSave = true
        XCTAssertFalse(model.togglePurchased(eggs))
        XCTAssertEqual(model.purchaseUndo?.id, undo.id)
        XCTAssertEqual(model.purchaseUndo?.expiresAt, undo.expiresAt)
        XCTAssertFalse(model.sessionPurchasedIDs.contains(eggs.id))
        XCTAssertEqual(model.items.first { $0.id == eggs.id }?.purchaseCount, 0)
        failSave = false
        model.completePurchaseAnimation(for: milk.id)

        var edited = try XCTUnwrap(store.items.first { $0.id == milk.id })
        edited.title = "低脂肪牛乳"
        edited.note = "編集したメモを保持"
        try store.updateItem(edited)
        XCTAssertEqual(model.purchaseUndo?.id, undo.id)
        let rowsBeforeFailure = model.purchasedItems
        failSave = true
        XCTAssertFalse(model.undoPurchase(undo.id))
        XCTAssertEqual(model.purchasedItems, rowsBeforeFailure)
        XCTAssertEqual(model.purchaseUndo?.id, undo.id)
        XCTAssertEqual(model.items.first { $0.id == milk.id }?.purchaseCount, 3)
        XCTAssertNotNil(model.errorMessage)

        failSave = false
        XCTAssertTrue(model.undoPurchase(undo.id))
        let restored = try XCTUnwrap(ShoppingStore(container: container).items.first { $0.id == milk.id })
        XCTAssertEqual(restored.purchaseCount, 2)
        XCTAssertFalse(restored.isPurchased)
        XCTAssertEqual(restored.title, "低脂肪牛乳")
        XCTAssertEqual(restored.note, "編集したメモを保持")
        XCTAssertNil(model.purchaseUndo)
    }

    func testExternalPurchaseChangesRebuyAndDeletion_invalidateOnlyTheAffectedUndo() throws {
        let store = ShoppingStore(container: try makeContainer())
        let milk = try store.addItem(title: "牛乳")
        let model = ShoppingListViewModel(shoppingStore: store)
        XCTAssertTrue(model.togglePurchased(milk))
        let firstToken = try XCTUnwrap(model.purchaseUndo).id
        try store.togglePurchased(milk.id)
        XCTAssertNil(model.purchaseUndo)
        XCTAssertTrue(model.sessionPurchasedIDs.isEmpty)
        XCTAssertFalse(model.undoPurchase(firstToken))

        XCTAssertTrue(model.togglePurchased(milk))
        let rebuyToken = try XCTUnwrap(model.purchaseUndo).id
        let nextMilk = try store.buyAgain(milk.id)
        XCTAssertNil(model.purchaseUndo)
        XCTAssertFalse(model.undoPurchase(rebuyToken))
        XCTAssertTrue(try XCTUnwrap(model.items.first { $0.id == milk.id }).isPurchased)
        XCTAssertFalse(nextMilk.isPurchased)

        XCTAssertTrue(model.togglePurchased(nextMilk))
        let deleteToken = try XCTUnwrap(model.purchaseUndo).id
        try store.deleteItem(nextMilk.id)
        XCTAssertNil(model.purchaseUndo)
        XCTAssertFalse(model.sessionPurchasedIDs.contains(nextMilk.id))
        XCTAssertFalse(model.undoPurchase(deleteToken))
        model.finishPurchaseInteractions()
        XCTAssertTrue(model.sessionPurchasedIDs.isEmpty)
        XCTAssertNil(model.purchaseUndo)
    }

    func testPurchasedOrdering_usesFamilyCountsAcrossAllPlacesThenDateAndStableID() throws {
        let store = ShoppingStore(container: try makeContainer())
        let supermarket = try store.addPlace(name: "スーパー")
        let pharmacy = try store.addPlace(name: "ドラッグストア")
        let milk = try store.addItem(title: "牛乳", placeID: supermarket.id)
        try store.restorePurchaseState(for: milk.id,
                                       purchasedAt: Date(timeIntervalSince1970: 1_000), purchaseCount: 2)
        var nextMilk = try store.buyAgain(milk.id)
        nextMilk.placeID = pharmacy.id
        try store.updateItem(nextMilk)
        try store.restorePurchaseState(for: nextMilk.id,
                                       purchasedAt: Date(timeIntervalSince1970: 2_000), purchaseCount: 1)
        let beans = try store.addItem(title: "豆", placeID: supermarket.id)
        let tea = try store.addItem(title: "お茶", placeID: supermarket.id)
        for item in [beans, tea] {
            try store.restorePurchaseState(for: item.id,
                                           purchasedAt: Date(timeIntervalSince1970: 3_000), purchaseCount: 2)
        }
        // A separately created item with the same title has its own frequency.
        let unrelatedMilk = try store.addItem(title: "牛乳", placeID: supermarket.id)
        try store.restorePurchaseState(for: unrelatedMilk.id,
                                       purchasedAt: Date(timeIntervalSince1970: 4_000), purchaseCount: 1)
        let tieIDs = [beans.id, tea.id].sorted { $0.uuidString < $1.uuidString }
        let model = ShoppingListViewModel(shoppingStore: store)
        XCTAssertEqual(model.purchasedItems.map(\.id), [nextMilk.id, milk.id] + tieIDs + [unrelatedMilk.id])
        model.selectFilter(.place(supermarket.id))
        XCTAssertEqual(model.purchasedItems.map(\.id), [milk.id] + tieIDs + [unrelatedMilk.id])
    }

    func testRepeatedAdditionsAndFailedSave_preservePurchasePlaceAndUnsavedDraft() throws {
        var failSave = false
        let store = ShoppingStore(container: try makeContainer()) { context in
            if failSave { throw SaveFailure.injected }
            try context.save()
        }
        let supermarket = try store.addPlace(name: "スーパー")
        let pharmacy = try store.addPlace(name: "ドラッグストア")
        let model = ShoppingListViewModel(shoppingStore: store)
        model.selectFilter(.place(supermarket.id))

        for title in ["牛乳", "卵"] {
            model.titleDraft = title
            XCTAssertTrue(model.addDraft())
            XCTAssertEqual(model.titleDraft, "")
            XCTAssertEqual(model.draftPlaceID, supermarket.id)
        }
        XCTAssertEqual(store.items.count, 2)
        XCTAssertTrue(store.items.allSatisfy { $0.placeID == supermarket.id })

        model.selectFilter(.all)
        XCTAssertEqual(model.draftPlaceID, supermarket.id)
        model.selectDraftPlace(pharmacy.id)
        model.titleDraft = "洗剤"
        failSave = true
        XCTAssertFalse(model.addDraft())
        XCTAssertEqual(model.titleDraft, "洗剤")
        XCTAssertEqual(model.draftPlaceID, pharmacy.id)
        XCTAssertEqual(store.items.count, 2)
        XCTAssertNotNil(model.errorMessage)

        failSave = false
        XCTAssertTrue(model.addDraft())
        XCTAssertEqual(model.titleDraft, "")
        XCTAssertEqual(model.draftPlaceID, pharmacy.id)
        XCTAssertEqual(store.items.first { $0.title == "洗剤" }?.placeID, pharmacy.id)

        model.selectFilter(.unassigned)
        model.titleDraft = "ごみ袋"
        XCTAssertTrue(model.addDraft())
        model.selectFilter(.all)
        XCTAssertNil(model.draftPlaceID)
        XCTAssertNil(try XCTUnwrap(store.items.first { $0.title == "ごみ袋" }).placeID)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([SDShoppingItem.self, SDShoppingPlace.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                               cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private enum SaveFailure: Error {
        case injected
    }
}
