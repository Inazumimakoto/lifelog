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
}

extension Collection where Element == HabitRecord {
    func record(for habit: Habit, on date: Date) -> HabitRecord? {
        first { $0.habitID == habit.id && Calendar.current.isDate($0.date, inSameDayAs: date) }
    }
}
