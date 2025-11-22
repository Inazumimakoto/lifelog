//
//  Utilities.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import SwiftUI

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if hexSanitized.count == 3 {
            for (index, char) in hexSanitized.enumerated() {
                hexSanitized.insert(char, at: hexSanitized.index(hexSanitized.startIndex, offsetBy: index * 2))
            }
        }

        guard let int = UInt64(hexSanitized, radix: 16) else { return nil }
        let r, g, b: Double
        switch hexSanitized.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            return nil
        }
        self.init(red: r, green: g, blue: b)
    }
}

private enum JapaneseLocaleProvider {
    static let locale = Locale(identifier: "ja_JP")
}

extension DateFormatter {
    static let japaneseMonthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = JapaneseLocaleProvider.locale
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    static let japaneseYearMonthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = JapaneseLocaleProvider.locale
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    static let japaneseWeekdayWide: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = JapaneseLocaleProvider.locale
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    static let japaneseWeekdayNarrow: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = JapaneseLocaleProvider.locale
        formatter.dateFormat = "EEEEE"
        return formatter
    }()

    static let japaneseTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = JapaneseLocaleProvider.locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static let memoPadDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = JapaneseLocaleProvider.locale
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()
}

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    func formatted(_ style: DateFormatter.Style = .medium) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = style
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }

    func formattedTime() -> String {
        DateFormatter.japaneseTime.string(from: self)
    }

    var jaMonthDayString: String {
        DateFormatter.japaneseMonthDay.string(from: self)
    }

    var jaYearMonthDayString: String {
        DateFormatter.japaneseYearMonthDay.string(from: self)
    }

    var jaWeekdayWideString: String {
        DateFormatter.japaneseWeekdayWide.string(from: self)
    }

    var jaWeekdayNarrowString: String {
        DateFormatter.japaneseWeekdayNarrow.string(from: self)
    }

    var jaWeekdayString: String {
        jaWeekdayNarrowString
    }

    func memoPadDisplayString(relativeTo reference: Date = Date()) -> String {
        if Calendar.current.isDate(self, inSameDayAs: reference) {
            return DateFormatter.japaneseTime.string(from: self)
        }
        return DateFormatter.memoPadDateTime.string(from: self)
    }
}

extension Collection where Element == HabitRecord {
    func record(for habit: Habit, on date: Date) -> HabitRecord? {
        first { $0.habitID == habit.id && Calendar.current.isDate($0.date, inSameDayAs: date) }
    }
}

enum CategoryPalette {
    struct CustomCategory: Codable, Hashable, Identifiable {
        var name: String
        var colorName: String

        var id: String { name }
    }

    private static let storageKey = "CategoryPalette_Categories_V3"
    private static let defaults = UserDefaults.standard

    private static let defaultCategories: [String: String] = [
        "仕事": "orange", "趣味": "green", "旅行": "blue"
    ]

    static let colorChoices: [String] = [
        "#F97316", "#F43F5E", "#EC4899", "#8B5CF6",
        "#3B82F6", "#0EA5E9", "#10B981", "#22C55E",
        "#84CC16", "#EAB308", "#EF4444", "#94A3B8"
    ]

    static func initializeIfNeeded() {
        var currentCategories = allCategoriesMapping()
        var madeChanges = false
        for (name, color) in defaultCategories {
            if currentCategories[name] == nil {
                currentCategories[name] = color
                madeChanges = true
            }
        }
        
        if madeChanges {
            persist(map: currentCategories)
        }
    }

    static func color(for name: String) -> Color {
        let key = normalized(name)
        if let colorHex = allCategoriesMapping()[key],
           let color = Color(hex: colorHex) {
            return color
        }
        return .accentColor
    }

    static func allCategories() -> [CustomCategory] {
        allCategoriesMapping()
            .map { CustomCategory(name: $0.key, colorName: $0.value) }
            .sorted(by: { $0.name < $1.name })
    }

    static func saveCategory(name: String, colorName: String) {
        var map = allCategoriesMapping()
        map[name] = colorName
        persist(map: map)
    }

    static func deleteCategory(_ name: String) {
        var map = allCategoriesMapping()
        map.removeValue(forKey: name)
        persist(map: map)
    }

    static func renameCategory(oldName: String, newName: String, colorName: String) {
        var map = allCategoriesMapping()
        if oldName != newName {
            map.removeValue(forKey: oldName)
        }
        map[newName] = colorName
        persist(map: map)
    }

    private static func allCategoriesMapping() -> [String: String] {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            return decoded
        }
        return defaultCategories
    }

    private static func persist(map: [String: String]) {
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
