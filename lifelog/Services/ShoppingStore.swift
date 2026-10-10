import Foundation
import Combine
import SwiftData
import SwiftUI
import os

/// Offline, immediately saved shopping data. See docs/requirements.md: 買い物リスト.
/// A dedicated context keeps rollback isolated from diary and calendar edits.
@MainActor
final class ShoppingStore: ObservableObject {
    @Published private(set) var items: [ShoppingItem] = []
    @Published private(set) var places: [ShoppingPlace] = []
    @Published private(set) var loadError: String?

    private let context: ModelContext
    private let saveOperation: (ModelContext) throws -> Void
    private var hasLoadedData = false

    init(container: ModelContainer,
         saveOperation: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        context = ModelContext(container)
        context.autosaveEnabled = false
        self.saveOperation = saveOperation
        // reload() records load or legacy-cleanup failures and disables writes until a successful retry.
        try? reload()
    }

    // Avoid the implicit isolated-deinit crash on older Swift runtimes.
    // https://github.com/swiftlang/swift/issues/87316
    nonisolated deinit {}

    func reload() throws {
        do {
            var state = try fetchState()
            let legacyPurchases = state.items.filter { $0.purchasedAt != nil }
            if !legacyPurchases.isEmpty {
                state.items.removeAll { $0.purchasedAt != nil }
                for item in legacyPurchases {
                    context.delete(item)
                }
                try saveOperation(context)
            }
            publish(state)
            hasLoadedData = true
            loadError = nil
        } catch {
            context.rollback()
            hasLoadedData = false
            loadError = String(localized: "shopping.error.load_failed")
            AppLogger.data.error("Shopping data load failed: \(error)")
            throw ShoppingStoreError.unavailable
        }
    }

    @discardableResult
    func addItem(title: String,
                 quantity: String = "",
                 note: String = "",
                 placeID: UUID? = nil) throws -> ShoppingItem {
        let title = try validatedTitle(title)
        return try mutate { state in
            try self.validatePlace(placeID, in: state)
            let item = ShoppingItem(title: title,
                                    quantity: quantity,
                                    note: note,
                                    placeID: placeID)
            let stored = SDShoppingItem(domain: item)
            self.context.insert(stored)
            state.items.append(stored)
            return item
        }
    }

    func updateItem(_ item: ShoppingItem) throws {
        var item = item
        item.title = try validatedTitle(item.title)
        try mutate { state in
            guard let stored = state.items.first(where: { $0.id == item.id }) else {
                throw ShoppingStoreError.itemNotFound
            }
            try self.validatePlace(item.placeID, in: state)
            // A draft cannot change the item's original ordering.
            var updated = item
            updated.createdAt = stored.createdAt
            stored.update(from: updated)
        }
    }

    /// Undo recreates the original item without replacing a newer row with the same identity.
    func restoreItem(_ item: ShoppingItem) throws {
        try mutate { state in
            guard !state.items.contains(where: { $0.id == item.id }) else { return }
            var restored = item
            if let placeID = restored.placeID,
               !state.places.contains(where: { $0.id == placeID }) {
                restored.placeID = nil
            }
            let stored = SDShoppingItem(domain: restored)
            self.context.insert(stored)
            state.items.append(stored)
        }
    }

    func deleteItem(_ id: UUID) throws {
        try mutate { state in
            guard let index = state.items.firstIndex(where: { $0.id == id }) else {
                throw ShoppingStoreError.itemNotFound
            }
            self.context.delete(state.items.remove(at: index))
        }
    }

    @discardableResult
    func addPlace(name: String) throws -> ShoppingPlace {
        try mutate { state in
            let name = try self.validatedPlaceName(name, in: state)
            let orderIndex = (state.places.map(\.orderIndex).max() ?? -1) + 1
            let place = ShoppingPlace(name: name, orderIndex: orderIndex)
            let stored = SDShoppingPlace(id: place.id, name: name, orderIndex: orderIndex)
            self.context.insert(stored)
            state.places.append(stored)
            return place
        }
    }

    func renamePlace(_ id: UUID, name: String) throws {
        try mutate { state in
            guard let stored = state.places.first(where: { $0.id == id }) else {
                throw ShoppingStoreError.placeNotFound
            }
            stored.name = try self.validatedPlaceName(name, excluding: id, in: state)
        }
    }

    func movePlaces(fromOffsets offsets: IndexSet, toOffset destination: Int) throws {
        try mutate { state in
            guard offsets.allSatisfy({ state.places.indices.contains($0) }),
                  (0...state.places.count).contains(destination) else {
                throw ShoppingStoreError.placeNotFound
            }
            state.places.move(fromOffsets: offsets, toOffset: destination)
            for (index, place) in state.places.enumerated() {
                place.orderIndex = index
            }
        }
    }

    func deletePlace(_ id: UUID) throws {
        try mutate { state in
            guard let index = state.places.firstIndex(where: { $0.id == id }) else {
                throw ShoppingStoreError.placeNotFound
            }
            // Removing a place never removes its items.
            for item in state.items where item.placeID == id {
                item.placeID = nil
            }
            self.context.delete(state.places.remove(at: index))
            for (index, place) in state.places.enumerated() {
                place.orderIndex = index
            }
        }
    }

    private struct StoredState {
        var items: [SDShoppingItem]
        var places: [SDShoppingPlace]
    }

    private func fetchState() throws -> StoredState {
        let state = StoredState(
            items: try context.fetch(FetchDescriptor<SDShoppingItem>(
                sortBy: [SortDescriptor(\.createdAt)])),
            places: try context.fetch(FetchDescriptor<SDShoppingPlace>(
                sortBy: [SortDescriptor(\.orderIndex)]))
        )
        return StoredState(items: state.items, places: state.places.sorted {
            if $0.orderIndex == $1.orderIndex { return $0.id.uuidString < $1.id.uuidString }
            return $0.orderIndex < $1.orderIndex
        })
    }

    private func mutate<Result>(_ operation: (inout StoredState) throws -> Result) throws -> Result {
        guard hasLoadedData else { throw ShoppingStoreError.unavailable }
        var state: StoredState
        do {
            state = try fetchState()
        } catch {
            hasLoadedData = false
            loadError = String(localized: "shopping.error.load_failed")
            AppLogger.data.error("Shopping data fetch failed: \(error)")
            throw ShoppingStoreError.unavailable
        }
        do {
            let result = try operation(&state)
            try saveOperation(context)
            // Value-type snapshots remain unchanged if the save above fails.
            publish(state)
            return result
        } catch {
            context.rollback()
            AppLogger.data.error("Shopping data save failed: \(error)")
            throw (error as? ShoppingStoreError) ?? ShoppingStoreError.saveFailed
        }
    }

    private func publish(_ state: StoredState) {
        items = state.items.map { ShoppingItem(sd: $0) }.sorted {
            if $0.createdAt == $1.createdAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.createdAt < $1.createdAt
        }
        places = state.places.map { ShoppingPlace(sd: $0) }.sorted {
            if $0.orderIndex == $1.orderIndex { return $0.id.uuidString < $1.id.uuidString }
            return $0.orderIndex < $1.orderIndex
        }
    }

    private func validatedTitle(_ title: String) throws -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ShoppingStoreError.emptyItem }
        return name
    }

    private func validatePlace(_ id: UUID?, in state: StoredState) throws {
        guard let id else { return }
        guard state.places.contains(where: { $0.id == id }) else {
            throw ShoppingStoreError.placeNotFound
        }
    }

    private func validatedPlaceName(_ name: String,
                                    excluding id: UUID? = nil,
                                    in state: StoredState) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ShoppingStoreError.emptyPlace }
        guard !state.places.contains(where: {
            $0.id != id && $0.name.compare(name, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame
        }) else { throw ShoppingStoreError.duplicatePlace }
        return name
    }
}

enum ShoppingStoreError: LocalizedError {
    case emptyItem
    case emptyPlace
    case duplicatePlace
    case itemNotFound
    case placeNotFound
    case unavailable
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .emptyItem: String(localized: "shopping.error.empty_item")
        case .emptyPlace: String(localized: "shopping.error.empty_place")
        case .duplicatePlace: String(localized: "shopping.error.duplicate_place")
        case .itemNotFound: String(localized: "shopping.error.item_not_found")
        case .placeNotFound: String(localized: "shopping.error.place_not_found")
        case .unavailable: String(localized: "shopping.error.unavailable")
        case .saveFailed: String(localized: "shopping.error.save_failed")
        }
    }
}
