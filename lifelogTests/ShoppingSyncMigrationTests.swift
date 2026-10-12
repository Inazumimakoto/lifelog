#if DEBUG
import XCTest
import SwiftData
@testable import lifelify

/// Temporary, on-disk fixtures exercise real schema migration rather than the
/// in-memory model container. They never open or reset an app/simulator store.
@MainActor
final class ShoppingSyncMigrationTests: XCTestCase {
    func testAddingSyncMetadata_preservesExistingShoppingRowsAndSurvivesDiskReload() throws {
        try withTemporaryStore { url in
            let place = ShoppingPlace(name: "いつものスーパー", orderIndex: 2)
            let item = ShoppingItem(title: "卵", note: "6個入り1パック\n元のメモ", placeID: place.id,
                                    createdAt: Date(timeIntervalSince1970: 1_234.567))
            try autoreleasepool {
                let container = try makeContainer(at: url, types: [SDShoppingItem.self, SDShoppingPlace.self])
                let context = ModelContext(container)
                context.insert(SDShoppingPlace(id: place.id, name: place.name, orderIndex: place.orderIndex))
                context.insert(SDShoppingItem(domain: item))
                try context.save()
            }
            let owner = UUID()
            try autoreleasepool {
                let container = try makeContainer(at: url, types: shoppingSyncTypes)
                let store = ShoppingStore(container: container, supportsShoppingSync: true)
                XCTAssertNil(store.loadError)
                XCTAssertEqual(store.items, [item])
                XCTAssertEqual(store.places, [place])
                XCTAssertNil(store.syncState)
                try store.enableSync(ownerID: owner)
                var state = try XCTUnwrap(store.syncState)
                state.stageChanges(items: store.items, places: store.places)
                try store.saveSyncState(state)
            }
            try autoreleasepool {
                let container = try makeContainer(at: url, types: shoppingSyncTypes)
                let store = ShoppingStore(container: container, supportsShoppingSync: true)
                XCTAssertNil(store.loadError)
                XCTAssertEqual(store.items, [item])
                XCTAssertEqual(store.places, [place])
                XCTAssertEqual(store.syncState?.ownerID, owner)
                XCTAssertEqual(Set(try XCTUnwrap(store.syncState).pending.map(\.id)), [item.id, place.id])
            }
        }
    }

    func testAddingSyncMetadataToShippedQuantitySchema_preservesQuantityAsMemoWithoutDuplicatingIt() throws {
        try withTemporaryStore { url in
            let place = ShoppingPlace(name: "元の購入先", orderIndex: 4)
            let item = ShoppingItem(title: "牛乳", note: "2本\n低脂肪", placeID: place.id,
                                    createdAt: Date(timeIntervalSince1970: 1_000))
            try autoreleasepool {
                let container = try makeContainer(at: url,
                                                  types: [ShoppingSyncShippedSchema.SDShoppingItem.self, SDShoppingPlace.self])
                let context = ModelContext(container)
                context.insert(SDShoppingPlace(id: place.id, name: place.name, orderIndex: place.orderIndex))
                context.insert(ShoppingSyncShippedSchema.SDShoppingItem(
                    id: item.id, title: item.title, quantity: "2本", note: "低脂肪",
                    placeID: item.placeID, createdAt: item.createdAt))
                try context.save()
            }
            for _ in 0..<2 {
                try autoreleasepool {
                    let container = try makeContainer(at: url, types: shoppingSyncTypes)
                    let store = ShoppingStore(container: container, supportsShoppingSync: true)
                    XCTAssertNil(store.loadError)
                    XCTAssertEqual(store.items, [item])
                    XCTAssertEqual(store.places, [place])
                    XCTAssertNil(store.syncState)
                    XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<SDShoppingItem>())
                        .allSatisfy { $0.legacyQuantity.isEmpty })
                }
            }
        }
    }

    func testAddingSyncMetadataToWholeAppSchema_preservesShoppingTaskAndDiaryRows() throws {
        try withTemporaryStore { url in
            let previousTypes: [any PersistentModel.Type] = [
                SDTask.self, SDDiaryEntry.self, SDHabit.self, SDHabitRecord.self,
                SDAnniversary.self, SDHealthSummary.self, SDCalendarEvent.self,
                SDMemoPad.self, SDAppState.self, SDLetter.self, SDSharedLetter.self,
                SDShoppingItem.self, SDShoppingPlace.self
            ]
            let taskID = UUID()
            let diaryID = UUID()
            let place = ShoppingPlace(name: "スーパー")
            let item = ShoppingItem(title: "パン", note: "1袋", placeID: place.id,
                                    createdAt: Date(timeIntervalSince1970: 2_000))
            try autoreleasepool {
                let container = try makeContainer(at: url, types: previousTypes)
                let context = ModelContext(container)
                context.insert(SDTask(id: taskID, title: "保持するタスク", detail: "元の本文"))
                context.insert(SDDiaryEntry(id: diaryID, date: item.createdAt, text: "保持する日記本文"))
                context.insert(SDShoppingPlace(id: place.id, name: place.name, orderIndex: place.orderIndex))
                context.insert(SDShoppingItem(domain: item))
                try context.save()
            }
            try autoreleasepool {
                let container = try makeContainer(at: url, types: previousTypes + [SDShoppingSyncState.self])
                let store = ShoppingStore(container: container, supportsShoppingSync: true)
                XCTAssertNil(store.loadError)
                XCTAssertEqual(store.items, [item])
                XCTAssertEqual(store.places, [place])
                let context = ModelContext(container)
                let task = try XCTUnwrap(context.fetch(FetchDescriptor<SDTask>()).first)
                XCTAssertEqual(task.id, taskID)
                XCTAssertEqual(task.detail, "元の本文")
                let diary = try XCTUnwrap(context.fetch(FetchDescriptor<SDDiaryEntry>()).first)
                XCTAssertEqual(diary.id, diaryID)
                XCTAssertEqual(diary.text, "保持する日記本文")
                XCTAssertTrue(try context.fetch(FetchDescriptor<SDShoppingSyncState>()).isEmpty)
            }
        }
    }

    private var shoppingSyncTypes: [any PersistentModel.Type] {
        [SDShoppingItem.self, SDShoppingPlace.self, SDShoppingSyncState.self]
    }

    private func makeContainer(at url: URL, types: [any PersistentModel.Type]) throws -> ModelContainer {
        let schema = Schema(types)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func withTemporaryStore(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shopping-sync-migration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("shopping.store"))
    }
}

/// Matches HEAD's persisted entity name and fields, including a quantity with
/// no declaration default. The new domain/UI exposes quantities only in notes.
private enum ShoppingSyncShippedSchema {
    @Model
    final class SDShoppingItem {
        @Attribute(.unique) var id: UUID
        var title: String
        var quantity: String
        var note: String
        var placeID: UUID?
        var createdAt: Date
        var purchasedAt: Date?

        init(id: UUID = UUID(), title: String, quantity: String = "", note: String = "",
             placeID: UUID? = nil, createdAt: Date = Date(), purchasedAt: Date? = nil) {
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
#endif
