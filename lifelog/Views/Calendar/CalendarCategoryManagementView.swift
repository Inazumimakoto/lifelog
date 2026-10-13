import SwiftUI

/// docs/requirements.md §4.9: one category manager for Settings and pickers.
struct CalendarCategoryManagementView: View {
    @ObservedObject var store: AppDataStore
    @ObservedObject private var paletteObserver = CategoryPaletteObserver.shared
    @State private var editor: EditorDestination?

    var body: some View {
        List {
            Section {
                ForEach(CategoryPalette.allCategories()) { category in
                    Button {
                        editor = .edit(category)
                    } label: {
                        HStack(spacing: 14) {
                            Circle()
                                .fill(CategoryPalette.color(for: category.name))
                                .frame(width: 24, height: 24)
                            Text(verbatim: CategoryPalette.displayName(for: category.name))
                            Spacer()
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                    .accessibilityHint(Text("calendar.categories.editHint"))
                }
            } footer: {
                Text("calendar.categories.description")
            }

            Section {
                Button {
                    editor = .new
                } label: {
                    Label("カテゴリを追加", systemImage: "plus")
                }
            }
        }
        .navigationTitle("calendar.categories.title")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editor) { destination in
            CalendarCategoryEditorView(store: store, category: destination.category)
        }
    }

    private enum EditorDestination: Identifiable {
        case new
        case edit(CategoryPalette.CustomCategory)

        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let category): return "edit:\(category.name)"
            }
        }

        var category: CategoryPalette.CustomCategory? {
            if case .edit(let category) = self { return category }
            return nil
        }
    }
}
