import SwiftUI

/// Adds several products in one keyboard session without returning to the shopping list.
/// See docs/ui-guidelines.md: Shopping list.
struct ShoppingAddItemsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("shoppingShowsUnassignedPlace") private var showsUnassignedPlace = true
    @StateObject private var viewModel: ShoppingAddItemsViewModel
    @State private var isAddingPlace = false
    @State private var focusRequest = 0
    @State private var memoFocusRequest = 0
    @State private var isMemoExpanded = false
    @State private var closesMemoAfterFocus = false

    private let shoppingStore: ShoppingStore
    private let onSelectedPlaceChanged: (UUID?) -> Void

    init(shoppingStore: ShoppingStore,
         initialPlaceID: UUID? = nil,
         onSelectedPlaceChanged: @escaping (UUID?) -> Void = { _ in }) {
        self.shoppingStore = shoppingStore
        self.onSelectedPlaceChanged = onSelectedPlaceChanged
        _viewModel = StateObject(wrappedValue: ShoppingAddItemsViewModel(
            shoppingStore: shoppingStore,
            initialPlaceID: initialPlaceID
        ))
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if let loadError = viewModel.loadError {
                    Section {
                        Text(verbatim: loadError)
                            .foregroundStyle(.secondary)
                        Button("再読み込み") { viewModel.reload() }
                    }
                } else {
                    Section {
                        if viewModel.addedItems.isEmpty {
                            Text("追加した商品はここに表示されます")
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(viewModel.addedItems) { item in
                                addedItemRow(item)
                                    .id(item.id)
                            }
                        }
                    } header: {
                        Text("今回追加した商品（\(viewModel.addedCount)）")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.never)
            .onChange(of: viewModel.addedItems.map(\.id)) { oldIDs, newIDs in
                guard newIDs.count > oldIDs.count, let id = newIDs.last else { return }
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
        .navigationTitle("商品を追加")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") {
                    onSelectedPlaceChanged(viewModel.selectedPlaceID)
                    dismiss()
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
        .sheet(isPresented: $isAddingPlace, onDismiss: requestInputFocus) {
            NavigationStack {
                ShoppingPlaceEditorView(shoppingStore: shoppingStore) { place in
                    viewModel.selectPlace(place.id)
                }
            }
        }
        .alert("商品を追加", isPresented: errorPresentation) {
            Button("OK", role: .cancel, action: dismissError)
        } message: {
            Text(verbatim: viewModel.errorMessage ?? "")
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(
            !viewModel.titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !viewModel.noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        .onAppear(perform: normalizeSelectedPlace)
        .onChange(of: showsUnassignedPlace) { _, _ in
            normalizeSelectedPlace()
        }
        .onChange(of: viewModel.places.map(\.id)) { _, _ in
            normalizeSelectedPlace()
        }
        .onChange(of: viewModel.selectedPlaceID) { _, id in
            onSelectedPlaceChanged(id)
        }
        .onChange(of: viewModel.loadError) { _, error in
            if error == nil { requestInputFocus() }
        }
    }

    private var composer: some View {
        VStack(spacing: 4) {
            purchasePlaceChoices
            HStack(spacing: 8) {
                ShoppingItemNameField(text: $viewModel.titleDraft,
                                      isEnabled: viewModel.loadError == nil,
                                      focusRequest: focusRequest,
                                      onSubmit: addItem,
                                      onFocusConfirmed: closeMemoAfterFocus)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                    .accessibilityIdentifier("shopping.titleDraft")
                if !dynamicTypeSize.isAccessibilitySize {
                    memoButton
                }
                Button(action: addItem) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 18, minHeight: 18)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .controlSize(.regular)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .disabled(!viewModel.canAdd)
                .accessibilityLabel(Text("追加"))
                .accessibilityIdentifier("shopping.add")
            }
            .padding(.horizontal, 16)
            if dynamicTypeSize.isAccessibilitySize {
                HStack {
                    memoButton
                    Spacer()
                }
                .padding(.horizontal, 16)
            }
            if isMemoExpanded {
                ShoppingItemMemoField(text: $viewModel.noteDraft,
                                      isEnabled: viewModel.loadError == nil,
                                      focusRequest: memoFocusRequest)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 16)
                    .disabled(viewModel.loadError != nil)
                    .accessibilityIdentifier("shopping.noteDraft")
            }
        }
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var memoButton: some View {
        Button {
            isMemoExpanded = true
            memoFocusRequest += 1
        } label: {
            Label("shopping.add.memo", systemImage: viewModel.noteDraft.isEmpty ? "plus" : "pencil")
                .font(.subheadline)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .tint(isMemoExpanded ? Color.accentColor : .secondary)
        .disabled(viewModel.loadError != nil)
        .accessibilityIdentifier("shopping.openMemo")
    }

    private var purchasePlaceChoices: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if showsUnassignedPlace {
                        purchasePlaceButton(String(localized: "未指定"), id: nil)
                            .id("unassigned")
                            .contextMenu {
                                Button("非表示", systemImage: "eye.slash") {
                                    showsUnassignedPlace = false
                                }
                            }
                    }
                    ForEach(viewModel.places) { place in
                        purchasePlaceButton(place.name, id: place.id)
                            .id(place.id.uuidString)
                    }
                    Button { isAddingPlace = true } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.regular)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .tint(.secondary)
                    .accessibilityLabel(Text("購入先を追加"))
                }
                .padding(.horizontal, 16)
            }
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                proxy.scrollTo(selectedPlaceScrollID, anchor: .center)
            }
            .onChange(of: viewModel.selectedPlaceID) { _, _ in
                proxy.scrollTo(selectedPlaceScrollID, anchor: .center)
            }
            .accessibilityLabel(Text("購入先"))
        }
        .disabled(viewModel.loadError != nil)
    }

    private var selectedPlaceScrollID: String {
        viewModel.selectedPlaceID?.uuidString ?? "unassigned"
    }

    private func purchasePlaceButton(_ title: String, id: UUID?) -> some View {
        let isSelected = viewModel.selectedPlaceID == id
        return Button { viewModel.selectPlace(id) } label: {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                }
                Text(verbatim: title)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .tint(isSelected ? Color.accentColor : .secondary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func addedItemRow(_ item: ShoppingItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: item.title)
                    .font(.body)
                Text(verbatim: viewModel.places.first { $0.id == item.placeID }?.name
                     ?? String(localized: "未指定"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !item.note.isEmpty {
                    Text(verbatim: item.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            Button("取り消す") {
                _ = viewModel.undoAddition(item.id)
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
        }
    }

    private func addItem() {
        if viewModel.addDraft() {
            closesMemoAfterFocus = isMemoExpanded
            HapticManager.success()
        }
        requestInputFocus()
    }

    private func closeMemoAfterFocus() {
        guard closesMemoAfterFocus else { return }
        // Transfer focus before removing the memo field so the keyboard stays open.
        closesMemoAfterFocus = false
        guard viewModel.noteDraft.isEmpty else { return }
        isMemoExpanded = false
    }

    private func normalizeSelectedPlace() {
        viewModel.normalizeSelectedPlace(showsUnassigned: showsUnassignedPlace)
    }

    private func requestInputFocus() {
        focusRequest += 1
    }

    private func dismissError() {
        guard viewModel.errorMessage != nil else { return }
        viewModel.errorMessage = nil
        requestInputFocus()
    }

    private var errorPresentation: Binding<Bool> {
        Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { dismissError() } })
    }
}
