import Foundation
import Combine

/// Tracks only the items added while this add screen is open.
/// See docs/requirements.md: Shopping list and docs/ui-guidelines.md: Shopping.
@MainActor
final class ShoppingAddItemsViewModel: ObservableObject {
    @Published var titleDraft = ""
    @Published var noteDraft = ""
    @Published var errorMessage: String?
    @Published private(set) var selectedPlaceID: UUID?
    @Published private(set) var sessionItemIDs: [UUID] = []
    @Published private(set) var items: [ShoppingItem] = []
    @Published private(set) var places: [ShoppingPlace] = []
    @Published private(set) var loadError: String?

    let shoppingStore: ShoppingStore
    private var showsUnassigned = true
    private var cancellables = Set<AnyCancellable>()

    init(shoppingStore: ShoppingStore, initialPlaceID: UUID? = nil) {
        self.shoppingStore = shoppingStore
        selectedPlaceID = initialPlaceID
        items = shoppingStore.items
        places = shoppingStore.places
        loadError = shoppingStore.loadError
        normalizeSelectedPlace(showsUnassigned: true)
        bind()
    }

    // No actor-isolated cleanup is needed; avoid Swift's implicit-deinit runtime bug.
    // https://github.com/swiftlang/swift/issues/87316
    nonisolated deinit {}

    var canAdd: Bool {
        loadError == nil && !titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var addedItems: [ShoppingItem] {
        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return sessionItemIDs.compactMap { itemsByID[$0] }
    }

    var addedCount: Int { addedItems.count }

    func selectPlace(_ id: UUID?) {
        selectedPlaceID = id
        normalizeSelectedPlace(showsUnassigned: showsUnassigned)
    }

    func normalizeSelectedPlace(showsUnassigned: Bool) {
        self.showsUnassigned = showsUnassigned
        if let id = selectedPlaceID, !places.contains(where: { $0.id == id }) {
            selectedPlaceID = nil
        }
        if selectedPlaceID == nil && !showsUnassigned {
            selectedPlaceID = places.first?.id
        }
    }

    @discardableResult
    func addDraft() -> Bool {
        guard canAdd else { return false }
        do {
            let item = try shoppingStore.addItem(title: titleDraft,
                                                note: noteDraft,
                                                placeID: selectedPlaceID)
            sessionItemIDs.append(item.id)
            titleDraft = ""
            noteDraft = ""
            errorMessage = nil
            return true
        } catch {
            // Keep both draft fields and the place so a failed offline save can be retried.
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func undoAddition(_ id: UUID) -> Bool {
        guard sessionItemIDs.contains(id) else { return false }
        do {
            try shoppingStore.deleteItem(id)
            sessionItemIDs.removeAll { $0 == id }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func reload() {
        do {
            try shoppingStore.reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func bind() {
        shoppingStore.$items
            .sink { [weak self] items in
                guard let self else { return }
                self.items = items
                let availableIDs = Set(items.map(\.id))
                self.sessionItemIDs.removeAll { !availableIDs.contains($0) }
            }
            .store(in: &cancellables)

        shoppingStore.$places
            .sink { [weak self] places in
                guard let self else { return }
                self.places = places
                self.normalizeSelectedPlace(showsUnassigned: self.showsUnassigned)
            }
            .store(in: &cancellables)

        shoppingStore.$loadError
            .sink { [weak self] in self?.loadError = $0 }
            .store(in: &cancellables)
    }
}
