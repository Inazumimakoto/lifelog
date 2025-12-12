//
//  ModelMapping.swift
//  lifelog
//
//  Created for SwiftData Migration
//

import Foundation

// MARK: - Task Mapping
extension Task {
    init(sd: SDTask) {
        self.init(
            id: sd.id,
            title: sd.title,
            detail: sd.detail,
            startDate: sd.startDate,
            endDate: sd.endDate,
            priority: sd.priority,
            isCompleted: sd.isCompleted,
            reminderDate: sd.reminderDate
        )
    }
}

extension SDTask {
    convenience init(domain: Task) {
        self.init(
            id: domain.id,
            title: domain.title,
            detail: domain.detail,
            startDate: domain.startDate,
            endDate: domain.endDate,
            priority: domain.priority,
            isCompleted: domain.isCompleted,
            reminderDate: domain.reminderDate
        )
    }
    
    func update(from domain: Task) {
        self.title = domain.title
        self.detail = domain.detail
        self.startDate = domain.startDate
        self.endDate = domain.endDate
        self.priority = domain.priority
        self.isCompleted = domain.isCompleted
        self.reminderDate = domain.reminderDate
    }
}

// MARK: - DiaryEntry Mapping
extension DiaryEntry {
    init(sd: SDDiaryEntry) {
        self.init(
            id: sd.id,
            date: sd.date,
            text: sd.text,
            mood: sd.mood,
            conditionScore: sd.conditionScore,
            locationName: sd.locationName,
            latitude: sd.latitude,
            longitude: sd.longitude,
            photoPaths: sd.photoPaths,
            favoritePhotoPath: sd.favoritePhotoPath
        )
    }
}

extension SDDiaryEntry {
    convenience init(domain: DiaryEntry) {
        self.init(
            id: domain.id,
            date: domain.date,
            text: domain.text,
            mood: domain.mood,
            conditionScore: domain.conditionScore,
            locationName: domain.locationName,
            latitude: domain.latitude,
            longitude: domain.longitude,
            photoPaths: domain.photoPaths,
            favoritePhotoPath: domain.favoritePhotoPath
        )
    }
    
    func update(from domain: DiaryEntry) {
        self.date = domain.date
        self.text = domain.text
        self.mood = domain.mood
        self.conditionScore = domain.conditionScore
        self.locationName = domain.locationName
        self.latitude = domain.latitude
        self.longitude = domain.longitude
        self.photoPaths = domain.photoPaths
        self.favoritePhotoPath = domain.favoritePhotoPath
    }
}

// MARK: - Habit Mapping
extension Habit {
    init(sd: SDHabit) {
        let schedule: HabitSchedule
        switch sd.scheduleType {
        case "daily":
            schedule = .daily
        case "weekdays":
            schedule = .weekdays
        case "custom":
            let days = sd.scheduleDays.compactMap { Weekday(rawValue: $0) }
            schedule = .custom(days: days)
        default:
            schedule = .daily // Fallback
        }
        
        self.init(
            id: sd.id,
            title: sd.title,
            iconName: sd.iconName,
            colorHex: sd.colorHex,
            schedule: schedule,
            isArchived: sd.isArchived,
            createdAt: sd.createdAt,
            archivedAt: sd.archivedAt
        )
    }
}

extension SDHabit {
    convenience init(domain: Habit) {
        self.init(
            id: domain.id,
            title: domain.title,
            iconName: domain.iconName,
            colorHex: domain.colorHex,
            schedule: domain.schedule,
            isArchived: domain.isArchived,
            createdAt: domain.createdAt,
            archivedAt: domain.archivedAt
        )
    }
    
    func update(from domain: Habit) {
        self.title = domain.title
        self.iconName = domain.iconName
        self.colorHex = domain.colorHex
        
        // Update flattened schedule
        switch domain.schedule {
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
        
        self.isArchived = domain.isArchived
        self.createdAt = domain.createdAt
        self.archivedAt = domain.archivedAt
    }
}

// MARK: - HabitRecord Mapping
extension HabitRecord {
    init(sd: SDHabitRecord) {
        self.init(
            id: sd.id,
            habitID: sd.habitID,
            date: sd.date,
            isCompleted: sd.isCompleted
        )
    }
}

extension SDHabitRecord {
    convenience init(domain: HabitRecord) {
        self.init(
            id: domain.id,
            habitID: domain.habitID,
            date: domain.date,
            isCompleted: domain.isCompleted
        )
    }
    
    func update(from domain: HabitRecord) {
        self.habitID = domain.habitID
        self.date = domain.date
        self.isCompleted = domain.isCompleted
    }
}

// MARK: - Anniversary Mapping
extension Anniversary {
    init(sd: SDAnniversary) {
        self.init(
            id: sd.id,
            title: sd.title,
            targetDate: sd.targetDate,
            type: sd.type,
            repeatsYearly: sd.repeatsYearly,
            startDate: sd.startDate,
            startLabel: sd.startLabel,
            endLabel: sd.endLabel,
            reminderDaysBefore: sd.reminderDaysBefore,
            reminderTime: sd.reminderTime,
            reminderDate: sd.reminderDate
        )
    }
}

extension SDAnniversary {
    convenience init(domain: Anniversary) {
        self.init(
            id: domain.id,
            title: domain.title,
            targetDate: domain.targetDate,
            type: domain.type,
            repeatsYearly: domain.repeatsYearly,
            startDate: domain.startDate,
            startLabel: domain.startLabel,
            endLabel: domain.endLabel,
            reminderDaysBefore: domain.reminderDaysBefore,
            reminderTime: domain.reminderTime,
            reminderDate: domain.reminderDate
        )
    }
    
    func update(from domain: Anniversary) {
        self.title = domain.title
        self.targetDate = domain.targetDate
        self.type = domain.type
        self.repeatsYearly = domain.repeatsYearly
        self.startDate = domain.startDate
        self.startLabel = domain.startLabel
        self.endLabel = domain.endLabel
        self.reminderDaysBefore = domain.reminderDaysBefore
        self.reminderTime = domain.reminderTime
        self.reminderDate = domain.reminderDate
    }
}

// MARK: - HealthSummary Mapping
extension HealthSummary {
    init(sd: SDHealthSummary) {
        // SDHealthSummary fields are optionals and match struct
        var summary = HealthSummary(date: sd.date)
        summary.id = sd.id
        summary.steps = sd.steps
        summary.sleepHours = sd.sleepHours
        summary.activeEnergy = sd.activeEnergy
        summary.moveMinutes = sd.moveMinutes
        summary.exerciseMinutes = sd.exerciseMinutes
        summary.standHours = sd.standHours
        summary.sleepStart = sd.sleepStart
        summary.sleepEnd = sd.sleepEnd
        summary.sleepStages = sd.sleepStages
        summary.weatherCondition = sd.weatherCondition
        summary.highTemperature = sd.highTemperature
        summary.lowTemperature = sd.lowTemperature
        self = summary
    }
}

extension SDHealthSummary {
    convenience init(domain: HealthSummary) {
        self.init(
            id: domain.id,
            date: domain.date,
            steps: domain.steps,
            sleepHours: domain.sleepHours,
            activeEnergy: domain.activeEnergy,
            moveMinutes: domain.moveMinutes,
            exerciseMinutes: domain.exerciseMinutes,
            standHours: domain.standHours,
            sleepStart: domain.sleepStart,
            sleepEnd: domain.sleepEnd,
            sleepStages: domain.sleepStages,
            weatherCondition: domain.weatherCondition,
            highTemperature: domain.highTemperature,
            lowTemperature: domain.lowTemperature
        )
    }
    
    func update(from domain: HealthSummary) {
        self.date = domain.date
        self.steps = domain.steps
        self.sleepHours = domain.sleepHours
        self.activeEnergy = domain.activeEnergy
        self.moveMinutes = domain.moveMinutes
        self.exerciseMinutes = domain.exerciseMinutes
        self.standHours = domain.standHours
        self.sleepStart = domain.sleepStart
        self.sleepEnd = domain.sleepEnd
        self.sleepStages = domain.sleepStages
        self.weatherCondition = domain.weatherCondition
        self.highTemperature = domain.highTemperature
        self.lowTemperature = domain.lowTemperature
    }
}

// MARK: - CalendarEvent Mapping
extension CalendarEvent {
    init(sd: SDCalendarEvent) {
        self.init(
            id: sd.id,
            title: sd.title,
            startDate: sd.startDate,
            endDate: sd.endDate,
            calendarName: sd.calendarName,
            isAllDay: sd.isAllDay,
            sourceCalendarIdentifier: sd.sourceCalendarIdentifier,
            reminderMinutes: sd.reminderMinutes,
            reminderDate: sd.reminderDate
        )
    }
}

extension SDCalendarEvent {
    convenience init(domain: CalendarEvent) {
        self.init(
            id: domain.id,
            title: domain.title,
            startDate: domain.startDate,
            endDate: domain.endDate,
            calendarName: domain.calendarName,
            isAllDay: domain.isAllDay,
            sourceCalendarIdentifier: domain.sourceCalendarIdentifier,
            reminderMinutes: domain.reminderMinutes,
            reminderDate: domain.reminderDate
        )
    }
    
    func update(from domain: CalendarEvent) {
        self.title = domain.title
        self.startDate = domain.startDate
        self.endDate = domain.endDate
        self.calendarName = domain.calendarName
        self.isAllDay = domain.isAllDay
        self.sourceCalendarIdentifier = domain.sourceCalendarIdentifier
        self.reminderMinutes = domain.reminderMinutes
        self.reminderDate = domain.reminderDate
    }
}

// MARK: - MemoPad Mapping
extension MemoPad {
    init(sd: SDMemoPad) {
        self.init(text: sd.text, lastUpdatedAt: sd.lastUpdatedAt)
    }
}

// MARK: - AppState Mapping
extension AppState {
    init(sd: SDAppState) {
        self.init(
            lastCalendarSyncDate: sd.lastCalendarSyncDate,
            calendarCategoryLinks: sd.calendarCategoryLinks,
            diaryReminderEnabled: sd.diaryReminderEnabled,
            diaryReminderHour: sd.diaryReminderHour,
            diaryReminderMinute: sd.diaryReminderMinute
        )
    }
}

// MARK: - Letter Mapping
extension Letter {
    init(sd: SDLetter) {
        let randomSettings: LetterRandomSettings? = {
            // 新しいフィールドも含めて判定
            if sd.randomUseDateRange || sd.randomUseTimeRange || sd.randomFixedDate != nil || sd.randomFixedHour != nil {
                return LetterRandomSettings(
                    useDateRange: sd.randomUseDateRange,
                    startDate: sd.randomStartDate,
                    endDate: sd.randomEndDate,
                    useTimeRange: sd.randomUseTimeRange,
                    startHour: sd.randomStartHour,
                    startMinute: sd.randomStartMinute,
                    endHour: sd.randomEndHour,
                    endMinute: sd.randomEndMinute,
                    fixedDate: sd.randomFixedDate,
                    fixedHour: sd.randomFixedHour,
                    fixedMinute: sd.randomFixedMinute
                )
            }
            return nil
        }()
        
        self.init(
            id: sd.id,
            content: sd.content,
            photoPaths: sd.photoPaths,
            createdAt: sd.createdAt,
            deliveryType: LetterDeliveryType(rawValue: sd.deliveryType) ?? .fixed,
            deliveryDate: sd.deliveryDate,
            randomSettings: randomSettings,
            status: LetterStatus(rawValue: sd.statusRaw) ?? .draft,
            openedAt: sd.openedAt,
            dismissedFromHome: sd.dismissedFromHome
        )
    }
}

extension SDLetter {
    convenience init(domain: Letter) {
        self.init(
            id: domain.id,
            content: domain.content,
            photoPaths: domain.photoPaths,
            createdAt: domain.createdAt,
            deliveryType: domain.deliveryType.rawValue,
            deliveryDate: domain.deliveryDate,
            statusRaw: domain.status.rawValue,
            openedAt: domain.openedAt,
            dismissedFromHome: domain.dismissedFromHome,
            randomUseDateRange: domain.randomSettings?.useDateRange ?? false,
            randomStartDate: domain.randomSettings?.startDate,
            randomEndDate: domain.randomSettings?.endDate,
            randomUseTimeRange: domain.randomSettings?.useTimeRange ?? false,
            randomStartHour: domain.randomSettings?.startHour ?? 9,
            randomStartMinute: domain.randomSettings?.startMinute ?? 0,
            randomEndHour: domain.randomSettings?.endHour ?? 21,
            randomEndMinute: domain.randomSettings?.endMinute ?? 0,
            randomFixedDate: domain.randomSettings?.fixedDate,
            randomFixedHour: domain.randomSettings?.fixedHour,
            randomFixedMinute: domain.randomSettings?.fixedMinute
        )
    }
    
    func update(from domain: Letter) {
        self.content = domain.content
        self.photoPaths = domain.photoPaths
        self.deliveryType = domain.deliveryType.rawValue
        self.deliveryDate = domain.deliveryDate
        self.statusRaw = domain.status.rawValue
        self.openedAt = domain.openedAt
        self.dismissedFromHome = domain.dismissedFromHome
        self.randomUseDateRange = domain.randomSettings?.useDateRange ?? false
        self.randomStartDate = domain.randomSettings?.startDate
        self.randomEndDate = domain.randomSettings?.endDate
        self.randomUseTimeRange = domain.randomSettings?.useTimeRange ?? false
        self.randomStartHour = domain.randomSettings?.startHour ?? 9
        self.randomStartMinute = domain.randomSettings?.startMinute ?? 0
        self.randomEndHour = domain.randomSettings?.endHour ?? 21
        self.randomEndMinute = domain.randomSettings?.endMinute ?? 0
        self.randomFixedDate = domain.randomSettings?.fixedDate
        self.randomFixedHour = domain.randomSettings?.fixedHour
        self.randomFixedMinute = domain.randomSettings?.fixedMinute
    }
}

// MARK: - SharedLetter Mapping
extension SharedLetter {
    init(sd: SDSharedLetter) {
        self.init(
            id: sd.id,
            senderId: sd.senderId,
            senderEmoji: sd.senderEmoji,
            senderName: sd.senderName,
            content: sd.content,
            photoPaths: sd.photoPaths,
            deliveredAt: sd.deliveredAt,
            openedAt: sd.openedAt
        )
    }
}

extension SDSharedLetter {
    convenience init(domain: SharedLetter) {
        self.init(
            id: domain.id,
            senderId: domain.senderId,
            senderEmoji: domain.senderEmoji,
            senderName: domain.senderName,
            content: domain.content,
            photoPaths: domain.photoPaths,
            deliveredAt: domain.deliveredAt,
            openedAt: domain.openedAt
        )
    }
}
