import XCTest
import SwiftData
@testable import lifelify

@MainActor
final class ShoppingAddItemsViewModelTests: XCTestCase {
    func testRepeatedAdditions_showOnlyThisSessionInAddOrderAndSaveImmediately() throws {
        let container = try makeContainer()
        let store = ShoppingStore(container: container)
        let place = try store.addPlace(name: "イオン")
        _ = try store.addItem(title: "以前からある商品", placeID: place.id)
        let model = ShoppingAddItemsViewModel(shoppingStore: store, initialPlaceID: place.id)
        _ = try store.addItem(title: "別の画面からの商品", placeID: place.id)
        XCTAssertTrue(model.addedItems.isEmpty)

        let memo = "  いつもの銘柄\n10個入りを買う  "
        model.noteDraft = memo
        for title in ["卵", "豆腐", "キャベツ"] {
            model.titleDraft = title
            XCTAssertTrue(model.addDraft())
            XCTAssertEqual(model.titleDraft, "")
            XCTAssertEqual(model.noteDraft, "")
            XCTAssertEqual(model.selectedPlaceID, place.id)
        }

        XCTAssertEqual(model.addedItems.map(\.title), ["卵", "豆腐", "キャベツ"])
        XCTAssertEqual(model.addedItems.map(\.note), [memo, "", ""])
        XCTAssertEqual(model.addedItems.map(\.id), model.sessionItemIDs)
        XCTAssertEqual(model.addedCount, 3)
        let restored = ShoppingStore(container: container)
        XCTAssertEqual(restored.items.count, 5)
        XCTAssertTrue(model.addedItems.allSatisfy { item in
            restored.items.contains {
                $0.id == item.id && $0.placeID == place.id && $0.note == item.note
            }
        })

        try store.deleteItem(try XCTUnwrap(model.addedItems.first).id)
        XCTAssertEqual(model.addedItems.map(\.title), ["豆腐", "キャベツ"])
        XCTAssertEqual(model.addedCount, 2)
        XCTAssertTrue(ShoppingAddItemsViewModel(shoppingStore: store).addedItems.isEmpty)
    }

    func testUndoAndFailedSave_keepSessionItemsAndUnsavedDraftUntilSaveSucceeds() throws {
        let container = try makeContainer()
        var failSave = false
        let store = ShoppingStore(container: container) { context in
            if failSave { throw SaveFailure.injected }
            try context.save()
        }
        let place = try store.addPlace(name: "スーパー")
        let existing = try store.addItem(title: "以前からある商品")
        let model = ShoppingAddItemsViewModel(shoppingStore: store, initialPlaceID: place.id)
        model.titleDraft = "牛乳"
        XCTAssertTrue(model.addDraft())
        let added = try XCTUnwrap(model.addedItems.first)

        XCTAssertFalse(model.undoAddition(existing.id))
        failSave = true
        XCTAssertFalse(model.undoAddition(added.id))
        XCTAssertEqual(model.addedItems.map(\.id), [added.id])
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(ShoppingStore(container: container).items.count, 2)

        model.titleDraft = "洗剤"
        let memo = "  詰め替え用\n無香料  "
        model.noteDraft = memo
        XCTAssertFalse(model.addDraft())
        XCTAssertEqual(model.titleDraft, "洗剤")
        XCTAssertEqual(model.noteDraft, memo)
        XCTAssertEqual(model.selectedPlaceID, place.id)
        XCTAssertEqual(model.addedCount, 1)

        failSave = false
        XCTAssertTrue(model.undoAddition(added.id))
        XCTAssertTrue(model.addedItems.isEmpty)
        XCTAssertEqual(ShoppingStore(container: container).items.map(\.id), [existing.id])
        XCTAssertEqual(model.titleDraft, "洗剤")
        XCTAssertEqual(model.noteDraft, memo)
        XCTAssertTrue(model.addDraft())
        XCTAssertEqual(model.addedItems.map(\.title), ["洗剤"])
        let retried = try XCTUnwrap(model.addedItems.first)
        XCTAssertEqual(retried.note, memo)
        XCTAssertEqual(ShoppingStore(container: container).items.first { $0.id == retried.id }?.note,
                       memo)
        XCTAssertEqual(model.titleDraft, "")
        XCTAssertEqual(model.noteDraft, "")
        XCTAssertNil(model.errorMessage)
    }

    func testPurchasePlaceChanges_leaveListFilterIndependentAndHandleHiddenUnassigned() throws {
        let store = ShoppingStore(container: try makeContainer())
        let supermarket = try store.addPlace(name: "スーパー")
        let pharmacy = try store.addPlace(name: "ドラッグストア")
        let listModel = ShoppingListViewModel(shoppingStore: store)
        listModel.selectFilter(.place(supermarket.id))
        let model = ShoppingAddItemsViewModel(shoppingStore: store,
                                             initialPlaceID: listModel.draftPlaceID)

        model.selectPlace(pharmacy.id)
        XCTAssertEqual(listModel.filter, .place(supermarket.id))
        XCTAssertEqual(listModel.draftPlaceID, supermarket.id)
        model.selectPlace(nil)
        XCTAssertNil(model.selectedPlaceID)
        model.normalizeSelectedPlace(showsUnassigned: false)
        XCTAssertEqual(model.selectedPlaceID, supermarket.id)

        try store.deletePlace(supermarket.id)
        XCTAssertEqual(model.selectedPlaceID, pharmacy.id)
        try store.deletePlace(pharmacy.id)
        XCTAssertNil(model.selectedPlaceID)
        model.titleDraft = "購入先なしの商品"
        XCTAssertTrue(model.addDraft())
        XCTAssertNil(model.addedItems.first?.placeID)

        let newPlace = try store.addPlace(name: "コンビニ")
        XCTAssertEqual(model.selectedPlaceID, newPlace.id)
        model.normalizeSelectedPlace(showsUnassigned: true)
        model.selectPlace(nil)
        XCTAssertNil(model.selectedPlaceID)
        model.selectPlace(UUID())
        XCTAssertNil(model.selectedPlaceID)
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
