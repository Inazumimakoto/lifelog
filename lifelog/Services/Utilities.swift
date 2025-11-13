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
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

extension Collection where Element == HabitRecord {
    func record(for habit: Habit, on date: Date) -> HabitRecord? {
        first { $0.habitID == habit.id && Calendar.current.isDate($0.date, inSameDayAs: date) }
    }
}

