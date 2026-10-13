import SwiftUI

/// Selection stays lightweight; editing uses the same screen as Settings.
struct CategorySelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore
    @ObservedObject private var paletteObserver = CategoryPaletteObserver.shared
    @Binding var selectedCategory: String
    var noneLabel: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let noneLabel {
                        Button {
                            selectedCategory = ""
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .stroke(.secondary, lineWidth: 1)
                                    .frame(width: 20, height: 20)
                                Text(verbatim: noneLabel)
                                Spacer()
                                selectionIndicator(isSelected: selectedCategory.isEmpty)
                            }
                            .frame(minHeight: 32)
                            .contentShape(Rectangle())
                        }
                        .foregroundStyle(.primary)
                    }
                    ForEach(CategoryPalette.allCategories()) { category in
                        Button {
                            selectedCategory = category.name
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(CategoryPalette.color(for: category.name))
                                    .frame(width: 20, height: 20)
                                Text(verbatim: CategoryPalette.displayName(for: category.name))
                                Spacer()
                                selectionIndicator(isSelected: selectedCategory == category.name)
                            }
                            .frame(minHeight: 32)
                            .contentShape(Rectangle())
                        }
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(selectedCategory == category.name ? .isSelected : [])
                    }
                }
                Section {
                    NavigationLink {
                        CalendarCategoryManagementView(store: store)
                    } label: {
                        Label("calendar.categories.manage", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .navigationTitle("カテゴリを選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func selectionIndicator(isSelected: Bool) -> some View {
        if isSelected {
            Image(systemName: "checkmark")
                .foregroundStyle(Color.accentColor)
        }
    }
}
