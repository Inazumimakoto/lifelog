//
//  Utilities.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import SwiftUI
import WidgetKit

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

    static let compactDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = JapaneseLocaleProvider.locale
        formatter.dateFormat = "yyyy/MM/dd"
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

    /// 12月5日(火) 形式
    var jaMonthDayWeekdayString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日(EEE)"
        return formatter.string(from: self)
    }

    /// 2024年 形式
    var jaYearString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年"
        return formatter.string(from: self)
    }

    func memoPadDisplayString(relativeTo reference: Date = Date()) -> String {
        if Calendar.current.isDate(self, inSameDayAs: reference) {
            return DateFormatter.japaneseTime.string(from: self)
        }
        return DateFormatter.memoPadDateTime.string(from: self)
    }

    /// YYYY/MM/DD(曜日) 形式
    var compactDateString: String {
        let dateStr = DateFormatter.compactDate.string(from: self)
        let weekday = DateFormatter.japaneseWeekdayNarrow.string(from: self)
        return "\(dateStr)(\(weekday))"
    }

    /// 12/07(日) 形式
    var slashMonthDayWeekdayString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "MM/dd"
        let dateStr = formatter.string(from: self)
        let weekday = DateFormatter.japaneseWeekdayNarrow.string(from: self)
        return "\(dateStr)(\(weekday))"
    }

    /// 年のみ: 2024
    var yearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: self)
    }

    /// MM/DD(曜日) 形式
    var monthDayWeekdayString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "MM/dd"
        let dateStr = formatter.string(from: self)
        let weekday = DateFormatter.japaneseWeekdayNarrow.string(from: self)
        return "\(dateStr)(\(weekday))"
    }
}

extension Date: Identifiable {
    public var id: TimeInterval { timeIntervalSince1970 }
}

enum ReminderDisplay {
    static func eventReminderDate(for event: CalendarEvent) -> Date? {
        if let minutes = event.reminderMinutes, minutes > 0 {
            return event.startDate.addingTimeInterval(-Double(minutes * 60))
        }

        if let reminderDate = event.reminderDate {
            return reminderDate
        }

        guard NotificationSettingsManager.shared.isEventCategoryNotificationEnabled else {
            return nil
        }

        let setting = NotificationSettingsManager.shared.getSetting(for: event.calendarName)
            ?? CategoryNotificationSetting(categoryName: event.calendarName)
        guard setting.enabled else { return nil }

        if setting.useRelativeTime {
            return event.startDate.addingTimeInterval(-Double(setting.minutesBefore * 60))
        }

        return Calendar.current.date(
            bySettingHour: setting.hour,
            minute: setting.minute,
            second: 0,
            of: event.startDate
        ) ?? event.startDate
    }

    static func eventReminderLabel(for event: CalendarEvent) -> String? {
        guard let reminderDate = eventReminderDate(for: event) else { return nil }
        return reminderTimeLabel(for: reminderDate, referenceDate: event.startDate)
    }

    static func taskReminderLabel(for task: Task) -> String? {
        guard let reminderDate = task.reminderDate else { return nil }
        let referenceDate = task.startDate ?? task.endDate ?? reminderDate
        return reminderTimeLabel(for: reminderDate, referenceDate: referenceDate)
    }

    private static func reminderTimeLabel(for reminderDate: Date, referenceDate: Date) -> String {
        if Calendar.current.isDate(reminderDate, inSameDayAs: referenceDate) {
            return reminderDate.formattedTime()
        }
        return DateFormatter.memoPadDateTime.string(from: reminderDate)
    }
}

extension Collection where Element == HabitRecord {
    func record(for habit: Habit, on date: Date) -> HabitRecord? {
        first { $0.habitID == habit.id && Calendar.current.isDate($0.date, inSameDayAs: date) }
    }
}

extension Color {
    static func from(cgColor: CGColor?) -> Color? {
        guard let cgColor else { return nil }
        return Color(cgColor)
    }
}

extension CGColor {
    var hexString: String? {
        guard let comps = converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil)?.components,
              comps.count >= 3 else { return nil }
        let r = Int(round(comps[0] * 255))
        let g = Int(round(comps[1] * 255))
        let b = Int(round(comps[2] * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

enum AppColorPalette {
    static let defaultHex = "#F97316"

    // Ordered by hue for predictable scanning in swatch grids.
    static let presets: [String] = [
        "#EF4444", "#F97316", "#F59E0B", "#EAB308",
        "#84CC16", "#22C55E", "#10B981", "#14B8A6",
        "#06B6D4", "#0EA5E9", "#3B82F6", "#6366F1",
        "#8B5CF6", "#A855F7", "#D946EF", "#EC4899",
        "#F43F5E", "#A16207", "#78716C", "#94A3B8"
    ]

    static func color(for token: String) -> Color {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if let color = Color(hex: trimmed) {
            return color
        }

        switch trimmed.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "mint": return .mint
        case "teal": return .teal
        case "cyan": return .cyan
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "brown": return .brown
        case "gray", "grey": return .gray
        default: return .accentColor
        }
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
    private static let sharedDefaults = UserDefaults(suiteName: PersistenceController.appGroupIdentifier)

    private static let defaultCategories: [String: String] = [
        "仕事": "orange", "趣味": "green", "旅行": "blue"
    ]

    static let colorChoices: [String] = AppColorPalette.presets

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
        if let token = allCategoriesMapping()[key] {
            return AppColorPalette.color(for: token)
        }
        return .accentColor
    }

    static func allCategories() -> [CustomCategory] {
        allCategoriesMapping()
            .map { CustomCategory(name: $0.key, colorName: $0.value) }
            .sorted(by: { $0.name < $1.name })
    }
    
    static func allCategoryNames() -> [String] {
        allCategories().map { $0.name }
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
        if let data = sharedDefaults?.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            return decoded
        }

        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            sharedDefaults?.set(data, forKey: storageKey)
            return decoded
        }

        return defaultCategories
    }

    private static func persist(map: [String: String]) {
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: storageKey)
            sharedDefaults?.set(data, forKey: storageKey)
            WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
        }
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var defaultCategoryName: String {
        allCategories().first?.name ?? "仕事"
    }

}
