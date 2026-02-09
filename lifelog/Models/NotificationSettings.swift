//
//  NotificationSettings.swift
//  lifelog
//
//  Created by Codex on 2025/12/06.
//

import Foundation

// MARK: - Category Notification Settings (Events)

struct CategoryNotificationSetting: Codable, Identifiable, Equatable {
    var id: String { categoryName }
    let categoryName: String
    var enabled: Bool
    var useRelativeTime: Bool  // true = X分前, false = 時刻指定
    var minutesBefore: Int     // 5, 15, 30, 60, 1440
    var hour: Int              // 時刻指定の場合
    var minute: Int            // 時刻指定の場合
    
    static let defaultMinutes = 30
    
    init(categoryName: String, enabled: Bool = true, useRelativeTime: Bool = true, minutesBefore: Int = 30, hour: Int = 9, minute: Int = 0) {
        self.categoryName = categoryName
        self.enabled = enabled
        self.useRelativeTime = useRelativeTime
        self.minutesBefore = minutesBefore
        self.hour = hour
        self.minute = minute
    }
}

// MARK: - Priority Notification Settings (Tasks)

struct PriorityNotificationSetting: Codable, Identifiable, Equatable {
    var id: Int { priority }
    let priority: Int  // TaskPriority.rawValue: 1=low, 2=medium, 3=high
    var enabled: Bool
    var hour: Int
    var minute: Int
    
    init(priority: Int, enabled: Bool = true, hour: Int = 9, minute: Int = 0) {
        self.priority = priority
        self.enabled = enabled
        self.hour = hour
        self.minute = minute
    }
    
    static let defaultSettings: [PriorityNotificationSetting] = [
        PriorityNotificationSetting(priority: 3, enabled: true, hour: 9, minute: 0),   // high
        PriorityNotificationSetting(priority: 2, enabled: true, hour: 9, minute: 0),   // medium
        PriorityNotificationSetting(priority: 1, enabled: false, hour: 9, minute: 0)   // low
    ]
}

// MARK: - Storage Manager

class NotificationSettingsManager {
    static let shared = NotificationSettingsManager()
    
    private let categorySettingsKey = "categoryNotificationSettings"
    private let prioritySettingsKey = "priorityNotificationSettings"
    private let eventNotificationEnabledKey = "eventCategoryNotificationEnabled"
    private let taskNotificationEnabledKey = "taskPriorityNotificationEnabled"
    
    private init() {}
    
    // MARK: - Event Category Settings
    
    var isEventCategoryNotificationEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: eventNotificationEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: eventNotificationEnabledKey) }
    }
    
    func getCategorySettings() -> [CategoryNotificationSetting] {
        guard let data = UserDefaults.standard.data(forKey: categorySettingsKey),
              let settings = try? JSONDecoder().decode([CategoryNotificationSetting].self, from: data) else {
            return []
        }
        return settings
    }
    
    func saveCategorySettings(_ settings: [CategoryNotificationSetting]) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: categorySettingsKey)
        }
    }
    
    func getSetting(for category: String) -> CategoryNotificationSetting? {
        return getCategorySettings().first { $0.categoryName == category }
    }

    @discardableResult
    func getOrCreateSetting(for category: String) -> CategoryNotificationSetting {
        if let existing = getSetting(for: category) {
            return existing
        }

        var settings = getCategorySettings()
        let newSetting = CategoryNotificationSetting(categoryName: category)
        settings.append(newSetting)
        saveCategorySettings(settings)
        return newSetting
    }

    @discardableResult
    func ensureCategorySettings(for categories: [String]) -> [CategoryNotificationSetting] {
        var settings = getCategorySettings()
        var changed = false

        for category in categories where settings.contains(where: { $0.categoryName == category }) == false {
            settings.append(CategoryNotificationSetting(categoryName: category))
            changed = true
        }

        if changed {
            saveCategorySettings(settings)
        }

        return settings
    }
    
    func updateSetting(for category: String, enabled: Bool? = nil, minutesBefore: Int? = nil) {
        var settings = getCategorySettings()
        if let index = settings.firstIndex(where: { $0.categoryName == category }) {
            if let enabled = enabled {
                settings[index].enabled = enabled
            }
            if let minutes = minutesBefore {
                settings[index].minutesBefore = minutes
            }
        } else {
            // Create new setting for this category
            let newSetting = CategoryNotificationSetting(
                categoryName: category,
                enabled: enabled ?? true,
                minutesBefore: minutesBefore ?? CategoryNotificationSetting.defaultMinutes
            )
            settings.append(newSetting)
        }
        saveCategorySettings(settings)
    }
    
    // MARK: - Task Priority Settings
    
    var isTaskPriorityNotificationEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: taskNotificationEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: taskNotificationEnabledKey) }
    }
    
    func getPrioritySettings() -> [PriorityNotificationSetting] {
        guard let data = UserDefaults.standard.data(forKey: prioritySettingsKey),
              let settings = try? JSONDecoder().decode([PriorityNotificationSetting].self, from: data) else {
            return PriorityNotificationSetting.defaultSettings
        }
        return settings
    }
    
    func savePrioritySettings(_ settings: [PriorityNotificationSetting]) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: prioritySettingsKey)
        }
    }
    
    func getSetting(for priority: TaskPriority) -> PriorityNotificationSetting? {
        let key = priority.rawValue
        return getPrioritySettings().first { $0.priority == key }
    }
    
    func updateSetting(for priority: TaskPriority, enabled: Bool? = nil, hour: Int? = nil, minute: Int? = nil) {
        var settings = getPrioritySettings()
        let key = priority.rawValue
        if let index = settings.firstIndex(where: { $0.priority == key }) {
            if let enabled = enabled {
                settings[index].enabled = enabled
            }
            if let hour = hour {
                settings[index].hour = hour
            }
            if let minute = minute {
                settings[index].minute = minute
            }
            savePrioritySettings(settings)
        }
    }
}
