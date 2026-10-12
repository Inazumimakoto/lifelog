#if DEBUG
import Combine
import Foundation

enum ShoppingSyncError: LocalizedError {
    case accountMismatch, invalidState, invalidContent

    var errorDescription: String? {
        switch self {
        case .accountMismatch: return String(localized: "shopping.sync.account_mismatch")
        case .invalidState: return String(localized: "shopping.sync.error")
        case .invalidContent: return String(localized: "shopping.sync.invalid_content")
        }
    }
}

struct ShoppingSyncConflictFailure: Error {
    let response: ShoppingSyncConflictResponse
}

@MainActor
protocol ShoppingSyncTransport: AnyObject {
    var accountID: String? { get }
    func restoreSession() async
    func shoppingChanges(after cursor: Int64, ownerID: UUID) async throws -> ShoppingSyncPage
    func sendShoppingMutation(_ mutation: ShoppingSyncMutation, ownerID: UUID) async throws -> ShoppingSyncMutationResponse
}

extension ShoppingConnectionService: ShoppingSyncTransport {}

/// Foreground synchronization for the opt-in prototype. Local edits remain immediately saved.
/// Cursor and outbox are saved with SwiftData; request attempts retain their operation ID on retry.
@MainActor
final class ShoppingSyncService: ObservableObject {
    struct Conflict: Identifiable {
        let mutation: ShoppingSyncMutation
        let response: ShoppingSyncConflictResponse
        var id: UUID { mutation.operationID }
    }

    @Published private(set) var isSyncing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var conflict: Conflict?

    let store: ShoppingStore
    private let transport: any ShoppingSyncTransport
    private let isUnlocked: @MainActor () -> Bool
    private var subscriptions = Set<AnyCancellable>()
    private var scheduled: _Concurrency.Task<Void, Never>?

    var isEnabled: Bool { store.syncState != nil }

    init(store: ShoppingStore, transport: any ShoppingSyncTransport = ShoppingConnectionService.shared,
         isUnlocked: @escaping @MainActor () -> Bool = {
             !AppLockService.shared.isAppLockEnabled || AppLockService.shared.isUnlocked
         }) {
        self.store = store
        self.transport = transport
        self.isUnlocked = isUnlocked
        store.$items.dropFirst().sink { [weak self] _ in self?.schedule() }.store(in: &subscriptions)
        store.$places.dropFirst().sink { [weak self] _ in self?.schedule() }.store(in: &subscriptions)
        store.$syncState.dropFirst().sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
    }

    nonisolated deinit {}

    /// The UI explains the initial upload before calling this method.
    func enable() async {
        do {
            guard let account = transport.accountID.flatMap(UUID.init(uuidString:)) else {
                throw ShoppingConnectionService.ConnectionError.signInRequired
            }
            guard isUnlocked() else { throw ShoppingConnectionService.ConnectionError.locked }
            try store.enableSync(ownerID: account)
            await synchronize()
        } catch { errorMessage = message(for: error) }
    }

    func resume() {
        guard isEnabled else { return }
        schedule(immediately: true)
    }

    private func schedule(immediately: Bool = false) {
        guard isEnabled, !isSyncing, conflict == nil else { return }
        scheduled?.cancel()
        scheduled = _Concurrency.Task { @MainActor [weak self] in
            if !immediately {
                do { try await _Concurrency.Task.sleep(for: .milliseconds(700)) }
                catch { return }
            }
            guard !_Concurrency.Task.isCancelled else { return }
            await self?.synchronize()
        }
    }

    func synchronize() async {
        guard !isSyncing, conflict == nil, let initial = store.syncState else { return }
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }
        do {
            await transport.restoreSession()
            let owner = initial.ownerID
            try verify(owner)
            while true {
                var state = try currentState(owner)
                state.stageChanges(items: store.items, places: store.places)
                try store.saveSyncState(state)
                while let mutation = state.pending.first {
                    try verify(owner)
                    try validateContent(mutation)
                    try state.markAttempted(mutation)
                    try store.saveSyncState(state)
                    let response: ShoppingSyncMutationResponse
                    do {
                        response = try await transport.sendShoppingMutation(mutation, ownerID: owner)
                    } catch let failure as ShoppingSyncConflictFailure {
                        try verify(owner)
                        guard failure.response.entity == mutation.entity,
                              failure.response.record.map({ $0.id == mutation.id }) ?? true else {
                            throw ShoppingSyncError.invalidState
                        }
                        conflict = Conflict(mutation: mutation, response: failure.response)
                        return
                    }
                    try verify(owner)
                    state = try currentState(owner)
                    try state.acknowledge(mutation, response: response)
                    // Do not replace the local value: it may have changed or been undone during await.
                    state.stageChanges(items: store.items, places: store.places)
                    try store.saveSyncState(state)
                }
                var hasMore = true
                while hasMore {
                    try verify(owner)
                    let page = try await transport.shoppingChanges(after: state.cursor, ownerID: owner)
                    try verify(owner)
                    state = try currentState(owner)
                    let merged = try state.merge(page, items: store.items, places: store.places)
                    try store.saveSyncState(state, items: merged.items, places: merged.places)
                    hasMore = page.hasMore
                }
                state.stageChanges(items: store.items, places: store.places)
                try store.saveSyncState(state)
                if state.pending.isEmpty { break }
                // Local changes made during pull are sent before the next pull, with their original base.
            }
            lastSyncedAt = Date()
        } catch {
            // A lost response leaves the attempted operation intact for a later safe retry.
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled {
                errorMessage = message(for: error)
            }
        }
    }

    /// Both choices use the observed server version. A further concurrent change will conflict again.
    func resolveConflict(keepLocal: Bool) async {
        guard let conflict, let current = store.syncState else { return }
        do {
            try verify(current.ownerID)
            var next = current
            try next.resolveConflict(conflict.mutation, remoteRecord: conflict.response.record)
            if keepLocal {
                try store.saveSyncState(next)
            } else {
                var items = store.items
                var places = store.places
                switch conflict.mutation.entity {
                case .item:
                    items.removeAll { $0.id == conflict.mutation.id }
                    if let item = conflict.response.record?.item { items.append(item) }
                case .place:
                    places.removeAll { $0.id == conflict.mutation.id }
                    if let place = conflict.response.record?.place { places.append(place) }
                    else {
                        for index in items.indices where items[index].placeID == conflict.mutation.id {
                            items[index].placeID = nil
                        }
                    }
                }
                try store.saveSyncState(next, items: items, places: places)
            }
            self.conflict = nil
            await synchronize()
        } catch { errorMessage = message(for: error) }
    }

    /// A missing place is a selection problem, not permission to discard a new local item.
    func resolveUnavailablePlace() async {
        guard let conflict, conflict.response.error == "place_unavailable",
              conflict.mutation.entity == .item, var next = store.syncState else { return }
        do {
            try verify(next.ownerID)
            try next.resolveConflict(conflict.mutation, remoteRecord: conflict.response.record)
            var items = store.items
            for index in items.indices where items[index].id == conflict.mutation.id { items[index].placeID = nil }
            try store.saveSyncState(next, items: items)
            self.conflict = nil
            await synchronize()
        } catch { errorMessage = message(for: error) }
    }

    private func currentState(_ owner: UUID) throws -> ShoppingSyncState {
        guard let state = store.syncState else { throw ShoppingSyncError.invalidState }
        try state.ensureOwner(owner)
        try state.validate()
        return state
    }

    private func validateContent(_ mutation: ShoppingSyncMutation) throws {
        guard let data = mutation.data else { return }
        func validName(_ value: String) -> Bool {
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !value.contains("\u{0000}") && value.utf16.count <= 200
        }
        switch data {
        case .item(let item):
            guard validName(item.title), item.note.utf16.count <= 4_000,
                  (0...9_007_199_254_740_991).contains(item.createdAt) else { throw ShoppingSyncError.invalidContent }
        case .place(let place):
            guard validName(place.name), (0...9_007_199_254_740_991).contains(place.orderIndex) else {
                throw ShoppingSyncError.invalidContent
            }
        }
    }

    private func verify(_ owner: UUID) throws {
        guard isUnlocked() else { throw ShoppingConnectionService.ConnectionError.locked }
        guard transport.accountID.flatMap(UUID.init(uuidString:)) == owner,
              store.syncState?.ownerID == owner else { throw ShoppingSyncError.accountMismatch }
        try _Concurrency.Task.checkCancellation()
    }

    private func message(for error: Error) -> String {
        if let error = error as? ShoppingSyncError { return error.localizedDescription }
        if let error = error as? ShoppingStoreError { return error.localizedDescription }
        if let error = error as? ShoppingConnectionService.ConnectionError { return error.localizedDescription }
        return String(localized: "shopping.sync.error")
    }
}
#endif
