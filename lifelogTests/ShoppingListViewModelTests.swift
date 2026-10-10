import XCTest
import SwiftData
@testable import lifelify

@MainActor
final class ShoppingListViewModelTests: XCTestCase {
    func testChecking_pinsRowBrieflyDeletesSavedItemAndUndoRestoresOriginalContent() throws {
        let container = try makeContainer()
        let store = ShoppingStore(container: container)
        let supermarket = try store.addPlace(name: "スーパー")
        let pharmacy = try store.addPlace(name: "ドラッグストア")
        let milk = try store.addItem(title: "牛乳", quantity: "2本", note: "低脂肪", placeID: supermarket.id)
        _ = try store.addItem(title: "卵", placeID: supermarket.id)
        _ = try store.addItem(title: "薬", placeID: pharmacy.id)
        let model = ShoppingListViewModel(shoppingStore: store, now: { Date(timeIntervalSince1970: 1_000) })
        let originalGroups = model.pendingGroups.map { $0.items.map(\.id) }
        let originalGroupIDs = model.pendingGroups.map(\.id)

        XCTAssertTrue(model.togglePurchase(milk))
        XCTAssertEqual(model.pendingGroups.map(\.id), originalGroupIDs)
        XCTAssertEqual(model.pendingGroups.map { $0.items.map(\.id) }, originalGroups)
        XCTAssertTrue(model.isChecking(milk.id))
        XCTAssertFalse(model.items.contains { $0.id == milk.id })
        XCTAssertFalse(ShoppingStore(container: container).items.contains { $0.id == milk.id })
        let undo = try XCTUnwrap(model.purchaseUndo)
        XCTAssertEqual(undo.item, milk)

        model.selectFilter(.all)
        XCTAssertEqual(model.pendingGroups.map { $0.items.map(\.id) }, originalGroups)
        XCTAssertTrue(model.isChecking(milk.id))
        model.completePurchaseAnimation(for: milk.id)
        XCTAssertFalse(model.pendingItems.contains { $0.id == milk.id })
        XCTAssertFalse(model.isChecking(milk.id))
        XCTAssertTrue(model.undoPurchase(undo.id))
        XCTAssertEqual(model.items.first { $0.id == milk.id }, milk)
        XCTAssertEqual(ShoppingStore(container: container).items.first { $0.id == milk.id }, milk)
        XCTAssertNil(model.purchaseUndo)
        XCTAssertEqual(model.pendingGroups.map { $0.items.map(\.id) }, originalGroups)

        XCTAssertTrue(model.togglePurchase(milk))
        // A rapid second tap carries the old row value, but restores the same saved item.
        XCTAssertTrue(model.togglePurchase(milk))
        XCTAssertEqual(model.items.filter { $0.id == milk.id }, [milk])
        XCTAssertFalse(model.isChecking(milk.id))
        XCTAssertNil(model.purchaseUndo)
    }

    func testConsecutiveChecks_replaceUndoAndIgnoreOldTokensWithoutRetainingHistory() throws {
        let container = try makeContainer()
        let store = ShoppingStore(container: container)
        let milk = try store.addItem(title: "牛乳")
        let eggs = try store.addItem(title: "卵")
        var clock = Date(timeIntervalSince1970: 1_000)
        let model = ShoppingListViewModel(shoppingStore: store, now: { clock })

        XCTAssertTrue(model.togglePurchase(milk))
        let firstUndo = try XCTUnwrap(model.purchaseUndo)
        XCTAssertEqual(firstUndo.expiresAt, clock.addingTimeInterval(6))
        clock = clock.addingTimeInterval(1)
        XCTAssertTrue(model.togglePurchase(eggs))
        let latestUndo = try XCTUnwrap(model.purchaseUndo)
        XCTAssertEqual(latestUndo.item.id, eggs.id)
        XCTAssertEqual(latestUndo.expiresAt, clock.addingTimeInterval(6))
        model.expirePurchaseUndo(token: firstUndo.id)
        XCTAssertEqual(model.purchaseUndo?.id, latestUndo.id)
        XCTAssertFalse(model.undoPurchase(firstUndo.id))
        XCTAssertEqual(model.purchaseUndo?.id, latestUndo.id)

        model.completePurchaseAnimation(for: milk.id)
        model.completePurchaseAnimation(for: eggs.id)
        XCTAssertTrue(model.pendingItems.isEmpty)
        XCTAssertFalse(model.togglePurchase(milk))
        clock = latestUndo.expiresAt
        XCTAssertFalse(model.undoPurchase(latestUndo.id))
        XCTAssertNil(model.purchaseUndo)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertTrue(ShoppingStore(container: container).items.isEmpty)
    }

    func testFailedPurchaseAndUndo_keepSavedItemsAndLatestUndoAvailableForRetry() throws {
        let container = try makeContainer()
        var failSave = false
        let store = ShoppingStore(container: container) { context in
            if failSave { throw SaveFailure.injected }
            try context.save()
        }
        let milk = try store.addItem(title: "牛乳")
        let eggs = try store.addItem(title: "卵")
        // A stale displayed row must not replace a more recent saved edit in the undo snapshot.
        var editedMilk = milk
        editedMilk.title = "低脂肪牛乳"
        editedMilk.note = "編集したメモ"
        try store.updateItem(editedMilk)
        let model = ShoppingListViewModel(shoppingStore: store)
        XCTAssertTrue(model.togglePurchase(milk))
        let undo = try XCTUnwrap(model.purchaseUndo)
        XCTAssertEqual(undo.item, editedMilk)

        failSave = true
        XCTAssertFalse(model.togglePurchase(eggs))
        XCTAssertEqual(model.purchaseUndo?.id, undo.id)
        XCTAssertEqual(model.purchaseUndo?.expiresAt, undo.expiresAt)
        XCTAssertFalse(model.isChecking(eggs.id))
        XCTAssertEqual(model.items, [eggs])
        XCTAssertEqual(ShoppingStore(container: container).items, [eggs])
        model.completePurchaseAnimation(for: milk.id)
        XCTAssertFalse(model.undoPurchase(undo.id))
        XCTAssertEqual(model.items, [eggs])
        XCTAssertEqual(model.purchaseUndo?.id, undo.id)
        XCTAssertNotNil(model.errorMessage)

        failSave = false
        XCTAssertTrue(model.undoPurchase(undo.id))
        XCTAssertEqual(ShoppingStore(container: container).items.first { $0.id == milk.id }, editedMilk)
        XCTAssertNil(model.purchaseUndo)
    }

    func testExternalRestoration_invalidatesUndoAndNeverOverwritesNewerContents() throws {
        let store = ShoppingStore(container: try makeContainer())
        let milk = try store.addItem(title: "牛乳")
        let model = ShoppingListViewModel(shoppingStore: store)
        XCTAssertTrue(model.togglePurchase(milk))
        let token = try XCTUnwrap(model.purchaseUndo).id
        var externallyRestored = milk
        externallyRestored.title = "豆乳"
        externallyRestored.note = "外部で復元した内容"
        try store.restoreItem(externallyRestored)
        XCTAssertFalse(model.isChecking(milk.id))
        XCTAssertNil(model.purchaseUndo)
        XCTAssertFalse(model.undoPurchase(token))
        XCTAssertEqual(model.pendingItems, [externallyRestored])
        try store.restoreItem(milk)
        XCTAssertEqual(store.items, [externallyRestored])
    }

    func testRepeatedNewItemsWithSameTitle_doNotAccumulatePurchasedRows() throws {
        let container = try makeContainer()
        let store = ShoppingStore(container: container)
        let model = ShoppingListViewModel(shoppingStore: store)
        let firstEggs = try store.addItem(title: "卵")
        XCTAssertTrue(model.togglePurchase(firstEggs))
        model.completePurchaseAnimation(for: firstEggs.id)
        let firstUndo = try XCTUnwrap(model.purchaseUndo)
        let nextEggs = try store.addItem(title: "卵")
        XCTAssertEqual(model.pendingItems, [nextEggs])
        // Independently entering the same title does not silently replace the current undo.
        XCTAssertEqual(model.purchaseUndo?.id, firstUndo.id)
        XCTAssertTrue(model.togglePurchase(nextEggs))
        model.completePurchaseAnimation(for: nextEggs.id)
        let latestUndo = try XCTUnwrap(model.purchaseUndo)
        XCTAssertTrue(ShoppingStore(container: container).items.isEmpty)
        XCTAssertTrue(model.undoPurchase(latestUndo.id))
        XCTAssertEqual(model.pendingItems, [nextEggs])
        XCTAssertEqual(ShoppingStore(container: container).items, [nextEggs])
    }

    func testLeavingListAndRelaunching_dropTransientStateWithoutRestoringBoughtItems() throws {
        let container = try makeContainer()
        let store = ShoppingStore(container: container)
        let milk = try store.addItem(title: "牛乳")
        let model = ShoppingListViewModel(shoppingStore: store)
        XCTAssertTrue(model.togglePurchase(milk))
        let token = try XCTUnwrap(model.purchaseUndo).id
        model.finishPurchaseInteractions()
        XCTAssertFalse(model.isChecking(milk.id))
        XCTAssertTrue(model.pendingItems.isEmpty)
        XCTAssertNil(model.purchaseUndo)
        XCTAssertFalse(model.undoPurchase(token))
        let relaunched = ShoppingListViewModel(shoppingStore: ShoppingStore(container: container))
        XCTAssertTrue(relaunched.pendingItems.isEmpty)
        XCTAssertNil(relaunched.purchaseUndo)
    }

    func testUndoAfterPlaceDeletion_restoresContentsWithoutADeletedPurchasePlace() throws {
        let store = ShoppingStore(container: try makeContainer())
        let place = try store.addPlace(name: "スーパー")
        let milk = try store.addItem(title: "牛乳", quantity: "2本", note: "低脂肪", placeID: place.id)
        let model = ShoppingListViewModel(shoppingStore: store)
        model.selectFilter(.place(place.id))
        XCTAssertTrue(model.togglePurchase(milk))
        let undo = try XCTUnwrap(model.purchaseUndo)
        model.completePurchaseAnimation(for: milk.id)
        try store.deletePlace(place.id)
        XCTAssertEqual(model.filter, .all)
        XCTAssertNil(model.draftPlaceID)
        XCTAssertTrue(model.undoPurchase(undo.id))
        var expected = milk
        expected.placeID = nil
        XCTAssertEqual(model.pendingItems, [expected])
        XCTAssertEqual(model.pendingGroups.first?.items, [expected])
    }

    func testPurchaseAnimationTimer_removesCheckedRowWhileKeepingUndo() async throws {
        let store = ShoppingStore(container: try makeContainer())
        let milk = try store.addItem(title: "牛乳")
        let eggs = try store.addItem(title: "卵")
        let model = ShoppingListViewModel(shoppingStore: store)
        XCTAssertTrue(model.togglePurchase(milk))
        XCTAssertEqual(model.pendingItems.map(\.id), [milk.id, eggs.id])
        try await _Concurrency.Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(model.pendingItems, [eggs])
        XCTAssertFalse(model.isChecking(milk.id))
        XCTAssertEqual(model.purchaseUndo?.item, milk)
        model.finishPurchaseInteractions()
    }

    func testUndoExpirationTimer_discardsSnapshotWithoutRestoringBoughtItem() async throws {
        let store = ShoppingStore(container: try makeContainer())
        let milk = try store.addItem(title: "牛乳")
        let model = ShoppingListViewModel(shoppingStore: store)
        XCTAssertTrue(model.togglePurchase(milk))
        let token = try XCTUnwrap(model.purchaseUndo).id
        try await _Concurrency.Task.sleep(nanoseconds: 6_200_000_000)
        XCTAssertNil(model.purchaseUndo)
        XCTAssertTrue(model.pendingItems.isEmpty)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(model.undoPurchase(token))
    }

    func testFiltersAndAdditionSheet_keepTheLastSelectedPurchasePlace() throws {
        let store = ShoppingStore(container: try makeContainer())
        let supermarket = try store.addPlace(name: "スーパー")
        let pharmacy = try store.addPlace(name: "ドラッグストア")
        let model = ShoppingListViewModel(shoppingStore: store)
        model.selectFilter(.place(supermarket.id))
        XCTAssertEqual(model.draftPlaceID, supermarket.id)
        model.selectFilter(.all)
        XCTAssertEqual(model.draftPlaceID, supermarket.id)
        model.rememberAdditionPlace(pharmacy.id)
        XCTAssertEqual(model.filter, .all)
        XCTAssertEqual(model.draftPlaceID, pharmacy.id)
        model.selectFilter(.unassigned)
        XCTAssertNil(model.draftPlaceID)
        model.selectFilter(.all)
        XCTAssertNil(model.draftPlaceID)
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
