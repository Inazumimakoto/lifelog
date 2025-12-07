//
//  MigrationManager.swift
//  lifelog
//
//  Created for SwiftData Migration
//

import Foundation
import SwiftData
import SwiftUI

class MigrationManager {
    static let shared = MigrationManager()
    
    private let migrationKey = "isSwiftDataMigrated_v1"
    
    // Legacy Keys
    private let tasksKey = "Tasks_Storage_V1"
    private let diaryKey = "DiaryEntries_Storage_V1"
    private let habitsKey = "Habits_Storage_V1"
    private let habitRecordsKey = "HabitRecords_Storage_V1"
    private let anniversariesKey = "Anniversaries_Storage_V1"
    private let calendarEventsKey = "CalendarEvents_Storage_V1"
    private let memoPadKey = "MemoPad_Storage_V1"
    private let appStateKey = "AppState_Storage_V1"
    private let healthKey = "HealthSummaries_Storage_V1"
    
    @MainActor
    func migrate(modelContext: ModelContext) {
        if UserDefaults.standard.bool(forKey: migrationKey) {
            print("Migration already completed.")
            return
        }
        
        print("Starting migration from UserDefaults to SwiftData...")
        
        do {
            // 1. Task
            if let data = UserDefaults.standard.data(forKey: tasksKey),
               let items = try? JSONDecoder().decode([Task].self, from: data) {
                for item in items {
                    let newItem = SDTask(
                        id: item.id,
                        title: item.title,
                        detail: item.detail,
                        startDate: item.startDate,
                        endDate: item.endDate,
                        priority: item.priority,
                        isCompleted: item.isCompleted,
                        reminderDate: item.reminderDate
                    )
                    modelContext.insert(newItem)
                }
            }
            
            // 2. DiaryEntry
            if let data = UserDefaults.standard.data(forKey: diaryKey),
               let items = try? JSONDecoder().decode([DiaryEntry].self, from: data) {
                 // normalization logic from AppDataStore
                 let normalizedItems = AppDataStore.normalizeDiaryEntries(items)
                for item in normalizedItems {
                    let newItem = SDDiaryEntry(
                        id: item.id,
                        date: item.date,
                        text: item.text,
                        mood: item.mood,
                        conditionScore: item.conditionScore,
                        locationName: item.locationName,
                        latitude: item.latitude,
                        longitude: item.longitude,
                        photoPaths: item.photoPaths,
                        favoritePhotoPath: item.favoritePhotoPath
                    )
                    modelContext.insert(newItem)
                }
            }
            
            // 3. Habit
            if let data = UserDefaults.standard.data(forKey: habitsKey),
               let items = try? JSONDecoder().decode([Habit].self, from: data) {
                for (index, item) in items.enumerated() {
                    let newItem = SDHabit(domain: item)
                    newItem.orderIndex = index
                    modelContext.insert(newItem)
                }
            }
            
            // 4. HabitRecord
            if let data = UserDefaults.standard.data(forKey: habitRecordsKey),
               let items = try? JSONDecoder().decode([HabitRecord].self, from: data) {
                for item in items {
                    let newItem = SDHabitRecord(
                        id: item.id,
                        habitID: item.habitID,
                        date: item.date,
                        isCompleted: item.isCompleted
                    )
                    modelContext.insert(newItem)
                }
            }
            
            // 5. Anniversary
            if let data = UserDefaults.standard.data(forKey: anniversariesKey),
               let items = try? JSONDecoder().decode([Anniversary].self, from: data) {
                for (index, item) in items.enumerated() {
                    let newItem = SDAnniversary(
                        id: item.id,
                        title: item.title,
                        targetDate: item.targetDate,
                        type: item.type,
                        repeatsYearly: item.repeatsYearly,
                        startDate: item.startDate,
                        startLabel: item.startLabel,
                        endLabel: item.endLabel,
                        reminderDaysBefore: item.reminderDaysBefore,
                        reminderTime: item.reminderTime,
                        reminderDate: item.reminderDate,
                        orderIndex: index
                    )
                    modelContext.insert(newItem)
                }
            }
            
            // 6. HealthSummary
            if let data = UserDefaults.standard.data(forKey: healthKey),
               let items = try? JSONDecoder().decode([HealthSummary].self, from: data) {
                for item in items {
                    let newItem = SDHealthSummary(
                        id: item.id,
                        date: item.date,
                        steps: item.steps,
                        sleepHours: item.sleepHours,
                        activeEnergy: item.activeEnergy,
                        moveMinutes: item.moveMinutes,
                        exerciseMinutes: item.exerciseMinutes,
                        standHours: item.standHours,
                        sleepStart: item.sleepStart,
                        sleepEnd: item.sleepEnd,
                        sleepStages: item.sleepStages,
                        weatherCondition: item.weatherCondition,
                        highTemperature: item.highTemperature,
                        lowTemperature: item.lowTemperature
                    )
                    modelContext.insert(newItem)
                }
            }
            
            // 7. CalendarEvent (Internal)
            if let data = UserDefaults.standard.data(forKey: calendarEventsKey),
               let items = try? JSONDecoder().decode([CalendarEvent].self, from: data) {
                for item in items {
                    let newItem = SDCalendarEvent(
                        id: item.id,
                        title: item.title,
                        startDate: item.startDate,
                        endDate: item.endDate,
                        calendarName: item.calendarName,
                        isAllDay: item.isAllDay,
                        sourceCalendarIdentifier: item.sourceCalendarIdentifier,
                        reminderMinutes: item.reminderMinutes,
                        reminderDate: item.reminderDate
                    )
                    modelContext.insert(newItem)
                }
            }
            
            // 8. MemoPad
            if let data = UserDefaults.standard.data(forKey: memoPadKey),
               let item = try? JSONDecoder().decode(MemoPad.self, from: data) {
                let newItem = SDMemoPad(
                    text: item.text,
                    lastUpdatedAt: item.lastUpdatedAt
                )
                modelContext.insert(newItem)
            }
            
            // 9. AppState
            if let data = UserDefaults.standard.data(forKey: appStateKey),
               let item = try? JSONDecoder().decode(AppState.self, from: data) {
                let newItem = SDAppState(
                    lastCalendarSyncDate: item.lastCalendarSyncDate,
                    calendarCategoryLinks: item.calendarCategoryLinks,
                    diaryReminderEnabled: item.diaryReminderEnabled,
                    diaryReminderHour: item.diaryReminderHour,
                    diaryReminderMinute: item.diaryReminderMinute
                )
                modelContext.insert(newItem)
            }
            
            try modelContext.save()
            UserDefaults.standard.set(true, forKey: migrationKey)
            print("Migration completed successfully.")
            
        } catch {
            print("Migration failed: \(error)")
        }
    }
}
