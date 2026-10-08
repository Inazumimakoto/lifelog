import SwiftUI

struct ShoppingItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var shoppingStore: ShoppingStore
    @FocusState private var isTitleFocused: Bool
    @State private var title: String
    @State private var note: String
    @State private var placeID: UUID?
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    private let originalItem: ShoppingItem

    init(shoppingStore: ShoppingStore, item: ShoppingItem) {
        self.shoppingStore = shoppingStore
        originalItem = item
        _title = State(initialValue: item.title)
        _note = State(initialValue: item.note)
        _placeID = State(initialValue: item.placeID)
    }

    var body: some View {
        Form {
            Section {
                TextField("商品名", text: $title)
                    .focused($isTitleFocused)
                TextField("メモ（任意）", text: $note, axis: .vertical)
                    .lineLimit(3...8)
            }
            Section {
                Picker("購入先", selection: $placeID) {
                    Text("未指定").tag(Optional<UUID>.none)
                    ForEach(shoppingStore.places) { place in
                        Text(verbatim: place.name).tag(Optional(place.id))
                    }
                }
                .pickerStyle(.menu)
            }
            Section {
                Button("削除", role: .destructive) { showDeleteConfirmation = true }
            }
        }
        .navigationTitle("商品を編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .confirmationDialog("商品を削除しますか？",
                            isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("削除", role: .destructive, action: delete)
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("この商品をリストから削除します。")
        }
        .alert("保存できませんでした", isPresented: errorPresentation) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
        .onChange(of: shoppingStore.places.map(\.id)) { _, ids in
            if let placeID, !ids.contains(placeID) { self.placeID = nil }
        }
    }

    private func save() {
        // Preserve current purchase state and stored quantity while editing visible fields.
        var item = shoppingStore.items.first { $0.id == originalItem.id } ?? originalItem
        item.title = title
        item.note = note
        item.placeID = placeID
        do {
            try shoppingStore.updateItem(item)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        do {
            try shoppingStore.deleteItem(originalItem.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorPresentation: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
