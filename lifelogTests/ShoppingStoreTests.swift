import XCTest
import SwiftData
@testable import lifelify

@MainActor
final class ShoppingStoreTests: XCTestCase {
    func testDeleteAndUndo_restoreOriginalIdentityContentAndOrder() throws {
        let container = try makeContainer()
        let store = ShoppingStore(container: container)
        let place = try store.addPlace(name: "スーパー")
        let original = ShoppingItem(title: "牛乳", quantity: "2本", note: "低脂肪",
                                    placeID: place.id, createdAt: Date(timeIntervalSince1970: 1_000))
        try store.restoreItem(original)
        let another = try store.addItem(title: "パン")

        try store.deleteItem(original.id)
        XCTAssertEqual(store.items.map(\.id), [another.id])
        XCTAssertEqual(ShoppingStore(container: container).items.map(\.id), [another.id])
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<SDShoppingItem>()).count, 1)

        try store.restoreItem(original)
        let restored = ShoppingStore(container: container)
        XCTAssertEqual(restored.items, [original, another])
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<SDShoppingItem>())
            .allSatisfy { $0.purchasedAt == nil })
    }

    func testUndoAfterPlaceDeletion_restoresItemWithoutRecreatingPlace() throws {
        let container = try makeContainer()
        let store = ShoppingStore(container: container)
        let place = try store.addPlace(name: "スーパー")
        let original = try store.addItem(title: "卵", note: "6個", placeID: place.id)
        try store.deleteItem(original.id)
        try store.deletePlace(place.id)

        try store.restoreItem(original)
        var expected = original
        expected.placeID = nil
        XCTAssertEqual(store.items, [expected])
        XCTAssertEqual(ShoppingStore(container: container).items, [expected])
        XCTAssertTrue(store.places.isEmpty)
    }

    func testUndoWhenIdentityExists_preservesNewerRowAndDoesNotDuplicateIt() throws {
        let container = try makeContainer()
        let store = ShoppingStore(container: container)
        let original = try store.addItem(title: "牛乳", quantity: "1本", note: "元のメモ")
        try store.deleteItem(original.id)
        var newer = original
        newer.title = "豆乳"
        newer.quantity = "2本"
        newer.note = "編集後のメモ"
        newer.createdAt = Date(timeIntervalSince1970: 2_000)
        try store.restoreItem(newer)

        try store.restoreItem(original)
        XCTAssertEqual(store.items, [newer])
        XCTAssertEqual(ShoppingStore(container: container).items, [newer])
    }

    func testPlaceDeletionAndReordering_keepItemsAndPersistOrder() throws {
        let container = try makeContainer()
        let store = ShoppingStore(container: container)
        let supermarket = try store.addPlace(name: "スーパー")
        let pharmacy = try store.addPlace(name: "ドラッグストア")
        let convenienceStore = try store.addPlace(name: "コンビニ")
        let grocery = try store.addItem(title: "卵", placeID: supermarket.id)
        let detergent = try store.addItem(title: "洗剤", placeID: supermarket.id)
        let medicine = try store.addItem(title: "薬", placeID: pharmacy.id)

        try store.movePlaces(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(ShoppingStore(container: container).places.map(\.id),
                       [convenienceStore.id, supermarket.id, pharmacy.id])
        try store.deletePlace(supermarket.id)

        let restored = ShoppingStore(container: container)
        XCTAssertEqual(restored.places.map(\.id), [convenienceStore.id, pharmacy.id])
        XCTAssertEqual(restored.places.map(\.orderIndex), [0, 1])
        XCTAssertEqual(restored.items.count, 3)
        XCTAssertNil(restored.items.first(where: { $0.id == grocery.id })?.placeID)
        XCTAssertNil(restored.items.first(where: { $0.id == detergent.id })?.placeID)
        XCTAssertEqual(restored.items.first(where: { $0.id == medicine.id })?.placeID, pharmacy.id)
    }

    func testFailedSave_rollsBackDeleteAndUndoWithoutTouchingOtherContext() throws {
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

        let mainContext = container.mainContext
        mainContext.autosaveEnabled = false
        let pendingTask = SDTask(title: "まだ保存していない予定")
        mainContext.insert(pendingTask)
        failNextSave = true
        XCTAssertThrowsError(try store.deletePlace(place.id))
        XCTAssertThrowsError(try store.deleteItem(item.id))
        XCTAssertEqual(store.items, originalItems)
        XCTAssertEqual(store.places, originalPlaces)
        XCTAssertEqual(ShoppingStore(container: container).items, originalItems)
        XCTAssertTrue(mainContext.hasChanges)
        XCTAssertEqual(pendingTask.title, "まだ保存していない予定")
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<SDTask>()).isEmpty)

        failNextSave = false
        try store.deleteItem(item.id)
        XCTAssertTrue(store.items.isEmpty)
        failNextSave = true
        XCTAssertThrowsError(try store.restoreItem(item))
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(ShoppingStore(container: container).items.isEmpty)
        XCTAssertTrue(mainContext.hasChanges)

        failNextSave = false
        try store.restoreItem(item)
        XCTAssertEqual(store.items, originalItems)
        XCTAssertTrue(mainContext.hasChanges)
    }

    func testLegacyShoppingJSON_ignoresRemovedPurchaseMetadata() throws {
        let item = ShoppingItem(title: "牛乳", quantity: "2本", note: "元の内容", placeID: UUID())
        let currentJSON = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(ShoppingItem.self, from: currentJSON), item)
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: currentJSON) as? [String: Any])
        XCTAssertNil(fields["purchasedAt"])
        XCTAssertNil(fields["purchaseCount"])
        XCTAssertNil(fields["familyID"])
        fields["purchasedAt"] = 123
        fields["purchaseCount"] = 5
        fields["familyID"] = UUID().uuidString
        let legacyJSON = try JSONSerialization.data(withJSONObject: fields)
        XCTAssertEqual(try JSONDecoder().decode(ShoppingItem.self, from: legacyJSON), item)
    }

    func testFailedLegacyCleanup_keepsPersistedRowsAndRetriesBeforeAllowingWrites() throws {
        let container = try makeContainer()
        let seedContext = ModelContext(container)
        let place = SDShoppingPlace(name: "元の購入先")
        let pending = SDShoppingItem(title: "買う卵", note: "6個", placeID: place.id)
        let purchased = SDShoppingItem(title: "買った卵", purchasedAt: Date(timeIntervalSince1970: 2_000))
        seedContext.insert(place)
        seedContext.insert(pending)
        seedContext.insert(purchased)
        try seedContext.save()
        let pendingID = pending.id
        let purchasedID = purchased.id

        let mainContext = container.mainContext
        mainContext.autosaveEnabled = false
        mainContext.insert(SDTask(title: "未保存タスク"))
        var failNextSave = true
        let store = ShoppingStore(container: container) { context in
            if failNextSave { throw SaveFailure.injected }
            try context.save()
        }
        XCTAssertNotNil(store.loadError)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertThrowsError(try store.addItem(title: "追加を止める"))
        XCTAssertEqual(Set(try ModelContext(container).fetch(FetchDescriptor<SDShoppingItem>()).map(\.id)),
                       Set([pendingID, purchasedID]))
        XCTAssertTrue(mainContext.hasChanges)

        failNextSave = false
        try store.reload()
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.items.map(\.id), [pendingID])
        XCTAssertEqual(store.items.first?.placeID, place.id)
        XCTAssertEqual(store.places.map(\.id), [place.id])
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<SDShoppingItem>()).map(\.id),
                       [pendingID])
        XCTAssertTrue(mainContext.hasChanges)
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<SDTask>()).isEmpty)
        _ = try store.addItem(title: "再試行後の追加")
        XCTAssertEqual(store.items.count, 2)
    }

    func testReloadWithoutLegacyPurchases_doesNotWrite() throws {
        let container = try makeContainer()
        var saveCount = 0
        let store = ShoppingStore(container: container) { context in
            saveCount += 1
            try context.save()
        }
        try store.reload()
        XCTAssertEqual(saveCount, 0)
        _ = try store.addItem(title: "卵")
        XCTAssertEqual(saveCount, 1)
        try store.reload()
        XCTAssertEqual(saveCount, 1)
    }

    func testRemovingFrequencySchema_removesPurchasedRowsAndPreservesOtherDataAcrossDiskReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("shopping-history-removal.store")
        let taskID = UUID()
        let diaryID = UUID()
        let placeID = UUID()
        let pendingID = UUID()
        let independentPendingID = UUID()
        let purchasedID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let expected = ShoppingItem(id: pendingID, title: "卵", quantity: "2個", note: "元のメモ",
                                    placeID: placeID, createdAt: createdAt)

        try autoreleasepool {
            let types = legacyModelTypes + [ShoppingSchemaWithFrequency.SDShoppingItem.self, SDShoppingPlace.self]
            let container = try makeDiskContainer(at: storeURL, types: types)
            let context = ModelContext(container)
            context.insert(SDTask(id: taskID, title: "既存タスク", detail: "保持するタスク本文"))
            context.insert(SDDiaryEntry(id: diaryID, date: createdAt, text: "保持する日記本文"))
            context.insert(SDShoppingPlace(id: placeID, name: "元の購入先", orderIndex: 0))
            context.insert(ShoppingSchemaWithFrequency.SDShoppingItem(
                id: pendingID, title: expected.title, quantity: expected.quantity, note: expected.note,
                placeID: placeID, createdAt: createdAt, purchasedAt: nil,
                purchaseCount: 3, familyID: purchasedID))
            context.insert(ShoppingSchemaWithFrequency.SDShoppingItem(
                id: independentPendingID, title: "卵", quantity: "", note: "別に追加した商品",
                placeID: nil, createdAt: Date(timeIntervalSince1970: 1_001), purchasedAt: nil,
                purchaseCount: 0, familyID: nil))
            context.insert(ShoppingSchemaWithFrequency.SDShoppingItem(
                id: purchasedID, title: "卵", quantity: "6個", note: "購入済みの履歴",
                placeID: placeID, createdAt: createdAt, purchasedAt: Date(timeIntervalSince1970: 2_000),
                purchaseCount: 5, familyID: nil))
            try context.save()
        }

        try autoreleasepool {
            let container = try makeDiskContainer(at: storeURL)
            let store = ShoppingStore(container: container)
            XCTAssertNil(store.loadError)
            XCTAssertEqual(store.items.first, expected)
            XCTAssertEqual(store.items.map(\.id), [pendingID, independentPendingID])
            XCTAssertEqual(store.items.last?.note, "別に追加した商品")
            XCTAssertEqual(store.places.map(\.id), [placeID])
            XCTAssertEqual(store.places.first?.name, "元の購入先")
            let context = ModelContext(container)
            XCTAssertEqual(Set(try context.fetch(FetchDescriptor<SDShoppingItem>()).map(\.id)),
                           Set([pendingID, independentPendingID]))
            XCTAssertEqual(try context.fetch(FetchDescriptor<SDTask>()).first?.id, taskID)
            XCTAssertEqual(try context.fetch(FetchDescriptor<SDTask>()).first?.detail, "保持するタスク本文")
            XCTAssertEqual(try context.fetch(FetchDescriptor<SDDiaryEntry>()).first?.id, diaryID)
            XCTAssertEqual(try context.fetch(FetchDescriptor<SDDiaryEntry>()).first?.text, "保持する日記本文")
        }

        try autoreleasepool {
            let container = try makeDiskContainer(at: storeURL)
            let store = ShoppingStore(container: container)
            XCTAssertNil(store.loadError)
            XCTAssertEqual(store.items.first, expected)
            XCTAssertEqual(store.items.map(\.id), [pendingID, independentPendingID])
            XCTAssertEqual(store.places.map(\.id), [placeID])
            XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<SDTask>()).first?.id, taskID)
            XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<SDDiaryEntry>()).first?.id, diaryID)
        }
    }

    func testPreFrequencySchema_removesPurchasedRowsAndPreservesPendingItems() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("shopping-before-frequency.store")
        let taskID = UUID()
        let placeID = UUID()
        let item = ShoppingItem(title: "元の商品", quantity: "2個", note: "元のメモ", placeID: placeID,
                                createdAt: Date(timeIntervalSince1970: 1_000))

        try autoreleasepool {
            let types = legacyModelTypes + [ShoppingSchemaBeforeFrequency.SDShoppingItem.self, SDShoppingPlace.self]
            let container = try makeDiskContainer(at: storeURL, types: types)
            let context = ModelContext(container)
            context.insert(SDTask(id: taskID, title: "既存タスク"))
            context.insert(SDShoppingPlace(id: placeID, name: "元の購入先", orderIndex: 0))
            context.insert(ShoppingSchemaBeforeFrequency.SDShoppingItem(
                id: item.id, title: item.title, quantity: item.quantity, note: item.note,
                placeID: placeID, createdAt: item.createdAt, purchasedAt: nil))
            context.insert(ShoppingSchemaBeforeFrequency.SDShoppingItem(
                id: UUID(), title: "購入済み", quantity: "", note: "", placeID: placeID,
                createdAt: item.createdAt, purchasedAt: Date(timeIntervalSince1970: 2_000)))
            try context.save()
        }

        try autoreleasepool {
            let container = try makeDiskContainer(at: storeURL)
            let store = ShoppingStore(container: container)
            XCTAssertNil(store.loadError)
            XCTAssertEqual(store.items, [item])
            XCTAssertEqual(store.places.map(\.id), [placeID])
            XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<SDShoppingItem>()).map(\.id), [item.id])
            XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<SDTask>()).first?.id, taskID)
        }
    }

    func testAddingShoppingSchema_preservesExistingTaskAndSurvivesDiskReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("migration.store")
        let existingTaskID = UUID()

        try autoreleasepool {
            let container = try makeDiskContainer(at: storeURL, types: legacyModelTypes)
            let context = ModelContext(container)
            context.insert(SDTask(id: existingTaskID, title: "以前からあるタスク", detail: "保持する本文"))
            try context.save()
        }

        var savedItem: ShoppingItem!
        var savedPlaceID: UUID!
        try autoreleasepool {
            let container = try makeDiskContainer(at: storeURL)
            let tasks = try ModelContext(container).fetch(FetchDescriptor<SDTask>())
            XCTAssertEqual(tasks.first?.id, existingTaskID)
            XCTAssertEqual(tasks.first?.detail, "保持する本文")
            let store = ShoppingStore(container: container)
            XCTAssertNil(store.loadError)
            savedPlaceID = try store.addPlace(name: "近所のお店").id
            savedItem = try store.addItem(title: "お米", quantity: "5kg", note: "いつもの", placeID: savedPlaceID)
        }

        try autoreleasepool {
            let container = try makeDiskContainer(at: storeURL)
            let store = ShoppingStore(container: container)
            XCTAssertNil(store.loadError)
            XCTAssertEqual(store.places.first?.id, savedPlaceID)
            XCTAssertEqual(store.items, [savedItem])
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

    private func makeDiskContainer(at url: URL, types: [any PersistentModel.Type]? = nil) throws -> ModelContainer {
        let schema = Schema(types ?? (legacyModelTypes + [SDShoppingItem.self, SDShoppingPlace.self]))
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private enum SaveFailure: Error {
        case injected
    }
}

/// Matches the previously shipped entity name and schema, including retired frequency fields.
private enum ShoppingSchemaWithFrequency {
    @Model
    final class SDShoppingItem {
        @Attribute(.unique) var id: UUID
        var title: String
        var quantity: String
        var note: String
        var placeID: UUID?
        var createdAt: Date
        var purchasedAt: Date?
        var purchaseCount: Int = 0
        var familyID: UUID? = nil

        init(id: UUID, title: String, quantity: String, note: String, placeID: UUID?,
             createdAt: Date, purchasedAt: Date?, purchaseCount: Int, familyID: UUID?) {
            self.id = id
            self.title = title
            self.quantity = quantity
            self.note = note
            self.placeID = placeID
            self.createdAt = createdAt
            self.purchasedAt = purchasedAt
            self.purchaseCount = purchaseCount
            self.familyID = familyID
        }
    }
}

/// Matches the first shopping schema, before purchase frequency was added.
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
