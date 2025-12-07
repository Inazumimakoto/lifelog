//
//  Models.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import SwiftUI
import EventKit

// MARK: - Enumerations

enum TaskPriority: Int, Codable, CaseIterable, Identifiable, Comparable {
    case high = 3
    case medium = 2
    case low = 1

    var id: Int { rawValue }

    static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

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

struct CalendarCategoryLink: Identifiable, Codable, Equatable {
    /// EventKit の EKCalendar.calendarIdentifier
    let calendarIdentifier: String
    /// 表示用タイトル
    var calendarTitle: String
    /// 対応させる lifelog カテゴリ名（nilなら取り込まない）
    var categoryId: String?
    /// iOSカレンダーの色 (hex)
    var colorHex: String?

    var id: String { calendarIdentifier }
}

struct MemoPad: Codable, Hashable {
    var text: String
    var lastUpdatedAt: Date?

    init(text: String = "", lastUpdatedAt: Date? = nil) {
        self.text = text
        self.lastUpdatedAt = lastUpdatedAt
    }
}

struct Task: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var detail: String
    var startDate: Date?
    var endDate: Date?
    var priority: TaskPriority
    var isCompleted: Bool
    var reminderDate: Date?

    init(id: UUID = UUID(),
         title: String,
         detail: String = "",
         startDate: Date? = nil,
         endDate: Date? = nil,
         priority: TaskPriority = .medium,
         isCompleted: Bool = false,
         reminderDate: Date? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.startDate = startDate
        self.endDate = endDate
        self.priority = priority
        self.isCompleted = isCompleted
        self.reminderDate = reminderDate
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
    // Will be used later to surface a day's favorite shot in the calendar/album view.
    var favoritePhotoPath: String?

    init(id: UUID = UUID(),
         date: Date,
         text: String,
         mood: MoodLevel? = .neutral,
         conditionScore: Int? = 3,
         locationName: String? = nil,
         latitude: Double? = nil,
         longitude: Double? = nil,
         photoPaths: [String] = [],
         favoritePhotoPath: String? = nil) {
        self.id = id
        self.date = date
        self.text = text
        self.mood = mood
        self.conditionScore = conditionScore
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.photoPaths = photoPaths
        self.favoritePhotoPath = favoritePhotoPath
    }
}

struct Habit: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var iconName: String
    var colorHex: String
    var schedule: HabitSchedule
    var isArchived: Bool
    var createdAt: Date
    var archivedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, iconName, colorHex, schedule, isArchived, createdAt, archivedAt
    }

    init(id: UUID = UUID(),
         title: String,
         iconName: String,
         colorHex: String,
         schedule: HabitSchedule,
         isArchived: Bool = false,
         createdAt: Date = Date(),
         archivedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.colorHex = colorHex
        self.schedule = schedule
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        iconName = try container.decode(String.self, forKey: .iconName)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        schedule = try container.decode(HabitSchedule.self, forKey: .schedule)
        // New fields: use defaults if missing
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date.distantPast
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
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
    var startDate: Date?              // 開始日（プログレスバー用）
    var startLabel: String?           // 開始ラベル（例：「生まれてから」）
    var endLabel: String?             // 終了ラベル（例：「100歳まで」）
    var reminderDaysBefore: Int?
    var reminderTime: Date?
    var reminderDate: Date?

    init(id: UUID = UUID(),
         title: String,
         targetDate: Date,
         type: AnniversaryType,
         repeatsYearly: Bool,
         startDate: Date? = nil,
         startLabel: String? = nil,
         endLabel: String? = nil,
         reminderDaysBefore: Int? = nil,
         reminderTime: Date? = nil,
         reminderDate: Date? = nil) {
        self.id = id
        self.title = title
        self.targetDate = targetDate
        self.type = type
        self.repeatsYearly = repeatsYearly
        self.startDate = startDate
        self.startLabel = startLabel
        self.endLabel = endLabel
        self.reminderDaysBefore = reminderDaysBefore
        self.reminderTime = reminderTime
        self.reminderDate = reminderDate
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
    
    /// 開始日からの進捗（0.0〜1.0）、開始日が未設定の場合はnil
    func progress(on date: Date) -> Double? {
        guard let start = startDate else { return nil }
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let targetDay = calendar.startOfDay(for: targetDate)
        let today = calendar.startOfDay(for: date)
        
        let totalDays = calendar.dateComponents([.day], from: startDay, to: targetDay).day ?? 0
        guard totalDays > 0 else { return nil }
        
        let elapsedDays = calendar.dateComponents([.day], from: startDay, to: today).day ?? 0
        let progress = Double(elapsedDays) / Double(totalDays)
        return min(max(progress, 0), 1)  // 0〜1にクランプ
    }
    
    /// 全期間の日数
    var totalDays: Int? {
        guard let start = startDate else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: targetDate)).day
    }
    
    /// 開始日からの経過日数
    func elapsedDays(on date: Date) -> Int? {
        guard let start = startDate else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: date)).day
    }
    
    /// 終了日までの残り日数
    func remainingDays(on date: Date) -> Int? {
        guard startDate != nil else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: targetDate)).day
    }
}

struct HealthSummary: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var date: Date
    var steps: Int?
    var sleepHours: Double?
    var activeEnergy: Double?
    var moveMinutes: Double?
    var exerciseMinutes: Double?
    var standHours: Double?
    var sleepStart: Date?
    var sleepEnd: Date?
    var sleepStages: [SleepStage] = []
    
    // 天気データ
    var weatherCondition: String?      // 天気状態（晴れ、曇り、雨など）
    var highTemperature: Double?       // 最高気温
    var lowTemperature: Double?        // 最低気温
    
    init(date: Date) {
        self.date = date
    }
    
    /// 天気の説明文（AI分析用）
    var weatherDescription: String? {
        guard let condition = weatherCondition else { return nil }
        var parts = [condition]
        if let high = highTemperature, let low = lowTemperature {
            parts.append("最高\(Int(high))°C/最低\(Int(low))°C")
        }
        return parts.joined(separator: "、")
    }
}

struct CalendarEvent: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var calendarName: String
    var isAllDay: Bool
    var sourceCalendarIdentifier: String?
    var reminderMinutes: Int?
    var reminderDate: Date?

    init(id: UUID = UUID(),
         title: String,
         startDate: Date,
         endDate: Date,
         calendarName: String,
         isAllDay: Bool = false,
         sourceCalendarIdentifier: String? = nil,
         reminderMinutes: Int? = nil,
         reminderDate: Date? = nil) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.calendarName = calendarName
        self.isAllDay = isAllDay
        self.sourceCalendarIdentifier = sourceCalendarIdentifier
        self.reminderMinutes = reminderMinutes
        self.reminderDate = reminderDate
    }
}

extension CalendarEvent {
    init(event: EKEvent, categoryName: String) {
        self.init(id: UUID(),
                  title: event.title,
                  startDate: event.startDate,
                  endDate: event.endDate,
                  calendarName: categoryName,
                  isAllDay: event.isAllDay,
                  sourceCalendarIdentifier: event.calendar.calendarIdentifier)
    }
}

enum SleepStageType: String, Codable, CaseIterable, Identifiable {
    case awake
    case rem
    case core
    case deep

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .awake: return "覚醒"
        case .rem: return "レム"
        case .core: return "コア"
        case .deep: return "深い"
        }
    }

    var color: Color {
        switch self {
        case .awake: return .orange
        case .rem: return .pink
        case .core: return .blue
        case .deep: return .indigo
        }
    }

    static var timelineOrder: [SleepStageType] { [.awake, .rem, .core, .deep] }
}

struct SleepStage: Identifiable, Codable, Hashable {
    let id = UUID()
    var start: Date
    var end: Date
    var stage: SleepStageType

    var durationMinutes: Double {
        end.timeIntervalSince(start) / 60
    }
}

extension SleepStage {
    static func demoSequence(referenceDate: Date = Date()) -> [SleepStage] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: referenceDate)
        guard
            let previousEvening = calendar.date(byAdding: .hour, value: -3, to: startOfDay),
            let bedtime = calendar.date(byAdding: .hour, value: -1, to: startOfDay),
            let midnight = calendar.date(byAdding: .hour, value: 0, to: startOfDay),
            let earlyMorning = calendar.date(byAdding: .hour, value: 3, to: startOfDay),
            let wakeUp = calendar.date(byAdding: .hour, value: 6, to: startOfDay)
        else {
            return []
        }

        return [
            SleepStage(start: previousEvening,
                       end: bedtime,
                       stage: .awake),
            SleepStage(start: bedtime,
                       end: midnight,
                       stage: .core),
            SleepStage(start: midnight,
                       end: earlyMorning,
                       stage: .deep),
            SleepStage(start: earlyMorning,
                       end: earlyMorning.addingTimeInterval(60 * 60),
                       stage: .rem),
            SleepStage(start: earlyMorning.addingTimeInterval(60 * 60),
                       end: wakeUp,
                       stage: .core)
        ]
    }
}
