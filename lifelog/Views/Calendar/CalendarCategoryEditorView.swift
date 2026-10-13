import SwiftUI

struct CalendarCategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let store: AppDataStore
    let category: CategoryPalette.CustomCategory?
    private let initialDisplayName: String
    @State private var name: String
    @State private var colorToken: String
    @State private var validationError: CalendarCategoryService.ValidationError?
    @State private var showDeleteConfirmation = false

    init(store: AppDataStore, category: CategoryPalette.CustomCategory?) {
        self.store = store
        self.category = category
        let initialName = category.map { CategoryPalette.displayName(for: $0.name) } ?? ""
        initialDisplayName = initialName
        _name = State(initialValue: initialName)
        _colorToken = State(initialValue: category?.colorName ?? AppColorPalette.defaultHex)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameToSave: String {
        // Display localized built-in names in the field, while retaining their
        // stored key when only the color changes. User-entered names stay raw.
        if let category, trimmedName == initialDisplayName { return category.name }
        return trimmedName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("カテゴリ名") {
                    TextField("カテゴリ名", text: $name)
                        .textInputAutocapitalization(.none)
                        .autocorrectionDisabled()
                        .onChange(of: name) { _, _ in validationError = nil }
                    if let validationError {
                        Text(LocalizedStringKey(validationError.messageKey))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    colorSwatches
                    ColorPicker("自由に色を選ぶ", selection: colorSelection, supportsOpacity: false)
                } header: {
                    Text("calendar.categories.color")
                } footer: {
                    Text("calendar.categories.colorHint")
                }

                if category != nil {
                    Section {
                        Button("calendar.categories.delete", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(category == nil ? LocalizedStringKey("カテゴリを追加") : LocalizedStringKey("カテゴリを編集"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(category == nil ? LocalizedStringKey("追加") : LocalizedStringKey("保存")) { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .confirmationDialog("calendar.categories.delete", isPresented: $showDeleteConfirmation,
                                titleVisibility: .visible) {
                Button("削除", role: .destructive) { delete() }
                Button("キャンセル", role: .cancel) { }
            } message: {
                if let category {
                    let replacement = CalendarCategoryService(store: store)
                        .replacementCategory(forDeleting: category.name)
                    Text("calendar.categories.deleteMessage \(CategoryPalette.displayName(for: category.name)) \(CategoryPalette.displayName(for: replacement))")
                }
            }
        }
    }

    private var colorSwatches: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
            ForEach(CategoryPalette.colorChoices, id: \.self) { token in
                let selected = AppColorPalette.color(for: colorToken) == AppColorPalette.color(for: token)
                Button {
                    colorToken = token
                } label: {
                    Circle()
                        .fill(AppColorPalette.color(for: token))
                        .frame(width: 30, height: 30)
                        .overlay {
                            if selected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.4), radius: 1)
                            }
                        }
                        .padding(4)
                        .overlay {
                            Circle().stroke(selected ? Color.primary : .clear, lineWidth: 2)
                        }
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("calendar.category.color \(token)"))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private var colorSelection: Binding<Color> {
        Binding(
            get: { AppColorPalette.color(for: colorToken) },
            set: { color in
                if let hex = color.cgColor?.hexString { colorToken = hex }
            }
        )
    }

    private func save() {
        let service = CalendarCategoryService(store: store)
        do {
            if let category {
                try service.update(originalName: category.name, name: nameToSave, colorToken: colorToken)
            } else {
                try service.add(name: nameToSave, colorToken: colorToken)
            }
            dismiss()
        } catch let error as CalendarCategoryService.ValidationError {
            validationError = error
        } catch {
            assertionFailure("Unexpected category validation error: \(error)")
        }
    }

    private func delete() {
        guard let category else { return }
        CalendarCategoryService(store: store).delete(name: category.name)
        dismiss()
    }
}
