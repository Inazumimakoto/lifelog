import Foundation

/// Shared category mutations for Settings and event/category selection.
/// docs/requirements.md §Settings: category names, colors, and existing events
/// stay consistent whichever screen starts an edit.
@MainActor
final class CalendarCategoryService {
    enum ValidationError: LocalizedError, Equatable {
        case emptyName
        case duplicateName

        var messageKey: String {
            switch self {
            case .emptyName:
                return "calendar.category.validation.emptyName"
            case .duplicateName:
                return "calendar.category.validation.duplicateName"
            }
        }

        var errorDescription: String? {
            String(localized: String.LocalizationValue(messageKey))
        }
    }

    private let store: AppDataStore

    // Match AppDataStore's workaround for Swift's implicit isolated-deinit
    // back-deployment crash on iOS 26.1; this service has no teardown work.
    nonisolated deinit {}

    init(store: AppDataStore) {
        self.store = store
    }

    @discardableResult
    func add(name: String, colorToken: String) throws -> String {
        let normalizedName = try validatedName(name)
        CategoryPalette.saveCategory(name: normalizedName, colorName: colorToken)
        return normalizedName
    }

    @discardableResult
    func update(originalName: String, name: String, colorToken: String) throws -> String {
        let normalizedName = try validatedName(name, excluding: originalName)
        CategoryPalette.renameCategory(oldName: originalName, newName: normalizedName, colorName: colorToken)
        store.renameCalendarCategory(from: originalName, to: normalizedName)
        CategoryPalette.notifyCategoryReplacement(from: originalName, to: normalizedName)
        return normalizedName
    }

    func replacementCategory(forDeleting name: String) -> String {
        CategoryPalette.allCategories().first { $0.name != name }?.name ?? "仕事"
    }

    @discardableResult
    func delete(name: String) -> String {
        let replacement = replacementCategory(forDeleting: name)
        CategoryPalette.deleteCategory(name)
        if CategoryPalette.allCategories().isEmpty {
            CategoryPalette.saveCategory(name: replacement, colorName: AppColorPalette.defaultHex)
        }
        // Keep events, shared calendar links, and category notification settings
        // together. These synchronous writes finish before the next UI render.
        store.renameCalendarCategory(from: name, to: replacement)
        CategoryPalette.notifyCategoryReplacement(from: name, to: replacement)
        return replacement
    }

    private func validatedName(_ name: String, excluding originalName: String? = nil) throws -> String {
        let normalizedName = normalized(name)
        guard normalizedName.isEmpty == false else { throw ValidationError.emptyName }
        let normalizedOriginal = originalName.map(normalized)
        let duplicatesExistingCategory = CategoryPalette.allCategoryNames().contains { existingName in
            let normalizedExisting = normalized(existingName)
            return normalizedExisting == normalizedName && normalizedExisting != normalizedOriginal
        }
        guard duplicatesExistingCategory == false else { throw ValidationError.duplicateName }
        return normalizedName
    }

    private func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
