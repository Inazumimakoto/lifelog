import XCTest
import SwiftData
@testable import lifelify

@MainActor
final class ShoppingStoreTests: XCTestCase {
    func testPurchaseCancellationAndBuyAgain_preserveOriginalHistory() throws {
        let container = try makeContainer()
        let store = ShoppingStore(container: container)
        let place = try store.addPlace(name: "スーパー")
        let original = try store.addItem(title: "牛乳", quantity: "2本", note: "低脂肪", placeID: place.id)

        try store.togglePurchased(original.id)
        let purchased = try XCTUnwrap(store.items.first(where: { $0.id == original.id }))
        XCTAssertNotNil(purchased.purchasedAt)
        XCTAssertEqual(purchased.purchaseCount, 1)
        let next = try store.buyAgain(original.id)
        XCTAssertNotEqual(next.id, original.id)
        XCTAssertNil(next.purchasedAt)
        XCTAssertEqual(next.title, original.title)
        XCTAssertEqual(next.quantity, original.quantity)
        XCTAssertEqual(next.note, original.note)
        XCTAssertEqual(next.placeID, original.placeID)
        XCTAssertEqual(next.purchaseCount, 0)
        XCTAssertEqual(next.effectiveFamilyID, original.effectiveFamilyID)

        let restored = ShoppingStore(container: container)
        XCTAssertEqual(restored.items.first(where: { $0.id == original.id })?.purchasedAt,
                       purchased.purchasedAt)
        XCTAssertEqual(restored.items.count, 2)
        try restored.togglePurchased(original.id)
        XCTAssertNil(restored.items.first(where: { $0.id == original.id })?.purchasedAt)
        XCTAssertEqual(restored.items.first(where: { $0.id == original.id })?.purchaseCount, 1)
        XCTAssertEqual(ShoppingStore(container: container).items.filter(\.isPurchased).count, 0)
    }

    func testPlaceDeletionAndReordering_keepItemsAndPersistOrder() throws {
        let container = try makeContainer()
        let store = ShoppingStore(container: container)
        let supermarket = try store.addPlace(name: "スーパー")
        let pharmacy = try store.addPlace(name: "ドラッグストア")
        let convenienceStore = try store.addPlace(name: "コンビニ")
        let grocery = try store.addItem(title: "卵", placeID: supermarket.id)
        let purchased = try store.addItem(title: "洗剤", placeID: supermarket.id)
        let medicine = try store.addItem(title: "薬", placeID: pharmacy.id)
        try store.togglePurchased(purchased.id)
        let purchasedAt = store.items.first(where: { $0.id == purchased.id })?.purchasedAt

        try store.movePlaces(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(ShoppingStore(container: container).places.map(\.id),
                       [convenienceStore.id, supermarket.id, pharmacy.id])
        try store.deletePlace(supermarket.id)

        let restored = ShoppingStore(container: container)
        XCTAssertEqual(restored.places.map(\.id), [convenienceStore.id, pharmacy.id])
        XCTAssertEqual(restored.places.map(\.orderIndex), [0, 1])
        XCTAssertEqual(restored.items.count, 3)
        XCTAssertNil(restored.items.first(where: { $0.id == grocery.id })?.placeID)
        XCTAssertNil(restored.items.first(where: { $0.id == purchased.id })?.placeID)
        XCTAssertEqual(restored.items.first(where: { $0.id == purchased.id })?.purchasedAt, purchasedAt)
        XCTAssertEqual(restored.items.first(where: { $0.id == medicine.id })?.placeID, pharmacy.id)
    }

    func testFailedSave_rollsBackShoppingOnlyAndKeepsPublishedSnapshots() throws {
        let container = try makeContainer()
        var failNextSave = false
        let store = ShoppingStore(container: container) { context in
            if failNextSave { throw SaveFailure.injected }
            try context.save()
        }
        let place = try store.addPlace(name: "スーパー")
        let item = try store.addItem(title: "パン", placeID: place.id)
        let originalItems = store.items
        let originalPlaces = store.places

        // Unrelated unsaved edits belong to the app's main context.
        let mainContext = container.mainContext
        mainContext.autosaveEnabled = false
        let pendingTask = SDTask(title: "まだ保存していない予定")
        mainContext.insert(pendingTask)
        failNextSave = true
        XCTAssertThrowsError(try store.deletePlace(place.id))
        XCTAssertEqual(store.items, originalItems)
        XCTAssertEqual(store.places, originalPlaces)
        XCTAssertTrue(mainContext.hasChanges)
        XCTAssertEqual(pendingTask.title, "まだ保存していない予定")

        let restored = ShoppingStore(container: container)
        XCTAssertEqual(restored.items.first?.placeID, place.id)
        XCTAssertEqual(restored.places.first?.id, place.id)
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<SDTask>()).isEmpty)

        failNextSave = false
        try store.togglePurchased(item.id)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertTrue(store.items[0].isPurchased)
        XCTAssertTrue(mainContext.hasChanges)

        let purchasedSnapshot = store.items
        failNextSave = true
        XCTAssertThrowsError(try store.restorePurchaseState(for: item.id, purchasedAt: nil, purchaseCount: 0))
        XCTAssertEqual(store.items, purchasedSnapshot)
        XCTAssertEqual(ShoppingStore(container: container).items, purchasedSnapshot)
        XCTAssertTrue(mainContext.hasChanges)
        failNextSave = false
        try store.restorePurchaseState(for: item.id, purchasedAt: nil, purchaseCount: 0)
        XCTAssertFalse(store.items[0].isPurchased)
        XCTAssertEqual(store.items[0].purchaseCount, 0)
        XCTAssertTrue(mainContext.hasChanges)
    }

    func testRepeatedPurchasesAndBuyAgain_shareFrequencyWithoutMatchingTitles() throws {
        let container = try makeContainer()
        let store = ShoppingStore(container: container)
        let original = try store.addItem(title: "牛乳")
        let independentlyAdded = try store.addItem(title: "牛乳")
        try store.togglePurchased(original.id)
        try store.togglePurchased(original.id)
        XCTAssertEqual(store.items.first { $0.id == original.id }?.purchaseCount, 1)
        try store.togglePurchased(original.id)
        XCTAssertEqual(store.items.first { $0.id == original.id }?.purchaseCount, 2)

        let copy = try store.buyAgain(original.id)
        XCTAssertEqual(copy.purchaseCount, 0)
        XCTAssertEqual(copy.effectiveFamilyID, original.id)
        try store.togglePurchased(copy.id)
        let nextCopy = try store.buyAgain(copy.id)
        XCTAssertEqual(nextCopy.effectiveFamilyID, original.id)

        let restored = ShoppingStore(container: container)
        let family = restored.items.filter { $0.effectiveFamilyID == original.effectiveFamilyID }
        XCTAssertEqual(family.count, 3)
        XCTAssertEqual(family.map(\.purchaseCount).reduce(0, +), 3)
        XCTAssertEqual(restored.items.first { $0.id == original.id }?.purchaseCount, 2)
        XCTAssertEqual(restored.items.first { $0.id == copy.id }?.purchaseCount, 1)
        XCTAssertEqual(restored.items.first { $0.id == nextCopy.id }?.purchaseCount, 0)
        XCTAssertEqual(restored.items.first { $0.id == independentlyAdded.id }?.effectiveFamilyID,
                       independentlyAdded.id)
    }

    func testUndoPurchase_restoresFrequencyAndPreservesNewerItemEdits() throws {
        let container = try makeContainer()
        let store = ShoppingStore(container: container)
        let originalPlace = try store.addPlace(name: "スーパー")
        let changedPlace = try store.addPlace(name: "別のお店")
        let original = try store.addItem(title: "牛乳", quantity: "1本", note: "元のメモ",
                                         placeID: originalPlace.id)
        try store.togglePurchased(original.id)
        let checked = try XCTUnwrap(store.items.first { $0.id == original.id })

        // A draft created before the check must not erase its newer purchase metadata.
        var editedDraft = original
        editedDraft.title = "豆乳"
        editedDraft.quantity = "2本"
        editedDraft.note = "編集後のメモ"
        editedDraft.placeID = changedPlace.id
        try store.updateItem(editedDraft)
        XCTAssertEqual(store.items.first?.purchasedAt, checked.purchasedAt)
        XCTAssertEqual(store.items.first?.purchaseCount, checked.purchaseCount)

        try store.restorePurchaseState(for: original.id,
                                       purchasedAt: original.purchasedAt,
                                       purchaseCount: original.purchaseCount)
        var restored = try XCTUnwrap(ShoppingStore(container: container).items.first)
        XCTAssertNil(restored.purchasedAt)
        XCTAssertEqual(restored.purchaseCount, 0)
        XCTAssertEqual(restored.title, "豆乳")
        XCTAssertEqual(restored.quantity, "2本")
        XCTAssertEqual(restored.note, "編集後のメモ")
        XCTAssertEqual(restored.placeID, changedPlace.id)
        XCTAssertEqual(restored.createdAt, original.createdAt)

        try store.togglePurchased(original.id)
        try store.togglePurchased(original.id)
        // A normal unpurchase retains count=1; undoing its next check restores that count.
        restored = try XCTUnwrap(store.items.first)
        XCTAssertEqual(restored.purchaseCount, 1)
        XCTAssertNil(restored.purchasedAt)
        try store.togglePurchased(original.id)
        XCTAssertEqual(store.items.first?.purchaseCount, 2)
        try store.restorePurchaseState(for: original.id,
                                       purchasedAt: restored.purchasedAt,
                                       purchaseCount: restored.purchaseCount)
        XCTAssertEqual(store.items.first?.purchaseCount, 1)
        XCTAssertNil(store.items.first?.purchasedAt)
    }

    func testLegacyShoppingJSON_decodesNewMetadataWithoutInferringPastPurchases() throws {
        let item = ShoppingItem(title: "牛乳", quantity: "2本", note: "元の内容",
                                placeID: UUID(), purchasedAt: Date(timeIntervalSince1970: 123),
                                purchaseCount: 5, familyID: UUID())
        let currentJSON = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(ShoppingItem.self, from: currentJSON), item)
        var oldFields = try XCTUnwrap(JSONSerialization.jsonObject(with: currentJSON) as? [String: Any])
        oldFields.removeValue(forKey: "purchaseCount")
        oldFields.removeValue(forKey: "familyID")

        let oldJSON = try JSONSerialization.data(withJSONObject: oldFields)
        let restored = try JSONDecoder().decode(ShoppingItem.self, from: oldJSON)
        XCTAssertEqual(restored.purchaseCount, 0)
        XCTAssertNil(restored.familyID)
        XCTAssertEqual(restored.effectiveFamilyID, item.id)
        XCTAssertEqual(restored.purchasedAt, item.purchasedAt)
        XCTAssertEqual(restored.title, item.title)
        XCTAssertEqual(restored.quantity, item.quantity)
        XCTAssertEqual(restored.note, item.note)
        XCTAssertEqual(restored.placeID, item.placeID)
    }

    func testAddingPurchaseMetadata_preservesExistingShoppingRowsAndTasks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("shopping-metadata-migration.store")
        let taskID = UUID()
        let itemID = UUID()
        let placeID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let purchasedAt = Date(timeIntervalSince1970: 2_000)

        try autoreleasepool {
            let types = legacyModelTypes + [ShoppingSchemaBeforeFrequency.SDShoppingItem.self, SDShoppingPlace.self]
            let schema = Schema(types)
            let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            context.insert(SDTask(id: taskID, title: "既存タスク"))
            context.insert(SDShoppingPlace(id: placeID, name: "元の購入先", orderIndex: 0))
            context.insert(ShoppingSchemaBeforeFrequency.SDShoppingItem(
                id: itemID, title: "元の商品", quantity: "2個", note: "元のメモ", placeID: placeID,
                createdAt: createdAt, purchasedAt: purchasedAt))
            try context.save()
        }

        var copyID: UUID!
        try autoreleasepool {
            let container = try makeDiskContainer(at: storeURL)
            let store = ShoppingStore(container: container)
            XCTAssertNil(store.loadError)
            let restored = try XCTUnwrap(store.items.first)
            XCTAssertEqual(restored.id, itemID)
            XCTAssertEqual(restored.title, "元の商品")
            XCTAssertEqual(restored.quantity, "2個")
            XCTAssertEqual(restored.note, "元のメモ")
            XCTAssertEqual(restored.placeID, placeID)
            XCTAssertEqual(restored.createdAt, createdAt)
            XCTAssertEqual(restored.purchasedAt, purchasedAt)
            XCTAssertEqual(restored.purchaseCount, 0)
            XCTAssertNil(restored.familyID)
            XCTAssertEqual(store.places.first?.id, placeID)
            XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<SDTask>()).first?.id, taskID)

            try store.togglePurchased(itemID)
            XCTAssertEqual(store.items.first?.purchaseCount, 0)
            try store.togglePurchased(itemID)
            XCTAssertEqual(store.items.first?.purchaseCount, 1)
            copyID = try store.buyAgain(itemID).id
        }

        try autoreleasepool {
            let store = ShoppingStore(container: try makeDiskContainer(at: storeURL))
            XCTAssertEqual(store.items.first { $0.id == itemID }?.purchaseCount, 1)
            XCTAssertEqual(store.items.first { $0.id == copyID }?.familyID, itemID)
            XCTAssertEqual(store.items.first { $0.id == copyID }?.purchaseCount, 0)
        }
    }

    func testAddingShoppingSchema_preservesExistingTaskAndSurvivesDiskReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("migration.store")
        let existingTaskID = UUID()

        try autoreleasepool {
            let legacySchema = Schema(legacyModelTypes)
            let configuration = ModelConfiguration(schema: legacySchema, url: storeURL,
                                                   cloudKitDatabase: .none)
            let container = try ModelContainer(for: legacySchema, configurations: [configuration])
            let context = ModelContext(container)
            context.insert(SDTask(id: existingTaskID, title: "以前からあるタスク", detail: "保持する本文"))
            try context.save()
        }

        var savedItemID: UUID!
        var savedPlaceID: UUID!
        try autoreleasepool {
            let container = try makeDiskContainer(at: storeURL)
            let tasks = try ModelContext(container).fetch(FetchDescriptor<SDTask>())
            XCTAssertEqual(tasks.first?.id, existingTaskID)
            XCTAssertEqual(tasks.first?.detail, "保持する本文")
            let store = ShoppingStore(container: container)
            XCTAssertNil(store.loadError)
            savedPlaceID = try store.addPlace(name: "近所のお店").id
            savedItemID = try store.addItem(title: "お米", quantity: "5kg", note: "いつもの",
                                            placeID: savedPlaceID).id
            try store.togglePurchased(savedItemID)
        }

        try autoreleasepool {
            let container = try makeDiskContainer(at: storeURL)
            let store = ShoppingStore(container: container)
            XCTAssertNil(store.loadError)
            XCTAssertEqual(store.places.first?.id, savedPlaceID)
            let item = try XCTUnwrap(store.items.first)
            XCTAssertEqual(item.id, savedItemID)
            XCTAssertEqual(item.title, "お米")
            XCTAssertEqual(item.quantity, "5kg")
            XCTAssertEqual(item.note, "いつもの")
            XCTAssertEqual(item.placeID, savedPlaceID)
            XCTAssertTrue(item.isPurchased)
            let tasks = try ModelContext(container).fetch(FetchDescriptor<SDTask>())
            XCTAssertEqual(tasks.first?.id, existingTaskID)
            XCTAssertEqual(tasks.first?.title, "以前からあるタスク")
        }
    }

    private var legacyModelTypes: [any PersistentModel.Type] {
        [SDTask.self, SDDiaryEntry.self, SDHabit.self, SDHabitRecord.self,
         SDAnniversary.self, SDHealthSummary.self, SDCalendarEvent.self,
         SDMemoPad.self, SDAppState.self, SDLetter.self, SDSharedLetter.self]
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([SDTask.self, SDShoppingItem.self, SDShoppingPlace.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                               cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeDiskContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema(legacyModelTypes + [SDShoppingItem.self, SDShoppingPlace.self])
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private enum SaveFailure: Error {
        case injected
    }
}

/// Uses the same entity name and fields as the schema shipped before frequency tracking.
private enum ShoppingSchemaBeforeFrequency {
    @Model
    final class SDShoppingItem {
        @Attribute(.unique) var id: UUID
        var title: String
        var quantity: String
        var note: String
        var placeID: UUID?
        var createdAt: Date
        var purchasedAt: Date?

        init(id: UUID, title: String, quantity: String, note: String, placeID: UUID?,
             createdAt: Date, purchasedAt: Date?) {
            self.id = id
            self.title = title
            self.quantity = quantity
            self.note = note
            self.placeID = placeID
            self.createdAt = createdAt
            self.purchasedAt = purchasedAt
        }
    }
}
