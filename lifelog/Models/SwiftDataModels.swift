//
//  SwiftDataModels.swift
//  lifelog
//
//  Created for SwiftData Migration
//

import Foundation
import SwiftData
import SwiftUI // For Color if needed, though usually stored as Hex String/Int in DB

// MARK: - SDTask
@Model
final class SDTask {
    @Attribute(.unique) var id: UUID
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

// MARK: - SDDiaryEntry
@Model
final class SDDiaryEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var text: String
    var mood: MoodLevel?
    var conditionScore: Int?
    var locationName: String?
    var latitude: Double?
    var longitude: Double?
    var photoPaths: [String]
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

// MARK: - SDHabit
@Model
final class SDHabit {
    @Attribute(.unique) var id: UUID
    var title: String
    var iconName: String
    var colorHex: String
    
    // Flattened HabitSchedule for SwiftData compatibility
    var scheduleType: String
    var scheduleDays: [Int] // Raw values of Weekday
    
    var isArchived: Bool
    var createdAt: Date
    var archivedAt: Date?
    var orderIndex: Int

    init(id: UUID = UUID(),
         title: String,
         iconName: String,
         colorHex: String,
         schedule: HabitSchedule,
         isArchived: Bool = false,
         createdAt: Date = Date(),
         archivedAt: Date? = nil,
         orderIndex: Int = 0) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.colorHex = colorHex
        
        // Flatten logic
        switch schedule {
        case .daily:
            self.scheduleType = "daily"
            self.scheduleDays = []
        case .weekdays:
            self.scheduleType = "weekdays"
            self.scheduleDays = []
        case .custom(let days):
            self.scheduleType = "custom"
            self.scheduleDays = days.map { $0.rawValue }
        }
        
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.archivedAt = archivedAt
        self.orderIndex = orderIndex
    }
}

// MARK: - SDHabitRecord
@Model
final class SDHabitRecord {
    @Attribute(.unique) var id: UUID
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

// MARK: - SDAnniversary
@Model
final class SDAnniversary {
    @Attribute(.unique) var id: UUID
    var title: String
    var targetDate: Date
    var type: AnniversaryType
    var repeatsYearly: Bool
    var startDate: Date?
    var startLabel: String?
    var endLabel: String?
    var reminderDaysBefore: Int?
    var reminderTime: Date?
    var reminderDate: Date?
    var orderIndex: Int

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
         reminderDate: Date? = nil,
         orderIndex: Int = 0) {
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
        self.orderIndex = orderIndex
    }
}

// MARK: - SDHealthSummary
@Model
final class SDHealthSummary {
    @Attribute(.unique) var id: UUID
    var date: Date
    var steps: Int?
    var sleepHours: Double?
    var activeEnergy: Double?
    var moveMinutes: Double?
    var exerciseMinutes: Double?
    var standHours: Double?
    var sleepStart: Date?
    var sleepEnd: Date?
    var sleepStages: [SleepStage] // SleepStage must be persistent-compatible (Codable) which it is
    
    // Weather
    var weatherCondition: String?
    var highTemperature: Double?
    var lowTemperature: Double?

    init(id: UUID = UUID(),
         date: Date,
         steps: Int? = nil,
         sleepHours: Double? = nil,
         activeEnergy: Double? = nil,
         moveMinutes: Double? = nil,
         exerciseMinutes: Double? = nil,
         standHours: Double? = nil,
         sleepStart: Date? = nil,
         sleepEnd: Date? = nil,
         sleepStages: [SleepStage] = [],
         weatherCondition: String? = nil,
         highTemperature: Double? = nil,
         lowTemperature: Double? = nil) {
        self.id = id
        self.date = date
        self.steps = steps
        self.sleepHours = sleepHours
        self.activeEnergy = activeEnergy
        self.moveMinutes = moveMinutes
        self.exerciseMinutes = exerciseMinutes
        self.standHours = standHours
        self.sleepStart = sleepStart
        self.sleepEnd = sleepEnd
        self.sleepStages = sleepStages
        self.weatherCondition = weatherCondition
        self.highTemperature = highTemperature
        self.lowTemperature = lowTemperature
    }
}

// MARK: - SDCalendarEvent (Internal)
@Model
final class SDCalendarEvent {
    @Attribute(.unique) var id: UUID
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

// MARK: - SDMemoPad
@Model
final class SDMemoPad {
    // Only one should exist, but we can treat it as a model.
    // Migration logic will ensure only one exists or overwrite.
    var text: String
    var lastUpdatedAt: Date?

    init(text: String = "", lastUpdatedAt: Date? = nil) {
        self.text = text
        self.lastUpdatedAt = lastUpdatedAt
    }
}

// MARK: - SDAppState
@Model
final class SDAppState {
    // Similarly, only one instance expected.
    var lastCalendarSyncDate: Date?
    var calendarCategoryLinks: [CalendarCategoryLink] // CalendarCategoryLink must be Codable
    var diaryReminderEnabled: Bool
    var diaryReminderHour: Int
    var diaryReminderMinute: Int

    init(lastCalendarSyncDate: Date? = nil,
         calendarCategoryLinks: [CalendarCategoryLink] = [],
         diaryReminderEnabled: Bool = false,
         diaryReminderHour: Int = 21,
         diaryReminderMinute: Int = 0) {
        self.lastCalendarSyncDate = lastCalendarSyncDate
        self.calendarCategoryLinks = calendarCategoryLinks
        self.diaryReminderEnabled = diaryReminderEnabled
        self.diaryReminderHour = diaryReminderHour
        self.diaryReminderMinute = diaryReminderMinute
    }
}
