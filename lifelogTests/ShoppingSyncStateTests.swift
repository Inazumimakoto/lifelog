#if DEBUG
import XCTest
@testable import lifelify

@MainActor
final class ShoppingSyncStateTests: XCTestCase {
    private let owner = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    private let firstID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
    private let secondID = UUID(uuidString: "20000000-0000-4000-8000-000000000002")!
    private let placeID = UUID(uuidString: "30000000-0000-4000-8000-000000000001")!
    private let date = Date(timeIntervalSince1970: 1_234.567)

    func testFirstPhoneUpload_preservesIdentityMemoAndCreatesPlacesBeforeItems() throws {
        let place = ShoppingPlace(id: placeID, name: "スーパー", orderIndex: 3)
        let first = item(id: firstID, title: "卵", note: "6個入り1パック", placeID: place.id)
        let second = item(id: secondID, title: "卵", note: "2パック")
        var state = ShoppingSyncState(ownerID: owner)

        let pending = state.stageChanges(items: [first, second], places: [place])

        XCTAssertEqual(pending.map(\.entity), [.place, .item, .item])
        XCTAssertEqual(Set(pending.map(\.id)), [first.id, second.id, place.id])
        XCTAssertTrue(pending.allSatisfy { $0.baseVersion == 0 && !$0.deleted })
        let firstWrite = try XCTUnwrap(pending.first { $0.id == first.id })
        XCTAssertEqual(firstWrite.data, .item(ShoppingSyncItemData(first)))
        let originalOperationIDs = pending.map(\.operationID)
        XCTAssertEqual(state.stageChanges(items: [second, first], places: [place]).map(\.operationID), originalOperationIDs)
    }

    func testAddThenDeleteBeforeSending_cancelsUnsentCreationWithoutCloudTombstone() {
        var state = ShoppingSyncState(ownerID: owner)
        XCTAssertEqual(state.stageChanges(items: [item()], places: []).count, 1)

        state.stageChanges(items: [], places: [])

        XCTAssertTrue(state.pending.isEmpty)
        XCTAssertTrue(state.baselines.isEmpty)
    }

    func testRestartAfterLostAcknowledgment_retainsExactAttemptedOperationDespiteNewLocalEdit() throws {
        let original = item(title: "りんご", note: "3つ")
        var state = ShoppingSyncState(ownerID: owner)
        let operation = try XCTUnwrap(state.stageChanges(items: [original], places: []).first)
        try state.markAttempted(operation)
        let bodyBeforeRestart = try JSONEncoder().encode(operation)

        var restarted = try JSONDecoder().decode(ShoppingSyncState.self, from: JSONEncoder().encode(state))
        var updated = original
        updated.note = "4つに変更"
        restarted.stageChanges(items: [updated], places: [])

        XCTAssertEqual(restarted.pending, [operation])
        XCTAssertEqual(try JSONDecoder().decode(ShoppingSyncMutation.self, from: bodyBeforeRestart), restarted.pending.first)
        XCTAssertEqual(restarted.attemptedOperationIDs, [operation.operationID])
        try restarted.validate()
    }

    func testOfflineDeletionAndServerEdit_doesNotResurrectDeletedLocalRow() throws {
        let original = item(note: "1本")
        var state = try syncedState(items: [original])
        let deletion = try XCTUnwrap(state.stageChanges(items: [], places: []).first)
        try state.markAttempted(deletion)
        var remoteEdited = original
        remoteEdited.note = "2本"
        let page = ShoppingSyncPage(changes: [ShoppingSyncChange(seq: 2, record: record(remoteEdited, version: 2))],
                                    nextCursor: 2, hasMore: false)

        let result = try state.merge(page, items: [], places: [])

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(state.pending, [deletion])
        XCTAssertEqual(state.baselines[deletion.key]?.version, 1)
        XCTAssertEqual(state.cursor, 2)
    }

    func testCloudAdditionAndConcurrentPhoneEdit_mergesNewIDWithoutRebasingDirtyPhoneRow() throws {
        let original = item(note: "1本")
        var state = try syncedState(items: [original])
        var localEdited = original
        localEdited.note = "端末で2本に変更"
        var remoteEdited = original
        remoteEdited.note = "ChatGPTで3本に変更"
        let cloudAdded = item(id: secondID, title: "パン")
        let page = ShoppingSyncPage(changes: [
            ShoppingSyncChange(seq: 2, record: record(remoteEdited, version: 2)),
            ShoppingSyncChange(seq: 3, record: record(cloudAdded))
        ], nextCursor: 3, hasMore: false)

        let result = try state.merge(page, items: [localEdited], places: [])
        state.stageChanges(items: result.items, places: result.places)

        XCTAssertEqual(result.items.first { $0.id == original.id }, localEdited)
        XCTAssertEqual(result.items.first { $0.id == cloudAdded.id }, cloudAdded)
        XCTAssertEqual(state.pending.count, 1)
        XCTAssertEqual(state.pending.first?.id, original.id)
        XCTAssertEqual(state.pending.first?.baseVersion, 1)
    }

    func testSkippedRemoteEditAfterCursorAdvance_survivesRestartAndAppliesWhenPhoneReverts() throws {
        let original = item(note: "1本")
        var localEdited = original
        localEdited.note = "端末で2本に変更"
        var remoteEdited = original
        remoteEdited.note = "ChatGPTで3本に変更"
        var state = try syncedState(items: [original])
        let dirty = try state.merge(ShoppingSyncPage(changes: [ShoppingSyncChange(seq: 2, record: record(remoteEdited, version: 2))],
                                                     nextCursor: 2, hasMore: false), items: [localEdited], places: [])
        XCTAssertEqual(dirty.items, [localEdited])
        XCTAssertEqual(state.cursor, 2)
        var restarted = try JSONDecoder().decode(ShoppingSyncState.self, from: JSONEncoder().encode(state))
        restarted.stageChanges(items: [original], places: [])

        let restored = try restarted.merge(ShoppingSyncPage(changes: [], nextCursor: 2, hasMore: false),
                                            items: [original], places: [])

        XCTAssertEqual(restored.items, [remoteEdited])
        XCTAssertTrue(restarted.deferredRemote.isEmpty)
        XCTAssertTrue(restarted.stageChanges(items: restored.items, places: []).isEmpty)
    }

    func testOlderCreationAcknowledgment_preservesDeferredNewerServerEdit() throws {
        let original = item(note: "1本")
        var state = ShoppingSyncState(ownerID: owner)
        let creation = try XCTUnwrap(state.stageChanges(items: [original], places: []).first)
        try state.markAttempted(creation)
        var remoteEdited = original
        remoteEdited.note = "サーバーで2本に変更"
        _ = try state.merge(ShoppingSyncPage(changes: [ShoppingSyncChange(seq: 1, record: record(remoteEdited, version: 2))],
                                             nextCursor: 1, hasMore: false), items: [original], places: [])

        try state.acknowledge(creation, response: ShoppingSyncMutationResponse(record: record(original)))
        XCTAssertEqual(state.deferredRemote[creation.key]?.version, 2)
        state.stageChanges(items: [original], places: [])
        let result = try state.merge(ShoppingSyncPage(changes: [], nextCursor: 1, hasMore: false),
                                     items: [original], places: [])

        XCTAssertEqual(result.items, [remoteEdited])
        XCTAssertEqual(state.baselines[creation.key]?.version, 2)
    }

    func testUndoWhileDeleteIsInFlight_restoresSameIDWithAcknowledgedTombstoneVersion() throws {
        let original = item(note: "低脂肪")
        var state = try syncedState(items: [original])
        let deletion = try XCTUnwrap(state.stageChanges(items: [], places: []).first)
        try state.markAttempted(deletion)
        state.stageChanges(items: [original], places: [])
        XCTAssertEqual(state.pending, [deletion])

        try state.acknowledge(deletion, response: ShoppingSyncMutationResponse(record: record(original, version: 2, deletedAt: 4_000)))
        let restoration = try XCTUnwrap(state.stageChanges(items: [original], places: []).first)

        XCTAssertEqual(restoration.id, original.id)
        XCTAssertFalse(restoration.deleted)
        XCTAssertEqual(restoration.baseVersion, 2)
        XCTAssertEqual(restoration.data, .item(ShoppingSyncItemData(original)))
        XCTAssertNotEqual(restoration.operationID, deletion.operationID)
    }

    func testUnsentDeletionThenUndo_cancelsDeletionAgainstUnchangedBaseline() throws {
        let original = item()
        var state = try syncedState(items: [original])
        state.stageChanges(items: [], places: [])
        XCTAssertTrue(try XCTUnwrap(state.pending.first).deleted)

        state.stageChanges(items: [original], places: [])

        XCTAssertTrue(state.pending.isEmpty)
    }

    func testCreationAcknowledgmentAfterUserEdit_stagesNewerLocalSnapshotAsNextVersion() throws {
        let original = item(note: "1本")
        var state = ShoppingSyncState(ownerID: owner)
        let creation = try XCTUnwrap(state.stageChanges(items: [original], places: []).first)
        try state.markAttempted(creation)
        var edited = original
        edited.note = "2本"

        try state.acknowledge(creation, response: ShoppingSyncMutationResponse(record: record(original)))
        let next = try XCTUnwrap(state.stageChanges(items: [edited], places: []).first)

        XCTAssertEqual(next.id, original.id)
        XCTAssertEqual(next.baseVersion, 1)
        XCTAssertEqual(next.data, .item(ShoppingSyncItemData(edited)))
        XCTAssertEqual(state.baselines[creation.key]?.item?.note, "1本")
    }

    func testSameTitleOnPhoneAndCloud_keepsDistinctIDs() throws {
        let first = item(id: firstID, title: "牛乳")
        let second = item(id: secondID, title: "牛乳")
        var state = try syncedState(items: [first])

        let result = try state.merge(ShoppingSyncPage(changes: [ShoppingSyncChange(seq: 2, record: record(second))],
                                                     nextCursor: 2, hasMore: false), items: [first], places: [])

        XCTAssertEqual(result.items.map(\.title), ["牛乳", "牛乳"])
        XCTAssertEqual(Set(result.items.map(\.id)), [first.id, second.id])
        XCTAssertTrue(state.stageChanges(items: result.items, places: []).isEmpty)
    }

    func testPagedChanges_ignoreOlderAndRepeatedVersionsAndAdvanceCursor() throws {
        let original = item(note: "version 3")
        var state = ShoppingSyncState(ownerID: owner)
        _ = try state.merge(ShoppingSyncPage(changes: [ShoppingSyncChange(seq: 1, record: record(original, version: 3))],
                                             nextCursor: 1, hasMore: true), items: [], places: [])
        var stale = original
        stale.note = "version 2"
        let ignored = try state.merge(ShoppingSyncPage(changes: [
            ShoppingSyncChange(seq: 2, record: record(stale, version: 2)),
            ShoppingSyncChange(seq: 3, record: record(original, version: 3))
        ], nextCursor: 3, hasMore: true), items: [original], places: [])
        var latest = original
        latest.note = "version 4"

        let result = try state.merge(ShoppingSyncPage(changes: [ShoppingSyncChange(seq: 4, record: record(latest, version: 4))],
                                                     nextCursor: 4, hasMore: false), items: ignored.items, places: [])

        XCTAssertEqual(ignored.items, [original])
        XCTAssertEqual(result.items, [latest])
        XCTAssertEqual(state.cursor, 4)
        XCTAssertEqual(state.baselines.values.first?.version, 4)
    }

    func testCleanCloudDeletion_removesLocalItemAndRetainsTombstoneWithoutResubmittingIt() throws {
        let original = item()
        var state = try syncedState(items: [original])

        let result = try state.merge(ShoppingSyncPage(changes: [ShoppingSyncChange(seq: 2, record: record(original, version: 2, deletedAt: 4_000))],
                                                     nextCursor: 2, hasMore: false), items: [original], places: [])

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertTrue(state.baselines.values.first?.isDeleted == true)
        XCTAssertTrue(state.stageChanges(items: [], places: []).isEmpty)
    }

    func testDeletePlace_ordersDependentItemUpdateBeforePlaceTombstone() throws {
        let place = ShoppingPlace(id: placeID, name: "スーパー")
        let original = item(placeID: place.id)
        var state = try syncedState(items: [original], places: [place])
        var unassigned = original
        unassigned.placeID = nil
        let replacement = ShoppingPlace(id: secondID, name: "薬局")

        let writes = state.stageChanges(items: [unassigned], places: [replacement])

        XCTAssertEqual(writes.map(\.entity), [.place, .item, .place])
        XCTAssertEqual(writes.map(\.deleted), [false, false, true])
        XCTAssertEqual(writes.last?.id, place.id)
        XCTAssertEqual(writes[1].data, .item(ShoppingSyncItemData(unassigned)))
    }

    func testExplicitKeepPhoneConflict_rebasesOnlyAfterUserChoice() throws {
        let original = item(note: "1本")
        var local = original
        local.note = "2本"
        var remote = original
        remote.note = "3本"
        var state = try syncedState(items: [original])
        let attempted = try XCTUnwrap(state.stageChanges(items: [local], places: []).first)
        try state.markAttempted(attempted)
        XCTAssertEqual(attempted.baseVersion, 1)

        try state.resolveConflict(attempted, remoteRecord: record(remote, version: 2))
        let overwrite = try XCTUnwrap(state.stageChanges(items: [local], places: []).first)

        XCTAssertEqual(overwrite.baseVersion, 2)
        XCTAssertEqual(overwrite.data, .item(ShoppingSyncItemData(local)))
        XCTAssertNotEqual(overwrite.operationID, attempted.operationID)
        XCTAssertTrue(state.attemptedOperationIDs.isEmpty)
    }

    func testExplicitUseCloudConflict_leavesNoWriteWhenCloudSnapshotIsApplied() throws {
        let original = item(note: "1本")
        var local = original
        local.note = "2本"
        var remote = original
        remote.note = "3本"
        var state = try syncedState(items: [original])
        let attempted = try XCTUnwrap(state.stageChanges(items: [local], places: []).first)
        try state.markAttempted(attempted)

        try state.resolveConflict(attempted, remoteRecord: record(remote, version: 2))
        state.stageChanges(items: [remote], places: [])

        XCTAssertTrue(state.pending.isEmpty)
    }

    func testAccountChange_cannotAdoptPreviousAccountsOutboxImplicitly() throws {
        var state = ShoppingSyncState(ownerID: owner)
        state.stageChanges(items: [item()], places: [])
        let otherOwner = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!

        XCTAssertThrowsError(try state.ensureOwner(otherOwner)) {
            XCTAssertEqual($0 as? ShoppingSyncStateError, .accountMismatch)
        }
        XCTAssertNoThrow(try state.ensureOwner(owner))
        XCTAssertEqual(state.pending.count, 1)
    }

    func testWireMutation_usesLowercaseUUIDsExplicitNullAndNoOutboxOnlyFields() throws {
        let identity = UUID(uuidString: "ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF")!
        let operation = ShoppingSyncMutation(operationID: identity, entity: .item, id: identity,
                                            baseVersion: 0, deleted: false,
                                            data: .item(ShoppingSyncItemData(title: "卵", note: "6個", placeID: nil, createdAt: 1_000)))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(operation)) as? [String: Any])
        let data = try XCTUnwrap(payload["data"] as? [String: Any])

        XCTAssertEqual(Set(payload.keys), ["operation_id", "entity", "id", "base_version", "deleted", "data"])
        XCTAssertEqual(payload["id"] as? String, identity.uuidString.lowercased())
        XCTAssertEqual(payload["operation_id"] as? String, identity.uuidString.lowercased())
        XCTAssertTrue(data["place_id"] is NSNull)
        XCTAssertEqual(Set(data.keys), ["title", "note", "place_id", "created_at"])
        let deletion = ShoppingSyncMutation(entity: .item, id: identity, baseVersion: 1, deleted: true, data: nil)
        let deletePayload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(deletion)) as? [String: Any])
        XCTAssertTrue(deletePayload["data"] is NSNull)
    }

    func testWirePageAndConflict_decodeServerShapesAndMillisecondDates() throws {
        let wire = """
        {"changes":[{"seq":8,"entity":"item","record":{"id":"\(firstID.uuidString.lowercased())","title":"卵","note":"6個","place_id":null,"created_at":1234567,"updated_at":2345678,"version":2,"deleted_at":null}}],"next_cursor":8,"has_more":false}
        """
        let page = try JSONDecoder().decode(ShoppingSyncPage.self, from: Data(wire.utf8))

        XCTAssertEqual(page.changes.first?.record.item?.createdAt, date)
        XCTAssertEqual(ShoppingSyncItemData(try XCTUnwrap(page.changes.first?.record.item)).createdAt, 1_234_567)
        XCTAssertEqual(try JSONDecoder().decode(ShoppingSyncPage.self, from: JSONEncoder().encode(page)), page)
        let conflict = try JSONDecoder().decode(ShoppingSyncConflictResponse.self,
                                                from: Data(#"{"error":"version_conflict","entity":"item","record":null}"#.utf8))
        XCTAssertNil(conflict.record)
        XCTAssertEqual(conflict.error, "version_conflict")
    }

    func testInvalidPagination_doesNotAdvanceCursorOrApplyPartialPage() throws {
        let original = item()
        var state = try syncedState(items: [original])
        let before = state
        let invalid = ShoppingSyncPage(changes: [ShoppingSyncChange(seq: 2, record: record(item(id: secondID))),
                                                  ShoppingSyncChange(seq: 2, record: record(original, version: 2))],
                                       nextCursor: 2, hasMore: false)

        XCTAssertThrowsError(try state.merge(invalid, items: [original], places: []))
        XCTAssertEqual(state, before)
    }

    private func item(id: UUID? = nil, title: String = "牛乳", note: String = "", placeID: UUID? = nil) -> ShoppingItem {
        ShoppingItem(id: id ?? firstID, title: title, note: note, placeID: placeID, createdAt: date)
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

    private func syncedState(items: [ShoppingItem], places: [ShoppingPlace] = []) throws -> ShoppingSyncState {
        let records = places.map { record($0) } + items.map { record($0) }
        let changes = records.enumerated().map { ShoppingSyncChange(seq: Int64($0.offset + 1), record: $0.element) }
        var state = ShoppingSyncState(ownerID: owner)
        _ = try state.merge(ShoppingSyncPage(changes: changes, nextCursor: Int64(records.count), hasMore: false),
                            items: [], places: [])
        return state
    }
}
#endif
