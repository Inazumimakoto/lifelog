import SwiftUI
import UIKit

/// A buying list with a separate sheet for uninterrupted, repeated item entry.
/// See docs/ui-guidelines.md: Shopping list.
struct ShoppingListView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("shoppingShowsUnassignedPlace") private var showsUnassignedPlace = true
    @StateObject private var viewModel: ShoppingListViewModel
    @State private var sheet: SheetDestination?
    @State private var deletingItem: ShoppingItem?
    @State private var checkFeedback = 0
    @State private var additionButtonHeight: CGFloat = 64

    private enum SheetDestination: Identifiable {
        case item(ShoppingItem)
        case places
        case addItems(UUID?)

        var id: String {
            switch self {
            case .item(let item): return "item-\(item.id.uuidString)"
            case .places: return "places"
            case .addItems: return "add-items"
            }
        }
    }

    init(store: AppDataStore) {
        self.init(shoppingStore: store.shoppingStore)
    }

    init(shoppingStore: ShoppingStore) {
        _viewModel = StateObject(wrappedValue: ShoppingListViewModel(shoppingStore: shoppingStore))
    }

    var body: some View {
        VStack(spacing: 0) {
            placeFilters
            List {
                if let loadError = viewModel.loadError {
                    Section {
                        Text(verbatim: loadError)
                            .foregroundStyle(.secondary)
                        Button("再読み込み") { viewModel.reload() }
                    }
                }
                if viewModel.loadError == nil {
                    if viewModel.pendingGroups.isEmpty {
                        Section("買うもの") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("買うものはまだありません")
                                    .font(.headline)
                                Text("「商品を追加」から追加できます")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 16)
                        }
                    } else {
                        ForEach(viewModel.pendingGroups) { group in
                            Section {
                                ForEach(group.items) { item in
                                    itemRow(item)
                                }
                            } header: {
                                Text(verbatim: group.title)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("買い物リスト")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            additionButton
        }
        .overlay(alignment: .bottom) {
            purchaseUndoBanner
        }
        .animation(purchaseAnimation, value: viewModel.purchaseUndo?.id)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("購入先を管理", systemImage: "building.2") {
                        present(.places)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(Text("商品の操作"))
            }
        }
        .sheet(item: $sheet) { destination in
            NavigationStack {
                switch destination {
                case .item(let item):
                    ShoppingItemEditorView(shoppingStore: viewModel.shoppingStore, item: item)
                case .places:
                    ShoppingPlacesView(shoppingStore: viewModel.shoppingStore)
                case .addItems(let initialPlaceID):
                    ShoppingAddItemsView(shoppingStore: viewModel.shoppingStore,
                                         initialPlaceID: initialPlaceID,
                                         onSelectedPlaceChanged: viewModel.rememberAdditionPlace)
                }
            }
        }
        .confirmationDialog("商品を削除しますか？",
                            isPresented: deleteConfirmation,
                            titleVisibility: .visible,
                            presenting: deletingItem) { item in
            Button("削除", role: .destructive) {
                viewModel.delete(item)
                deletingItem = nil
            }
            Button("キャンセル", role: .cancel) { deletingItem = nil }
        } message: { _ in
            Text("この商品をリストから削除します。")
        }
        .alert("買い物リスト", isPresented: errorPresentation) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(verbatim: viewModel.errorMessage ?? "")
        }
        .sensoryFeedback(.success, trigger: checkFeedback)
        .onAppear(perform: selectVisiblePurchasePlaceIfNeeded)
        .onChange(of: showsUnassignedPlace) { _, _ in
            selectVisiblePurchasePlaceIfNeeded()
        }
        .onChange(of: viewModel.places.map(\.id)) { _, _ in
            selectVisiblePurchasePlaceIfNeeded()
        }
        .onDisappear {
            viewModel.finishPurchaseInteractions()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { viewModel.finishPurchaseInteractions() }
        }
        .onChange(of: viewModel.purchaseUndo?.id) { _, token in
            if token != nil, let undo = viewModel.purchaseUndo {
                UIAccessibility.post(notification: .announcement,
                                     argument: purchaseMessage(for: undo.title))
            }
        }
    }

    private var placeFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterButton(String(localized: "すべて"), filter: .all)
                ForEach(viewModel.places) { place in
                    filterButton(place.name, filter: .place(place.id))
                }
                if showsUnassignedPlace {
                    filterButton(String(localized: "未指定"), filter: .unassigned)
                        .contextMenu {
                            Button("非表示", systemImage: "eye.slash") {
                                showsUnassignedPlace = false
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .accessibilityLabel(Text("購入先で絞り込む"))
    }

    private func filterButton(_ title: String, filter: ShoppingListViewModel.PlaceFilter) -> some View {
        Button { viewModel.selectFilter(filter) } label: {
            Text(verbatim: title)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(viewModel.filter == filter ? Color.accentColor : .secondary)
        .accessibilityAddTraits(viewModel.filter == filter ? .isSelected : [])
    }

    private var additionButton: some View {
        HStack {
            Spacer()
            Button("商品を追加", systemImage: "plus") {
                present(.addItems(viewModel.draftPlaceID))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(viewModel.loadError != nil)
            .accessibilityIdentifier("shopping.openAddition")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: ShoppingAdditionButtonHeightKey.self,
                                       value: proxy.size.height)
            }
        }
        .onPreferenceChange(ShoppingAdditionButtonHeightKey.self) { height in
            additionButtonHeight = height
        }
    }

    @ViewBuilder
    private var purchaseUndoBanner: some View {
        if let undo = viewModel.purchaseUndo {
            HStack(spacing: 12) {
                Text(verbatim: purchaseMessage(for: undo.title))
                    .font(.subheadline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    withAnimation(purchaseAnimation) {
                        if viewModel.undoPurchase(undo.id) { checkFeedback += 1 }
                    }
                } label: {
                    Text("元に戻す")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("shopping.undoPurchase")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            .padding(.horizontal, 16)
            .padding(.bottom, additionButtonHeight + 8)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain)
        }
    }

    private var purchaseAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)
    }

    private func purchaseMessage(for title: String) -> String {
        String.localizedStringWithFormat(String(localized: "shopping.purchase.completed"), title)
    }

    private func selectVisiblePurchasePlaceIfNeeded() {
        guard !showsUnassignedPlace else { return }
        if viewModel.filter == .unassigned {
            viewModel.selectFilter(.all)
        }
        if viewModel.draftPlaceID == nil, let place = viewModel.places.first {
            viewModel.rememberAdditionPlace(place.id)
        }
    }

    private func itemRow(_ item: ShoppingItem) -> some View {
        ShoppingItemRow(item: item,
                        isChecked: viewModel.isChecking(item.id),
                        placeName: viewModel.places.first { $0.id == item.placeID }?.name,
                        onToggle: {
            if viewModel.isChecking(item.id) {
                withAnimation(purchaseAnimation) {
                    if viewModel.togglePurchase(item) { checkFeedback += 1 }
                }
            } else if viewModel.togglePurchase(item) {
                checkFeedback += 1
            }
        }, onEdit: {
            guard !viewModel.isChecking(item.id) else { return }
            present(.item(item))
        }, onDelete: {
            guard !viewModel.isChecking(item.id) else { return }
            deletingItem = item
        })
    }

    private func present(_ destination: SheetDestination) {
        viewModel.finishPurchaseInteractions()
        sheet = destination
    }

    private var deleteConfirmation: Binding<Bool> {
        Binding(get: { deletingItem != nil }, set: { if !$0 { deletingItem = nil } })
    }

    private var errorPresentation: Binding<Bool> {
        Binding(get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } })
    }
}

private struct ShoppingAdditionButtonHeightKey: PreferenceKey {
    nonisolated static let defaultValue: CGFloat = 0

    nonisolated static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview("買い物リスト") {
    NavigationStack {
        ShoppingListView(shoppingStore: ShoppingStore(container: PersistenceController(inMemory: true).container))
    }
}
