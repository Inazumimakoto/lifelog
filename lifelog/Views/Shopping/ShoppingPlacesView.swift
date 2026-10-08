import SwiftUI

struct ShoppingPlacesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var shoppingStore: ShoppingStore
    @AppStorage("shoppingShowsUnassignedPlace") private var showsUnassignedPlace = true
    @State private var sheet: SheetDestination?
    @State private var deletingPlace: ShoppingPlace?
    @State private var errorMessage: String?

    private enum SheetDestination: Identifiable {
        case newPlace
        case edit(ShoppingPlace)

        var id: String {
            switch self {
            case .newPlace: return "new-place"
            case .edit(let place): return place.id.uuidString
            }
        }
    }

    init(shoppingStore: ShoppingStore) {
        self.shoppingStore = shoppingStore
    }

    var body: some View {
        List {
            if shoppingStore.places.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("購入先はまだありません")
                            .font(.headline)
                        Text("購入先を追加すると、商品をお店ごとに整理できます")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 16)
                }
            } else {
                Section("購入先") {
                    ForEach(shoppingStore.places) { place in
                        HStack {
                            Button { sheet = .edit(place) } label: {
                                Text(verbatim: place.name)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Menu {
                                Button("購入先を編集", systemImage: "pencil") { sheet = .edit(place) }
                                Button("削除", systemImage: "trash", role: .destructive) { deletingPlace = place }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel(Text("購入先の操作"))
                        }
                    }
                    .onMove(perform: movePlaces)
                }
            }
            Section {
                Toggle("未指定を表示", isOn: $showsUnassignedPlace)
            } footer: {
                Text("非表示にしても商品は削除されません。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("購入先を管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !shoppingStore.places.isEmpty { EditButton() }
                Button { sheet = .newPlace } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("購入先を追加"))
            }
        }
        .sheet(item: $sheet) { destination in
            NavigationStack {
                switch destination {
                case .newPlace:
                    ShoppingPlaceEditorView(shoppingStore: shoppingStore)
                case .edit(let place):
                    ShoppingPlaceEditorView(shoppingStore: shoppingStore, place: place)
                }
            }
        }
        .confirmationDialog("購入先を削除しますか？",
                            isPresented: deleteConfirmation,
                            titleVisibility: .visible,
                            presenting: deletingPlace) { place in
            Button("削除", role: .destructive) { delete(place) }
            Button("キャンセル", role: .cancel) { deletingPlace = nil }
        } message: { _ in
            Text("この購入先の商品は「未指定」に移動します。商品は削除されません。")
        }
        .alert("保存できませんでした", isPresented: errorPresentation) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
    }

    private func movePlaces(fromOffsets: IndexSet, toOffset: Int) {
        do {
            try shoppingStore.movePlaces(fromOffsets: fromOffsets, toOffset: toOffset)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ place: ShoppingPlace) {
        do {
            try shoppingStore.deletePlace(place.id)
            deletingPlace = nil
        } catch {
            deletingPlace = nil
            errorMessage = error.localizedDescription
        }
    }

    private var deleteConfirmation: Binding<Bool> {
        Binding(get: { deletingPlace != nil }, set: { if !$0 { deletingPlace = nil } })
    }

    private var errorPresentation: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
