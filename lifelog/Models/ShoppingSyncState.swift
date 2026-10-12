#if DEBUG
import Foundation

/// Wire values and durable outbox for the development shopping synchronization.
/// Persist this state together with any merged SwiftData rows in the same save.
/// See docs/requirements.md: 買い物リスト / ChatGPT連携.
enum ShoppingSyncEntity: String, Codable {
    case item, place
}

struct ShoppingSyncItemData: Codable, Equatable {
    var title: String
    var note: String
    var placeID: UUID?
    var createdAt: Int64

    init(title: String, note: String, placeID: UUID?, createdAt: Int64) {
        self.title = title
        self.note = note
        self.placeID = placeID
        self.createdAt = createdAt
    }

    init(_ item: ShoppingItem) {
        self.init(title: item.title, note: item.note, placeID: item.placeID,
                  createdAt: Self.milliseconds(item.createdAt))
    }

    private enum CodingKeys: String, CodingKey {
        case title, note
        case placeID = "place_id"
        case createdAt = "created_at"
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(title, forKey: .title)
        try values.encode(note, forKey: .note)
        if let placeID {
            try values.encode(placeID.uuidString.lowercased(), forKey: .placeID)
        } else {
            try values.encodeNil(forKey: .placeID)
        }
        try values.encode(createdAt, forKey: .createdAt)
    }

    static func milliseconds(_ date: Date) -> Int64 {
        // Millisecond precision is shared by D1 and the wire protocol. A decoded
        // millisecond must compare equal despite Date's floating-point storage.
        let value = (date.timeIntervalSince1970 * 1_000).rounded()
        guard value.isFinite, value >= 0, value < Double(Int64.max) else { return 0 }
        return Int64(value)
    }
}

struct ShoppingSyncPlaceData: Codable, Equatable {
    var name: String
    var orderIndex: Int

    init(name: String, orderIndex: Int) {
        self.name = name
        self.orderIndex = orderIndex
    }

    init(_ place: ShoppingPlace) {
        self.init(name: place.name, orderIndex: place.orderIndex)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case orderIndex = "order_index"
    }
}

enum ShoppingSyncData: Codable, Equatable {
    case item(ShoppingSyncItemData)
    case place(ShoppingSyncPlaceData)

    var entity: ShoppingSyncEntity {
        switch self {
        case .item: return .item
        case .place: return .place
        }
    }

    private enum CodingKeys: String, CodingKey { case title, name }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.title), !values.contains(.name) {
            self = .item(try ShoppingSyncItemData(from: decoder))
        } else if values.contains(.name), !values.contains(.title) {
            self = .place(try ShoppingSyncPlaceData(from: decoder))
        } else {
            throw ShoppingSyncStateError.invalidResponse
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .item(let item): try item.encode(to: encoder)
        case .place(let place): try place.encode(to: encoder)
        }
    }
}

/// A tombstone retains its former payload, so deleting and undoing preserve ID.
/// State stores an entity/record wrapper; network responses nest only the payload.
struct ShoppingSyncRecord: Codable, Equatable {
    var entity: ShoppingSyncEntity
    var id: UUID
    var version: Int
    var deletedAt: Int64?
    var createdAt: Int64
    var updatedAt: Int64
    var data: ShoppingSyncData

    var key: String { Self.key(entity: entity, id: id) }
    var isDeleted: Bool { deletedAt != nil }

    var item: ShoppingItem? {
        guard !isDeleted, case .item(let item) = data else { return nil }
        return ShoppingItem(id: id, title: item.title, note: item.note,
                            placeID: item.placeID,
                            createdAt: Date(timeIntervalSince1970: Double(item.createdAt) / 1_000))
    }

    var place: ShoppingPlace? {
        guard !isDeleted, case .place(let place) = data else { return nil }
        return ShoppingPlace(id: id, name: place.name, orderIndex: place.orderIndex)
    }

    static func key(entity: ShoppingSyncEntity, id: UUID) -> String {
        entity.rawValue + "/" + id.uuidString.lowercased()
    }

    private enum CodingKeys: String, CodingKey {
        case entity, record, id, version
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(entity: ShoppingSyncEntity, id: UUID, version: Int, deletedAt: Int64? = nil,
         createdAt: Int64, updatedAt: Int64, data: ShoppingSyncData) {
        self.entity = entity
        self.id = id
        self.version = version
        self.deletedAt = deletedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.data = data
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let entity = try values.decode(ShoppingSyncEntity.self, forKey: .entity)
        try self.init(payload: values.superDecoder(forKey: .record), entity: entity)
    }

    fileprivate init(payload decoder: Decoder, entity: ShoppingSyncEntity) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let data = try ShoppingSyncData(from: decoder)
        self.init(entity: entity,
                  id: try values.decode(UUID.self, forKey: .id),
                  version: try values.decode(Int.self, forKey: .version),
                  deletedAt: try values.decodeIfPresent(Int64.self, forKey: .deletedAt),
                  createdAt: try values.decode(Int64.self, forKey: .createdAt),
                  updatedAt: try values.decode(Int64.self, forKey: .updatedAt),
                  data: data)
        guard data.entity == entity, version > 0, createdAt >= 0, updatedAt >= 0,
              deletedAt.map({ $0 >= 0 }) ?? true else {
            throw ShoppingSyncStateError.invalidResponse
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(entity, forKey: .entity)
        try encodePayload(to: values.superEncoder(forKey: .record))
    }

    fileprivate func encodePayload(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id.uuidString.lowercased(), forKey: .id)
        try values.encode(version, forKey: .version)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
        if let deletedAt {
            try values.encode(deletedAt, forKey: .deletedAt)
        } else {
            try values.encodeNil(forKey: .deletedAt)
        }
        try data.encode(to: encoder)
    }
}

struct ShoppingSyncMutation: Codable, Equatable, Identifiable {
    let operationID: UUID
    let entity: ShoppingSyncEntity
    let id: UUID
    let baseVersion: Int
    let deleted: Bool
    let data: ShoppingSyncData?

    var key: String { ShoppingSyncRecord.key(entity: entity, id: id) }

    init(operationID: UUID = UUID(), entity: ShoppingSyncEntity, id: UUID,
         baseVersion: Int, deleted: Bool, data: ShoppingSyncData?) {
        self.operationID = operationID
        self.entity = entity
        self.id = id
        self.baseVersion = baseVersion
        self.deleted = deleted
        self.data = data
    }

    private enum CodingKeys: String, CodingKey {
        case entity, id, deleted, data
        case operationID = "operation_id"
        case baseVersion = "base_version"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(operationID: try values.decode(UUID.self, forKey: .operationID),
                  entity: try values.decode(ShoppingSyncEntity.self, forKey: .entity),
                  id: try values.decode(UUID.self, forKey: .id),
                  baseVersion: try values.decode(Int.self, forKey: .baseVersion),
                  deleted: try values.decode(Bool.self, forKey: .deleted),
                  data: try values.decodeIfPresent(ShoppingSyncData.self, forKey: .data))
        guard baseVersion >= 0,
              deleted ? (data == nil && baseVersion > 0) : (data?.entity == entity) else {
            throw ShoppingSyncStateError.invalidResponse
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(operationID.uuidString.lowercased(), forKey: .operationID)
        try values.encode(entity, forKey: .entity)
        try values.encode(id.uuidString.lowercased(), forKey: .id)
        try values.encode(baseVersion, forKey: .baseVersion)
        try values.encode(deleted, forKey: .deleted)
        if let data {
            try values.encode(data, forKey: .data)
        } else {
            try values.encodeNil(forKey: .data)
        }
    }
}

struct ShoppingSyncMutationResponse: Codable, Equatable {
    let record: ShoppingSyncRecord
    var entity: ShoppingSyncEntity { record.entity }

    init(record: ShoppingSyncRecord) { self.record = record }

    private enum CodingKeys: String, CodingKey { case entity, record }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        record = try ShoppingSyncRecord(payload: values.superDecoder(forKey: .record),
                                        entity: values.decode(ShoppingSyncEntity.self, forKey: .entity))
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(entity, forKey: .entity)
        try record.encodePayload(to: values.superEncoder(forKey: .record))
    }
}

struct ShoppingSyncConflictResponse: Decodable {
    let error: String
    let entity: ShoppingSyncEntity
    let record: ShoppingSyncRecord?

    private enum CodingKeys: String, CodingKey { case error, entity, record }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        error = try values.decode(String.self, forKey: .error)
        entity = try values.decode(ShoppingSyncEntity.self, forKey: .entity)
        record = try values.decodeNil(forKey: .record) ? nil
            : ShoppingSyncRecord(payload: values.superDecoder(forKey: .record), entity: entity)
    }
}

struct ShoppingSyncChange: Codable, Equatable {
    let seq: Int64
    let record: ShoppingSyncRecord
    var entity: ShoppingSyncEntity { record.entity }

    init(seq: Int64, record: ShoppingSyncRecord) {
        self.seq = seq
        self.record = record
    }

    private enum CodingKeys: String, CodingKey { case seq, entity, record }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        seq = try values.decode(Int64.self, forKey: .seq)
        record = try ShoppingSyncRecord(payload: values.superDecoder(forKey: .record),
                                        entity: values.decode(ShoppingSyncEntity.self, forKey: .entity))
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(seq, forKey: .seq)
        try values.encode(entity, forKey: .entity)
        try record.encodePayload(to: values.superEncoder(forKey: .record))
    }
}

struct ShoppingSyncPage: Codable, Equatable {
    let changes: [ShoppingSyncChange]
    let nextCursor: Int64
    let hasMore: Bool

    private enum CodingKeys: String, CodingKey {
        case changes
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

struct ShoppingSyncMergeResult {
    let items: [ShoppingItem]
    let places: [ShoppingPlace]
}

enum ShoppingSyncStateError: Error, Equatable {
    case accountMismatch, invalidResponse, invalidState, pendingMutationMissing
}

struct ShoppingSyncState: Codable, Equatable {
    let ownerID: UUID
    private(set) var cursor: Int64
    private(set) var baselines: [String: ShoppingSyncRecord]
    private(set) var deferredRemote: [String: ShoppingSyncRecord]
    private(set) var pending: [ShoppingSyncMutation]
    private(set) var attemptedOperationIDs: Set<UUID>

    init(ownerID: UUID, cursor: Int64 = 0) {
        self.ownerID = ownerID
        self.cursor = cursor
        baselines = [:]
        deferredRemote = [:]
        pending = []
        attemptedOperationIDs = []
    }

    func ensureOwner(_ accountID: UUID) throws {
        guard ownerID == accountID else { throw ShoppingSyncStateError.accountMismatch }
    }

    func validate() throws {
        guard cursor >= 0, Set(pending.map(\.operationID)).count == pending.count,
              Set(pending.map(\.key)).count == pending.count,
              attemptedOperationIDs.isSubset(of: Set(pending.map(\.operationID))),
              baselines.allSatisfy({ $0.key == $0.value.key }),
              deferredRemote.allSatisfy({ $0.key == $0.value.key }) else {
            throw ShoppingSyncStateError.invalidState
        }
    }

    /// A persisted but unsent snapshot may be replaced/cancelled. Once attempted,
    /// its exact operation ID and body must survive retries and concurrent edits.
    @discardableResult
    mutating func stageChanges(items: [ShoppingItem], places: [ShoppingPlace]) -> [ShoppingSyncMutation] {
        let current = Self.snapshot(items: items, places: places)
        pending = pending.compactMap { mutation in
            guard !attemptedOperationIDs.contains(mutation.operationID) else { return mutation }
            guard let candidate = desiredMutation(key: mutation.key, current: current) else { return nil }
            return mutation.sameWrite(as: candidate) ? mutation : candidate
        }
        let pendingKeys = Set(pending.map(\.key))
        for key in Set(current.keys).union(baselines.keys).sorted() where !pendingKeys.contains(key) {
            if let mutation = desiredMutation(key: key, current: current) {
                pending.append(mutation)
            }
        }
        pending.sort {
            let lhs = $0.priority, rhs = $1.priority
            return lhs == rhs ? $0.key < $1.key : lhs < rhs
        }
        return pending
    }

    /// Save the resulting state before making the HTTP request.
    mutating func markAttempted(_ mutation: ShoppingSyncMutation) throws {
        guard pending.contains(mutation) else { throw ShoppingSyncStateError.pendingMutationMissing }
        attemptedOperationIDs.insert(mutation.operationID)
    }

    /// This deliberately does not return a local row replacement. A user can edit
    /// or undo while HTTP is in flight; the next stage compares that newer local
    /// snapshot with the acknowledged baseline and produces the following write.
    mutating func acknowledge(_ mutation: ShoppingSyncMutation,
                              response: ShoppingSyncMutationResponse) throws {
        guard pending.contains(mutation), response.record.key == mutation.key,
              response.record.isDeleted == mutation.deleted else {
            throw ShoppingSyncStateError.invalidResponse
        }
        if response.record.version >= (baselines[mutation.key]?.version ?? 0) {
            baselines[mutation.key] = response.record
        }
        discardStaleDeferred(key: mutation.key)
        discard(mutation)
    }

    /// Keep dirty rows and their former base version. Replacing their baseline
    /// would silently rebase the next edit and lose a real concurrent conflict.
    mutating func merge(_ page: ShoppingSyncPage,
                        items: [ShoppingItem], places: [ShoppingPlace]) throws -> ShoppingSyncMergeResult {
        var previousSeq = cursor
        for change in page.changes {
            guard change.seq > previousSeq else { throw ShoppingSyncStateError.invalidResponse }
            previousSeq = change.seq
        }
        guard page.nextCursor == previousSeq, !page.hasMore || !page.changes.isEmpty else {
            throw ShoppingSyncStateError.invalidResponse
        }
        var current = Self.snapshot(items: items, places: places)
        var itemMap: [UUID: ShoppingItem] = [:]
        var placeMap: [UUID: ShoppingPlace] = [:]
        for item in items { itemMap[item.id] = item }
        for place in places { placeMap[place.id] = place }
        for change in page.changes {
            let incoming = change.record, key = incoming.key
            guard incoming.version > (baselines[key]?.version ?? 0) else { continue }
            if incoming.version > (deferredRemote[key]?.version ?? 0) {
                deferredRemote[key] = incoming
            }
        }
        let pendingKeys = Set(pending.map(\.key))
        for key in deferredRemote.keys.sorted() {
            guard let incoming = deferredRemote[key] else { continue }
            let old = baselines[key]
            guard incoming.version > (old?.version ?? 0) else {
                deferredRemote.removeValue(forKey: key)
                continue
            }
            guard !pendingKeys.contains(key) else { continue }
            let baselineData = old.flatMap { $0.isDeleted ? nil : $0.data }
            guard current[key]?.data == baselineData else { continue }
            baselines[key] = incoming
            deferredRemote.removeValue(forKey: key)
            switch incoming.entity {
            case .item:
                itemMap[incoming.id] = incoming.item
            case .place:
                placeMap[incoming.id] = incoming.place
            }
            if incoming.isDeleted {
                current.removeValue(forKey: key)
            } else {
                current[key] = Snapshot(entity: incoming.entity, id: incoming.id, data: incoming.data)
            }
        }
        cursor = page.nextCursor
        return ShoppingSyncMergeResult(
            items: itemMap.values.sorted {
                $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt
            },
            places: placeMap.values.sorted {
                $0.orderIndex == $1.orderIndex ? $0.id.uuidString < $1.id.uuidString : $0.orderIndex < $1.orderIndex
            })
    }

    /// Call only after an explicit conflict choice. Both choices accept the
    /// observed server baseline; root either applies the remote row or leaves
    /// the local row, which stageChanges submits with this new base version.
    mutating func resolveConflict(_ mutation: ShoppingSyncMutation,
                                 remoteRecord: ShoppingSyncRecord?) throws {
        guard pending.contains(mutation), remoteRecord.map({ $0.key == mutation.key }) ?? true else {
            throw ShoppingSyncStateError.invalidResponse
        }
        if let remoteRecord {
            baselines[mutation.key] = remoteRecord
            discardStaleDeferred(key: mutation.key)
        } else {
            baselines.removeValue(forKey: mutation.key)
            deferredRemote.removeValue(forKey: mutation.key)
        }
        discard(mutation)
    }

    private mutating func discard(_ mutation: ShoppingSyncMutation) {
        pending.removeAll { $0.operationID == mutation.operationID }
        attemptedOperationIDs.remove(mutation.operationID)
    }

    private mutating func discardStaleDeferred(key: String) {
        guard let deferred = deferredRemote[key],
              deferred.version <= (baselines[key]?.version ?? 0) else { return }
        deferredRemote.removeValue(forKey: key)
    }

    private func desiredMutation(key: String, current: [String: Snapshot]) -> ShoppingSyncMutation? {
        let previous = baselines[key]
        if let local = current[key] {
            guard previous?.isDeleted != false || previous?.data != local.data else { return nil }
            return ShoppingSyncMutation(entity: local.entity, id: local.id,
                                        baseVersion: previous?.version ?? 0, deleted: false, data: local.data)
        }
        guard let previous, !previous.isDeleted else { return nil }
        return ShoppingSyncMutation(entity: previous.entity, id: previous.id,
                                    baseVersion: previous.version, deleted: true, data: nil)
    }

    private struct Snapshot {
        let entity: ShoppingSyncEntity
        let id: UUID
        let data: ShoppingSyncData
        var key: String { ShoppingSyncRecord.key(entity: entity, id: id) }
    }

    private static func snapshot(items: [ShoppingItem], places: [ShoppingPlace]) -> [String: Snapshot] {
        var result: [String: Snapshot] = [:]
        for place in places {
            let snapshot = Snapshot(entity: .place, id: place.id, data: .place(ShoppingSyncPlaceData(place)))
            result[snapshot.key] = snapshot
        }
        for item in items {
            let snapshot = Snapshot(entity: .item, id: item.id, data: .item(ShoppingSyncItemData(item)))
            result[snapshot.key] = snapshot
        }
        return result
    }
}

private extension ShoppingSyncMutation {
    var priority: Int {
        if entity == .place { return deleted ? 2 : 0 }
        return 1
    }

    func sameWrite(as other: Self) -> Bool {
        entity == other.entity && id == other.id && baseVersion == other.baseVersion
            && deleted == other.deleted && data == other.data
    }
}
#endif
