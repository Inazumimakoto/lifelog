import SwiftUI

struct ShoppingPlaceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var shoppingStore: ShoppingStore
    @FocusState private var isNameFocused: Bool
    @State private var name: String
    @State private var errorMessage: String?
    private let place: ShoppingPlace?
    private let onSaved: ((ShoppingPlace) -> Void)?

    init(shoppingStore: ShoppingStore,
         place: ShoppingPlace? = nil,
         onSaved: ((ShoppingPlace) -> Void)? = nil) {
        self.shoppingStore = shoppingStore
        self.place = place
        self.onSaved = onSaved
        _name = State(initialValue: place?.name ?? "")
    }

    var body: some View {
        Form {
            TextField("購入先の名前", text: $name)
                .focused($isNameFocused)
                .submitLabel(.done)
                .onSubmit(save)
        }
        .navigationTitle(place == nil ? String(localized: "購入先を追加") : String(localized: "購入先を編集"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .alert("保存できませんでした", isPresented: errorPresentation) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
        .onAppear { isNameFocused = true }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            if let place {
                try shoppingStore.renamePlace(place.id, name: name)
                if let updated = shoppingStore.places.first(where: { $0.id == place.id }) {
                    onSaved?(updated)
                }
            } else {
                let place = try shoppingStore.addPlace(name: name)
                onSaved?(place)
            }
            dismiss()
        } catch {
            // Retain the name field for validation errors and failed saves alike.
            errorMessage = error.localizedDescription
        }
    }

    private var errorPresentation: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
