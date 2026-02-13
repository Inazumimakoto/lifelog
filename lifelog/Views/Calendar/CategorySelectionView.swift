//
//  CategorySelectionView.swift
//  lifelog
//
//  Created by InumakiMakoto on 2025/11/21.
//

import SwiftUI

struct CategorySelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCategory: String
    var noneLabel: String?
    
    @State private var allCategories: [CategoryPalette.CustomCategory]
    @State private var newCategoryName: String = ""
    @State private var newCategoryColor: String = CategoryPalette.colorChoices.first ?? AppColorPalette.defaultHex
    @State private var editingCategory: CategoryPalette.CustomCategory?
    @State private var editingCategoryName: String = ""
    @State private var editingCategoryColor: String = CategoryPalette.colorChoices.first ?? AppColorPalette.defaultHex
    @State private var isShowingAddCategory = false

    init(selectedCategory: Binding<String>, noneLabel: String? = nil) {
        self._selectedCategory = selectedCategory
        self.noneLabel = noneLabel
        self._allCategories = State(initialValue: CategoryPalette.allCategories())
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("カテゴリは左にスワイプすると編集・削除ができます。\n新しいカテゴリは右上の「＋」ボタンから追加してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                List {
                    if let noneLabel {
                        Button(action: {
                            selectedCategory = ""
                            dismiss()
                        }) {
                            HStack {
                                Circle()
                                    .stroke(Color.secondary, lineWidth: 1)
                                    .frame(width: 20, height: 20)
                                Text(noneLabel)
                                Spacer()
                                if selectedCategory.isEmpty {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                    ForEach(allCategories, id: \.name) { category in
                        Button(action: {
                            selectedCategory = category.name
                            dismiss()
                        }) {
                            HStack {
                                Circle()
                                    .fill(CategoryPalette.color(for: category.name))
                                    .frame(width: 20, height: 20)
                                Text(category.name)
                                Spacer()
                                if selectedCategory == category.name {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .swipeActions {
                            Button("削除", role: .destructive) {
                                deleteCategory(name: category.name)
                            }
                            Button("編集") {
                                startEditing(category: category)
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
            .navigationTitle("カテゴリを選択")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { isShowingAddCategory.toggle() }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingAddCategory) {
                categoryCreatorSheet
            }
            .sheet(item: $editingCategory) { category in
                categoryEditorSheet(for: category)
            }
        }
    }
    
    private var categoryCreatorSheet: some View {
        NavigationStack {
            Form {
                Section("新しいカテゴリ") {
                    TextField("カテゴリ名", text: $newCategoryName)
                    colorSwatchGrid(selection: $newCategoryColor)
                    ColorPicker("自由に色を選ぶ", selection: colorPickerSelection(for: $newCategoryColor), supportsOpacity: false)
                }
            }
            .navigationTitle("カテゴリを追加")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { isShowingAddCategory = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        addCategory()
                        isShowingAddCategory = false
                    }
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func categoryEditorSheet(for category: CategoryPalette.CustomCategory) -> some View {
        NavigationStack {
            Form {
                Section("カテゴリを編集") {
                    TextField("カテゴリ名", text: $editingCategoryName)
                        .onAppear {
                            editingCategoryName = category.name
                            editingCategoryColor = category.colorName
                        }
                    colorSwatchGrid(selection: $editingCategoryColor)
                    ColorPicker("自由に色を選ぶ", selection: colorPickerSelection(for: $editingCategoryColor), supportsOpacity: false)
                }
            }
            .navigationTitle("カテゴリを編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { editingCategory = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        applyEditing()
                    }
                    .disabled(editingCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func colorSwatchGrid(selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                ForEach(CategoryPalette.colorChoices, id: \.self) { hex in
                    Circle()
                        .fill(AppColorPalette.color(for: hex))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .stroke(
                                    isSameColorToken(selection.wrappedValue, hex) ? Color.primary : Color.clear,
                                    lineWidth: 2
                                )
                        )
                        .onTapGesture {
                            selection.wrappedValue = hex
                        }
                }
            }
            .padding(.vertical)
            Text(selection.wrappedValue)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private func addCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        CategoryPalette.saveCategory(name: trimmed, colorName: newCategoryColor)
        refreshCategories()
        newCategoryName = ""
    }

    private func deleteCategory(name: String) {
        CategoryPalette.deleteCategory(name)
        refreshCategories()
        if selectedCategory == name {
            selectedCategory = allCategories.first?.name ?? "その他"
        }
    }

    private func startEditing(category: CategoryPalette.CustomCategory) {
        editingCategory = category
    }
    
    private func applyEditing() {
        guard let original = editingCategory else { return }
        let trimmed = editingCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        CategoryPalette.renameCategory(oldName: original.name, newName: trimmed, colorName: editingCategoryColor)
        refreshCategories()
        if selectedCategory == original.name {
            selectedCategory = trimmed
        }
        editingCategory = nil
    }

    private func refreshCategories() {
        allCategories = CategoryPalette.allCategories()
    }

    private func colorPickerSelection(for selection: Binding<String>) -> Binding<Color> {
        Binding(
            get: { AppColorPalette.color(for: selection.wrappedValue) },
            set: { selected in
                if let hex = selected.cgColor?.hexString {
                    selection.wrappedValue = hex
                }
            }
        )
    }

    private func isSameColorToken(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}
