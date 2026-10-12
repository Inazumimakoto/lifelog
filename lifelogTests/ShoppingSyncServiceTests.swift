#if DEBUG
import Foundation
import SwiftData
import XCTest
@testable import lifelify

@MainActor
final class ShoppingSyncServiceTests: XCTestCase {
    private let owner = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    private let otherOwner = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
    private let date = Date(timeIntervalSince1970: 1_234.567)

    func testAccountChangeDuringWrite_keepsAttemptedOutboxAndRejectsAcknowledgement() async throws {
        let container = try makeContainer()
        let store = ShoppingStore(container: container, supportsShoppingSync: true)
        let local = try store.addItem(title: "牛乳", note: "1本")
        try store.enableSync(ownerID: owner)
        let transport = MockShoppingSyncTransport(owner: owner)
        transport.afterMutation = { [weak transport, otherOwner = self.otherOwner] _ in
            transport?.accountID = otherOwner.uuidString
            await _Concurrency.Task.yield()
        }
        let service = ShoppingSyncService(store: store, transport: transport, isUnlocked: { true })

        await service.synchronize()

        XCTAssertNotNil(service.errorMessage)
        XCTAssertEqual(store.items, [local])
        XCTAssertEqual(store.syncState?.ownerID, owner)
        XCTAssertEqual(store.syncState?.baselines.count, 0)
        XCTAssertEqual(store.syncState?.pending.count, 1)
        XCTAssertEqual(store.syncState?.attemptedOperationIDs.count, 1)
        XCTAssertNil(service.lastSyncedAt)
        let restarted = ShoppingStore(container: container, supportsShoppingSync: true)
        XCTAssertEqual(restarted.syncState, store.syncState)
        XCTAssertEqual(transport.sent.count, 1)
    }

    func testAccountChangeDuringPull_doesNotApplyOtherAccountResponseOrAdvanceCursor() async throws {
        let container = try makeContainer()
        let store = ShoppingStore(container: container, supportsShoppingSync: true)
        try store.enableSync(ownerID: owner)
        let transport = MockShoppingSyncTransport(owner: owner)
        transport.seed(record(ShoppingItem(title: "クラウドの商品", createdAt: date)))
        transport.afterPull = { [weak transport, otherOwner = self.otherOwner] _ in
            transport?.accountID = otherOwner.uuidString
            await _Concurrency.Task.yield()
        }
        let service = ShoppingSyncService(store: store, transport: transport, isUnlocked: { true })

        await service.synchronize()

        XCTAssertNotNil(service.errorMessage)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(store.syncState?.cursor, 0)
        XCTAssertTrue(store.syncState?.baselines.isEmpty == true)
        XCTAssertTrue(ShoppingStore(container: container, supportsShoppingSync: true).items.isEmpty)
    }

    func testLostCreateAcknowledgementThenLocalDelete_restartsWithSameOperationBeforeDeletingCloudRow() async throws {
        let container = try makeContainer()
        let store = ShoppingStore(container: container, supportsShoppingSync: true)
        let local = try store.addItem(title: "パン", note: "2袋")
        try store.enableSync(ownerID: owner)
        let transport = MockShoppingSyncTransport(owner: owner)
        transport.loseNextAcknowledgement = true
        do {
            let service = ShoppingSyncService(store: store, transport: transport, isUnlocked: { true })
            await service.synchronize()
            XCTAssertNotNil(service.errorMessage)
            XCTAssertEqual(transport.sent.count, 1)
            XCTAssertEqual(store.syncState?.pending.count, 1)
            XCTAssertEqual(transport.records.values.first?.isDeleted, false)
        }
        let attempted = try XCTUnwrap(store.syncState?.pending.first)
        try store.deleteItem(local.id)
        let restarted = ShoppingStore(container: container, supportsShoppingSync: true)
        XCTAssertTrue(restarted.items.isEmpty)
        XCTAssertEqual(restarted.syncState?.pending.first, attempted)
        let service = ShoppingSyncService(store: restarted, transport: transport, isUnlocked: { true })

        await service.synchronize()

        XCTAssertNil(service.errorMessage)
        XCTAssertEqual(transport.sent.count, 3)
        XCTAssertEqual(transport.sent[0], transport.sent[1], "A lost write must be replayed with the identical body and ID")
        XCTAssertEqual(transport.sent[2].id, local.id)
        XCTAssertTrue(transport.sent[2].deleted)
        XCTAssertEqual(transport.sent[2].baseVersion, 1)
        XCTAssertEqual(transport.records.values.first?.version, 2)
        XCTAssertEqual(transport.records.values.first?.isDeleted, true)
        XCTAssertEqual(transport.changes.count, 2, "Replaying a receipt must not append another event")
        XCTAssertTrue(restarted.items.isEmpty)
        XCTAssertTrue(restarted.syncState?.pending.isEmpty == true)
        XCTAssertTrue(ShoppingStore(container: container, supportsShoppingSync: true).items.isEmpty)
    }

    func testFailedMergeSave_keepsRowsAndCursorTogetherAndRetriesTheSamePage() async throws {
        let container = try makeContainer()
        var failNextSave = false
        let store = ShoppingStore(container: container, supportsShoppingSync: true) { context in
            if failNextSave { throw InjectedSaveFailure.failed }
            try context.save()
        }
        try store.enableSync(ownerID: owner)
        let originalState = try XCTUnwrap(store.syncState)
        let cloud = ShoppingItem(title: "リンゴ", note: "3個", createdAt: date)
        let transport = MockShoppingSyncTransport(owner: owner)
        transport.seed(record(cloud))
        transport.afterPull = { _ in failNextSave = true }
        let service = ShoppingSyncService(store: store, transport: transport, isUnlocked: { true })

        await service.synchronize()

        XCTAssertNotNil(service.errorMessage)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(store.syncState, originalState)
        let persisted = ShoppingStore(container: container, supportsShoppingSync: true)
        XCTAssertTrue(persisted.items.isEmpty)
        XCTAssertEqual(persisted.syncState, originalState)
        failNextSave = false
        transport.afterPull = nil

        await service.synchronize()

        XCTAssertNil(service.errorMessage)
        XCTAssertEqual(store.items, [cloud])
        XCTAssertEqual(store.syncState?.cursor, 1)
        XCTAssertEqual(transport.requestedCursors, [0, 0])
    }

    func testUnavailablePlaceForNewItem_preservesItemWhenUserChoosesUnassigned() async throws {
        let container = try makeContainer()
        let store = ShoppingStore(container: container, supportsShoppingSync: true)
        let place = try store.addPlace(name: "スーパー")
        let local = try store.addItem(title: "卵", note: "6個", placeID: place.id)
        var initial = ShoppingSyncState(ownerID: owner)
        _ = try initial.merge(ShoppingSyncPage(changes: [ShoppingSyncChange(seq: 1, record: record(place))],
                                                nextCursor: 1, hasMore: false), items: [], places: [])
        try store.saveSyncState(initial)
        let transport = MockShoppingSyncTransport(owner: owner)
        transport.seed(record(place))
        transport.seed(record(place, version: 2, deletedAt: 4_000))
        let service = ShoppingSyncService(store: store, transport: transport, isUnlocked: { true })

        await service.synchronize()

        XCTAssertEqual(service.conflict?.response.error, "place_unavailable")
        XCTAssertNil(service.conflict?.response.record)
        XCTAssertEqual(store.items, [local])
        await service.resolveUnavailablePlace()

        XCTAssertNil(service.conflict)
        XCTAssertNil(service.errorMessage)
        let preserved = try XCTUnwrap(store.items.first)
        XCTAssertEqual(preserved.id, local.id)
        XCTAssertEqual(preserved.title, local.title)
        XCTAssertEqual(preserved.note, local.note)
        XCTAssertNil(preserved.placeID)
        XCTAssertTrue(store.places.isEmpty)
        XCTAssertEqual(transport.sent.count, 2)
        XCTAssertNotEqual(transport.sent[0].operationID, transport.sent[1].operationID)
        XCTAssertEqual(transport.sent[1].data, .item(ShoppingSyncItemData(preserved)))
        XCTAssertEqual(transport.records[preserved.idKey]?.isDeleted, false)
    }

    func testFirstPhoneUploadAndCloudAddition_preservesBothDatasetsAcrossPaginatedPull() async throws {
        let container = try makeContainer()
        let store = ShoppingStore(container: container, supportsShoppingSync: true)
        let phonePlace = try store.addPlace(name: "薬局")
        let phone = ShoppingItem(title: "洗剤", note: "詰替え", placeID: phonePlace.id, createdAt: date)
        try store.restoreItem(phone)
        let cloudPlace = ShoppingPlace(name: "スーパー", orderIndex: 1)
        let cloud = ShoppingItem(title: "牛乳", note: "1本", placeID: cloudPlace.id,
                                 createdAt: date.addingTimeInterval(1))
        let transport = MockShoppingSyncTransport(owner: owner)
        transport.pageSize = 1
        transport.seed(record(cloudPlace))
        transport.seed(record(cloud))
        let service = ShoppingSyncService(store: store, transport: transport, isUnlocked: { true })

        await service.enable()

        XCTAssertNil(service.errorMessage)
        XCTAssertNotNil(service.lastSyncedAt)
        XCTAssertEqual(transport.sent.map(\.entity), [.place, .item])
        XCTAssertEqual(Set(store.items), Set([phone, cloud]))
        XCTAssertEqual(Set(store.places), Set([phonePlace, cloudPlace]))
        XCTAssertEqual(store.syncState?.cursor, 4)
        XCTAssertTrue(store.syncState?.pending.isEmpty == true)
        XCTAssertEqual(transport.records.count, 4)
        let restored = ShoppingStore(container: container, supportsShoppingSync: true)
        XCTAssertEqual(Set(restored.items), Set([phone, cloud]))
        XCTAssertEqual(restored.syncState, store.syncState)
    }

    func testConcurrentEdit_keepPhoneChoiceUsesObservedCloudVersionForFollowingWrite() async throws {
        let fixture = try concurrentEditFixture()
        let service = ShoppingSyncService(store: fixture.store, transport: fixture.transport, isUnlocked: { true })

        await service.synchronize()

        XCTAssertEqual(service.conflict?.response.error, "version_conflict")
        XCTAssertEqual(service.conflict?.response.record?.version, 2)
        XCTAssertEqual(fixture.store.items, [fixture.local])
        XCTAssertEqual(fixture.transport.sent.map(\.baseVersion), [1])
        await service.resolveConflict(keepLocal: true)

        XCTAssertNil(service.errorMessage)
        XCTAssertNil(service.conflict)
        XCTAssertEqual(fixture.transport.sent.map(\.baseVersion), [1, 2])
        XCTAssertNotEqual(fixture.transport.sent[0].operationID, fixture.transport.sent[1].operationID)
        let server = try XCTUnwrap(fixture.transport.records[fixture.local.idKey])
        XCTAssertEqual(server.version, 3)
        XCTAssertEqual(server.item, fixture.local)
        XCTAssertEqual(fixture.store.items, [fixture.local])
        XCTAssertTrue(fixture.store.syncState?.pending.isEmpty == true)
        XCTAssertEqual(fixture.store.syncState?.cursor, 3)
    }

    func testConcurrentEdit_useCloudChoiceAppliesRemoteRowWithoutReuploadingOldPhoneEdit() async throws {
        let fixture = try concurrentEditFixture()
        let service = ShoppingSyncService(store: fixture.store, transport: fixture.transport, isUnlocked: { true })

        await service.synchronize()

        XCTAssertNotNil(service.conflict)
        XCTAssertEqual(fixture.store.items, [fixture.local])
        await service.resolveConflict(keepLocal: false)

        XCTAssertNil(service.errorMessage)
        XCTAssertNil(service.conflict)
        XCTAssertEqual(fixture.store.items, [fixture.remote])
        XCTAssertEqual(fixture.transport.sent.count, 1, "Accepting the cloud edit must not send another local write")
        XCTAssertEqual(fixture.transport.records[fixture.remote.idKey]?.version, 2)
        XCTAssertEqual(fixture.transport.records[fixture.remote.idKey]?.item, fixture.remote)
        XCTAssertTrue(fixture.store.syncState?.pending.isEmpty == true)
        XCTAssertEqual(fixture.store.syncState?.cursor, 2)
    }

    private func concurrentEditFixture() throws -> (store: ShoppingStore, transport: MockShoppingSyncTransport,
                                                    local: ShoppingItem, remote: ShoppingItem) {
        let store = ShoppingStore(container: try makeContainer(), supportsShoppingSync: true)
        let original = ShoppingItem(title: "牛乳", note: "1本", createdAt: date)
        try store.restoreItem(original)
        var baseline = ShoppingSyncState(ownerID: owner)
        _ = try baseline.merge(ShoppingSyncPage(changes: [ShoppingSyncChange(seq: 1, record: record(original))],
                                                 nextCursor: 1, hasMore: false), items: [], places: [])
        try store.saveSyncState(baseline)
        var local = original
        local.note = "2本"
        try store.updateItem(local)
        var remote = original
        remote.note = "3本"
        let transport = MockShoppingSyncTransport(owner: owner)
        transport.seed(record(original))
        transport.seed(record(remote, version: 2))
        return (store, transport, local, remote)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([SDShoppingItem.self, SDShoppingPlace.self, SDShoppingSyncState.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func record(_ item: ShoppingItem, version: Int = 1, deletedAt: Int64? = nil) -> ShoppingSyncRecord {
        ShoppingSyncRecord(entity: .item, id: item.id, version: version, deletedAt: deletedAt,
                           createdAt: ShoppingSyncItemData.milliseconds(item.createdAt), updatedAt: 3_000,
                           data: .item(ShoppingSyncItemData(item)))
    }

    private func record(_ place: ShoppingPlace, version: Int = 1, deletedAt: Int64? = nil) -> ShoppingSyncRecord {
        ShoppingSyncRecord(entity: .place, id: place.id, version: version, deletedAt: deletedAt,
                           createdAt: 1_000, updatedAt: 3_000, data: .place(ShoppingSyncPlaceData(place)))
    }

    private enum InjectedSaveFailure: Error { case failed }
}

@MainActor
private final class MockShoppingSyncTransport: ShoppingSyncTransport {
    var accountID: String?
    var pageSize = 100
    var loseNextAcknowledgement = false
    var afterMutation: (@MainActor (ShoppingSyncMutation) async throws -> Void)?
    var afterPull: (@MainActor (Int64) async throws -> Void)?
    private(set) var sent: [ShoppingSyncMutation] = []
    private(set) var requestedCursors: [Int64] = []
    private(set) var records: [String: ShoppingSyncRecord] = [:]
    private(set) var changes: [ShoppingSyncChange] = []
    private var receipts: [UUID: (ShoppingSyncMutation, ShoppingSyncMutationResponse)] = [:]
    private let owner: UUID

    init(owner: UUID) { self.owner = owner; accountID = owner.uuidString }
    nonisolated deinit {}

    func restoreSession() async {}

    func seed(_ record: ShoppingSyncRecord) {
        records[record.key] = record
        changes.append(ShoppingSyncChange(seq: Int64(changes.count + 1), record: record))
    }

    func shoppingChanges(after cursor: Int64, ownerID: UUID) async throws -> ShoppingSyncPage {
        guard ownerID == owner else { throw ShoppingSyncError.accountMismatch }
        requestedCursors.append(cursor)
        let remaining = changes.filter { $0.seq > cursor }
        let page = Array(remaining.prefix(pageSize))
        let result = ShoppingSyncPage(changes: page, nextCursor: page.last?.seq ?? cursor,
                                      hasMore: remaining.count > page.count)
        try await afterPull?(cursor)
        return result
    }

    func sendShoppingMutation(_ mutation: ShoppingSyncMutation, ownerID: UUID) async throws -> ShoppingSyncMutationResponse {
        guard ownerID == owner else { throw ShoppingSyncError.accountMismatch }
        sent.append(mutation)
        if let receipt = receipts[mutation.operationID] {
            guard receipt.0 == mutation else { throw ShoppingSyncError.invalidState }
            try await afterMutation?(mutation)
            return receipt.1
        }
        if case .item(let item)? = mutation.data, let placeID = item.placeID,
           records[ShoppingSyncRecord.key(entity: .place, id: placeID)]?.isDeleted != false {
            throw try conflict(error: "place_unavailable", mutation: mutation)
        }
        let previous = records[mutation.key]
        guard (previous?.version ?? 0) == mutation.baseVersion else {
            throw try conflict(error: "version_conflict", mutation: mutation)
        }
        let data = try XCTUnwrap(mutation.data ?? previous?.data)
        let createdAt: Int64
        if let previous { createdAt = previous.createdAt }
        else if case .item(let item) = data { createdAt = item.createdAt }
        else { createdAt = 3_000 }
        let next = ShoppingSyncRecord(entity: mutation.entity, id: mutation.id, version: mutation.baseVersion + 1,
                                       deletedAt: mutation.deleted ? 4_000 : nil, createdAt: createdAt,
                                       updatedAt: 4_000, data: data)
        seed(next)
        let response = ShoppingSyncMutationResponse(record: next)
        receipts[mutation.operationID] = (mutation, response)
        try await afterMutation?(mutation)
        if loseNextAcknowledgement {
            loseNextAcknowledgement = false
            throw URLError(.networkConnectionLost)
        }
        return response
    }

    private func conflict(error: String, mutation: ShoppingSyncMutation) throws -> ShoppingSyncConflictFailure {
        let payload: Data
        if let current = records[mutation.key] {
            let response = try XCTUnwrap(JSONSerialization.jsonObject(with:
                JSONEncoder().encode(ShoppingSyncMutationResponse(record: current))) as? [String: Any])
            var fields = response
            fields["error"] = error
            payload = try JSONSerialization.data(withJSONObject: fields)
        } else {
            payload = try JSONSerialization.data(withJSONObject: ["error": error, "entity": mutation.entity.rawValue, "record": NSNull()])
        }
        return ShoppingSyncConflictFailure(response: try JSONDecoder().decode(ShoppingSyncConflictResponse.self, from: payload))
    }
}

private extension ShoppingItem {
    var idKey: String { ShoppingSyncRecord.key(entity: .item, id: id) }
}
#endif
