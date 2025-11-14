//
//  Models.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import SwiftUI

// MARK: - Enumerations

enum TaskPriority: Int, Codable, CaseIterable, Identifiable {
    case low = 1
    case medium = 2
    case high = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }

    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

enum HabitSchedule: Codable, Identifiable, Hashable {
    case daily
    case weekdays
    case custom(days: [Weekday])

    var id: String {
        switch self {
        case .daily: return "daily"
        case .weekdays: return "weekdays"
        case .custom(let days): return "custom-\(days.map { String($0.rawValue) }.joined(separator: "-"))"
        }
    }

    func isActive(on date: Date) -> Bool {
        switch self {
        case .daily:
            return true
        case .weekdays:
            return Calendar.current.isDateInWeekend(date) == false
        case .custom(let days):
            let weekday = Weekday(date: date)
            return days.contains(weekday)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case days
    }

    private enum ScheduleType: String, Codable {
        case daily, weekdays, custom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ScheduleType.self, forKey: .type)
        switch type {
        case .daily:
            self = .daily
        case .weekdays:
            self = .weekdays
        case .custom:
            let days = try container.decode([Weekday].self, forKey: .days)
            self = .custom(days: days)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .daily:
            try container.encode(ScheduleType.daily, forKey: .type)
        case .weekdays:
            try container.encode(ScheduleType.weekdays, forKey: .type)
        case .custom(let days):
            try container.encode(ScheduleType.custom, forKey: .type)
            try container.encode(days, forKey: .days)
        }
    }
}

enum AnniversaryType: String, Codable, CaseIterable, Identifiable {
    case countdown
    case since

    var id: String { rawValue }
}

enum MoodLevel: Int, Codable, CaseIterable, Identifiable {
    case veryLow = 1
    case low = 2
    case neutral = 3
    case high = 4
    case veryHigh = 5

    var id: Int { rawValue }

    var emoji: String {
        switch self {
        case .veryLow: return "😢"
        case .low: return "🙁"
        case .neutral: return "😐"
        case .high: return "🙂"
        case .veryHigh: return "😄"
        }
    }
}

enum Weekday: Int, CaseIterable, Identifiable, Codable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    init(date: Date) {
        let weekday = Calendar.current.component(.weekday, from: date)
        self = Weekday(rawValue: weekday) ?? .monday
    }

    var id: Int { rawValue }

    var shortLabel: String {
        switch self {
        case .sunday: return "日"
        case .monday: return "月"
        case .tuesday: return "火"
        case .wednesday: return "水"
        case .thursday: return "木"
        case .friday: return "金"
        case .saturday: return "土"
        }
    }
}

// MARK: - Core Models

struct Task: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var detail: String
    var startDate: Date?
    var endDate: Date?
    var priority: TaskPriority
    var isCompleted: Bool

    init(id: UUID = UUID(),
         title: String,
         detail: String = "",
         startDate: Date? = nil,
         endDate: Date? = nil,
         priority: TaskPriority = .medium,
         isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.detail = detail
        self.startDate = startDate
        self.endDate = endDate
        self.priority = priority
        self.isCompleted = isCompleted
    }
}

struct DiaryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var date: Date
    var text: String
    var mood: MoodLevel?
    var conditionScore: Int?
    var locationName: String?
    var latitude: Double?
    var longitude: Double?
    var photoPaths: [String]

    init(id: UUID = UUID(),
         date: Date,
         text: String,
         mood: MoodLevel? = nil,
         conditionScore: Int? = nil,
         locationName: String? = nil,
         latitude: Double? = nil,
         longitude: Double? = nil,
         photoPaths: [String] = []) {
        self.id = id
        self.date = date
        self.text = text
        self.mood = mood
        self.conditionScore = conditionScore
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.photoPaths = photoPaths
    }
}

struct Habit: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var iconName: String
    var colorHex: String
    var schedule: HabitSchedule

    init(id: UUID = UUID(),
         title: String,
         iconName: String,
         colorHex: String,
         schedule: HabitSchedule) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.colorHex = colorHex
        self.schedule = schedule
    }
}

struct HabitRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var habitID: UUID
    var date: Date
    var isCompleted: Bool

    init(id: UUID = UUID(),
         habitID: UUID,
         date: Date,
         isCompleted: Bool) {
        self.id = id
        self.habitID = habitID
        self.date = date
        self.isCompleted = isCompleted
    }
}

struct Anniversary: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var targetDate: Date
    var type: AnniversaryType
    var repeatsYearly: Bool

    init(id: UUID = UUID(),
         title: String,
         targetDate: Date,
         type: AnniversaryType,
         repeatsYearly: Bool) {
        self.id = id
        self.title = title
        self.targetDate = targetDate
        self.type = type
        self.repeatsYearly = repeatsYearly
    }

    func daysRelative(to date: Date) -> Int {
        let calendar = Calendar.current
        let reference = repeatsYearly
            ? calendar.nextDate(after: date, matching: calendar.dateComponents([.month, .day], from: targetDate), matchingPolicy: .nextTimePreservingSmallerComponents) ?? targetDate
            : targetDate
        let startOfToday = calendar.startOfDay(for: date)
        let startOfTarget = calendar.startOfDay(for: reference)
        guard let days = calendar.dateComponents([.day], from: startOfToday, to: startOfTarget).day else {
            return 0
        }
        return days
    }
}

struct HealthSummary: Identifiable, Hashable {
    let id = UUID()
    var date: Date
    var steps: Int?
    var sleepHours: Double?
    var activeEnergy: Double?
    var moveMinutes: Double?
    var exerciseMinutes: Double?
    var standHours: Double?
    var sleepStart: Date?
    var sleepEnd: Date?
}

struct CalendarEvent: Identifiable, Hashable {
    let id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var calendarName: String

    init(id: UUID = UUID(),
         title: String,
         startDate: Date,
         endDate: Date,
         calendarName: String) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.calendarName = calendarName
    }
}
