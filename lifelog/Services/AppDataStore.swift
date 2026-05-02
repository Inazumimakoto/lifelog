//
//  AppDataStore.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import Combine
import HealthKit
import EventKit
import UserNotifications
import SwiftUI
import SwiftData
import WidgetKit

@MainActor
final class AppDataStore: ObservableObject {

    // MARK: - Published Sources

    @Published private(set) var tasks: [Task] = []
    @Published private(set) var diaryEntries: [DiaryEntry] = []
    @Published private(set) var habits: [Habit] = []
    @Published private(set) var habitRecords: [HabitRecord] = []
    @Published private(set) var anniversaries: [Anniversary] = []
    @Published private(set) var healthSummaries: [HealthSummary] = []
    @Published private(set) var calendarEvents: [CalendarEvent] = []
    @Published private(set) var memoPad: MemoPad = MemoPad()
    @Published private(set) var externalCalendarEvents: [CalendarEvent] = []
    @Published private(set) var letters: [Letter] = []
    @Published private(set) var sharedLetters: [SharedLetter] = []  // 他ユーザーからの手紙
    @Published private(set) var appState: AppState = AppState()
    @Published private(set) var locationVisitTagDefinitions: [LocationVisitTagDefinition] = []

    // MARK: - Cache
    private var eventsCache: [Date: [CalendarEvent]] = [:]
    private var externalCalendarRange: ExternalCalendarRange? = nil
    private var externalReminderRescheduleGeneration: UInt = 0
    private(set) var hasExistingUserFootprintForInitialPermissions = false

    // MARK: - Legacy Persistence Keys
    private static let tasksDefaultsKey = "Tasks_Storage_V1"
    private static let diaryDefaultsKey = "DiaryEntries_Storage_V1"
    private static let habitsDefaultsKey = "Habits_Storage_V1"
    private static let habitRecordsDefaultsKey = "HabitRecords_Storage_V1"
    private static let anniversariesDefaultsKey = "Anniversaries_Storage_V1"
    private static let calendarEventsDefaultsKey = "CalendarEvents_Storage_V1"
    private static let externalCalendarEventsDefaultsKey = "ExternalCalendarEvents_Storage_V1"
    private static let externalCalendarRangeDefaultsKey = "ExternalCalendarRange_Storage_V1"
    private static let memoPadDefaultsKey = "MemoPad_Storage_V1"
    private static let appStateDefaultsKey = "AppState_Storage_V1"
    private static let healthSummariesDefaultsKey = "HealthSummaries_Storage_V1"
    private static let locationVisitTagsDefaultsKey = "LocationVisitTags_Storage_V1"
    private static let locationVisitTagsSeededDefaultsKey = "LocationVisitTagsSeeded_Storage_V1"
    private static let defaultLocationVisitTagNames: [String] = [
        "ご飯", "カフェ", "仕事", "勉強", "買い物", "旅行", "観光", "運動", "用事", "友人", "家族", "デート"
    ]
    #if DEBUG
    private static let screenshotsModeLaunchArguments: Set<String> = [
        "-screenshots-mode",
        "-ScreenshotsMode",
    ]
    #endif

    // MARK: - SwiftData Context
    private let modelContext: ModelContext
    
    static let maxLocationVisitTagsPerVisit = 8
    static let maxLocationVisitTagNameLength = 15
    
    enum LocationVisitTagError: LocalizedError {
        case emptyName
        case nameTooLong(max: Int)
        case duplicateName
        case tagNotFound
        
        var errorDescription: String? {
            switch self {
            case .emptyName:
                return "タグ名を入力してください。"
            case .nameTooLong(let max):
                return "タグ名は\(max)文字以内で入力してください。"
            case .duplicateName:
                return "同じ名前のタグが既にあります。"
            case .tagNotFound:
                return "対象のタグが見つかりませんでした。"
            }
        }
    }

    // MARK: - Init

    init() {
        // Setup SwiftData
        let container = PersistenceController.shared.container
        self.modelContext = container.mainContext
        
        // 1. Run Migration (if needed)
        MigrationManager.shared.migrate(modelContext: modelContext)
        
        // 2. Load Data from SwiftData
        // We load into the existing @Published properties to maintain View compatibility
        // Note: We use helper methods to fetch and map SD models to structs
        
        do {
            // Tasks
            let sdTasks = try modelContext.fetch(FetchDescriptor<SDTask>())
            self.tasks = sdTasks.map { Task(sd: $0) }
            
            // DiaryEntries
            let sdDiaries = try modelContext.fetch(FetchDescriptor<SDDiaryEntry>())
            let mappedDiaries = sdDiaries.map { DiaryEntry(sd: $0) }
            // Normalization logic is still useful
            let needsNormalization = mappedDiaries.contains { $0.mood == nil || $0.conditionScore == nil }
            self.diaryEntries = Self.normalizeDiaryEntries(mappedDiaries)
            
            // Habits
            let sdHabits = try modelContext.fetch(FetchDescriptor<SDHabit>(sortBy: [SortDescriptor(\.orderIndex)]))
            self.habits = sdHabits.map { Habit(sd: $0) }
            
            // HabitRecords
            let sdRecords = try modelContext.fetch(FetchDescriptor<SDHabitRecord>())
            self.habitRecords = sdRecords.map { HabitRecord(sd: $0) }
            
            // Anniversaries
            let sdAnniversaries = try modelContext.fetch(FetchDescriptor<SDAnniversary>(sortBy: [SortDescriptor(\.orderIndex)]))
            self.anniversaries = sdAnniversaries.map { Anniversary(sd: $0) }
            
            // CalendarEvents (Internal)
            let sdEvents = try modelContext.fetch(FetchDescriptor<SDCalendarEvent>())
            self.calendarEvents = sdEvents.map { CalendarEvent(sd: $0) }
            
            // Letters
            let sdLetters = try modelContext.fetch(FetchDescriptor<SDLetter>())
            self.letters = sdLetters.map { Letter(sd: $0) }
            
            // SharedLetters (他ユーザーからの手紙)
            let sdSharedLetters = try modelContext.fetch(FetchDescriptor<SDSharedLetter>(sortBy: [SortDescriptor(\.openedAt, order: .reverse)]))
            self.sharedLetters = sdSharedLetters.map { SharedLetter(sd: $0) }
            
            // HealthSummaries (Cache)
            let sdHealth = try modelContext.fetch(FetchDescriptor<SDHealthSummary>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
            self.healthSummaries = sdHealth.map { HealthSummary(sd: $0) }
            
            // MemoPad
            let sdMemos = try modelContext.fetch(FetchDescriptor<SDMemoPad>())
            if let first = sdMemos.first {
                self.memoPad = MemoPad(sd: first)
            } else {
                self.memoPad = MemoPad()
            }
            
            // AppState
            let sdStates = try modelContext.fetch(FetchDescriptor<SDAppState>())
            if let first = sdStates.first {
                self.appState = AppState(sd: first)
            } else {
                self.appState = AppState()
            }
            
            // If diary normalization happened (in memory), we should update DB?
            // Since we just loaded from DB, if DB had nil, we normalized in memory.
            // We should save back to DB if normalized.
            // However, SDDiaryEntry properties are optional?
            // Struct DiaryEntry has optional mood?
            // normalizeDiaryEntries fills nil with default.
            // If we want to persist this fix, we should update SDDiaryEntries.
            // Ideally migration handles this, but legacy normalization logic is safe to keep.
            if needsNormalization {
                // Bulk update logic? Or just iterate and save.
                // For now, assume migration likely handled it or lazy update on edit.
            }
            
        } catch {
            print("Failed to fetch initial data from SwiftData: \(error)")
        }

        self.externalCalendarEvents = Self.loadValue(forKey: Self.externalCalendarEventsDefaultsKey, defaultValue: [])
        let storedRange: ExternalCalendarRange? = Self.loadValue(forKey: Self.externalCalendarRangeDefaultsKey, defaultValue: nil)
        self.externalCalendarRange = storedRange
        self.locationVisitTagDefinitions = Self.loadValue(forKey: Self.locationVisitTagsDefaultsKey, defaultValue: [])
        normalizeLocationVisitTagOrderIfNeeded()
        let hasSeenInitialPermissionsFeature = UserDefaults.standard.bool(forKey: InitialPermissionsState.featureSeenKey)
        hasExistingUserFootprintForInitialPermissions = hasUserContentForInitialPermissions ||
            Self.hasStoredUserDefaultsFootprintForInitialPermissions(
                includeAutoSeededKeys: hasSeenInitialPermissionsFeature == false
            )
        UserDefaults.standard.set(true, forKey: InitialPermissionsState.featureSeenKey)
        seedDefaultLocationVisitTagsIfNeeded()

        reapplyEventCategoryNotificationSettings()
        rescheduleTodayOverviewReminderIfNeeded()

        #if DEBUG
        seedSampleDataIfNeeded()
        seedJapaneseScheduleForScreenshotsIfNeeded()
        #endif
        loadCachedHealthData()
        if UserDefaults.standard.bool(forKey: InitialPermissionsState.healthRequestedKey) {
            _Concurrency.Task {
                await loadHealthData()
            }
        }
    }

    private var hasUserContentForInitialPermissions: Bool {
        !tasks.isEmpty ||
        !diaryEntries.isEmpty ||
        !habits.isEmpty ||
        !habitRecords.isEmpty ||
        !anniversaries.isEmpty ||
        !calendarEvents.isEmpty ||
        !externalCalendarEvents.isEmpty ||
        !letters.isEmpty ||
        !sharedLetters.isEmpty ||
        !healthSummaries.isEmpty ||
        memoPad.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
        memoPad.lastUpdatedAt != nil ||
        appState.lastCalendarSyncDate != nil ||
        appState.calendarCategoryLinks.isEmpty == false ||
        appState.diaryReminderEnabled
    }

    private func loadCachedHealthData() {
        let cached: [HealthSummary] = Self.loadValue(forKey: Self.healthSummariesDefaultsKey, defaultValue: [])
        if !cached.isEmpty {
            self.healthSummaries = cached
        }
    }

    @discardableResult
    func loadHealthData(requestAuthorizationIfNeeded: Bool = false) async -> Bool {
        loadCachedHealthData()

        if requestAuthorizationIfNeeded {
            UserDefaults.standard.set(true, forKey: InitialPermissionsState.healthRequestedKey)
            let authorizationCompleted = await HealthKitManager.shared.requestAuthorization()
            guard authorizationCompleted else { return false }
        } else {
            guard UserDefaults.standard.bool(forKey: InitialPermissionsState.healthRequestedKey) else {
                return false
            }
        }

        // Fetch recent 7 days for quick update, then full year in background.
        let recentFetched = await HealthKitManager.shared.fetchHealthData(for: 7)
        if !recentFetched.isEmpty {
            mergeHealthSummaries(recentFetched)
        }

        let fullFetched = await HealthKitManager.shared.fetchHealthData(for: 365)
        if !fullFetched.isEmpty {
            mergeHealthSummaries(fullFetched)
            persistHealthSummaries()
        }

        return true
    }
    
    private func mergeHealthSummaries(_ newData: [HealthSummary]) {
        var summaryDict = Dictionary(uniqueKeysWithValues: healthSummaries.map { ($0.date, $0) })
        for summary in newData {
            if var existing = summaryDict[summary.date] {
                // 既存データがある場合は、天気データを保持しながらマージ
                // HealthKitデータで更新
                existing.steps = summary.steps ?? existing.steps
                existing.sleepHours = summary.sleepHours ?? existing.sleepHours
                existing.sleepStart = summary.sleepStart ?? existing.sleepStart
                existing.sleepEnd = summary.sleepEnd ?? existing.sleepEnd
                existing.activeEnergy = summary.activeEnergy ?? existing.activeEnergy
                existing.moveMinutes = summary.moveMinutes ?? existing.moveMinutes
                existing.exerciseMinutes = summary.exerciseMinutes ?? existing.exerciseMinutes
                existing.standHours = summary.standHours ?? existing.standHours
                if !summary.sleepStages.isEmpty {
                    existing.sleepStages = summary.sleepStages
                }
                // 天気データは新データにある場合のみ更新（nilで上書きしない）
                if summary.weatherCondition != nil {
                    existing.weatherCondition = summary.weatherCondition
                }
                if summary.highTemperature != nil {
                    existing.highTemperature = summary.highTemperature
                }
                if summary.lowTemperature != nil {
                    existing.lowTemperature = summary.lowTemperature
                }
                summaryDict[summary.date] = existing
            } else {
                // 新規データ
                summaryDict[summary.date] = summary
            }
        }
        healthSummaries = Array(summaryDict.values).sorted { $0.date > $1.date }
    }
    
    private func persistHealthSummaries() {
        persist(healthSummaries, forKey: Self.healthSummariesDefaultsKey)
        
        // Full Sync to SwiftData (keyed by Date to avoid duplication if IDs change)
        // 1. Fetch all existing SDHealthSummaries
        let descriptor = FetchDescriptor<SDHealthSummary>()
        if let existingItems = try? modelContext.fetch(descriptor) {
            // Map by Date (start of day) for matching
            let calendar = Calendar.current
            var existingMap = Dictionary(grouping: existingItems, by: { calendar.startOfDay(for: $0.date) })
                .mapValues { $0.first! } // Assume uniqueness by day
            
            // 2. Iterate memory items
            for item in healthSummaries {
                let dateKey = calendar.startOfDay(for: item.date)
                if let existing = existingMap[dateKey] {
                    // Update
                    existing.update(from: item)
                    existingMap.removeValue(forKey: dateKey)
                } else {
                    // Insert
                    let newItem = SDHealthSummary(domain: item)
                    modelContext.insert(newItem)
                }
            }
            
            // 3. Delete remaining (orphaned) items
            // Health data usually isn't deleted, but if it was removed from memory, we sync that.
            for orphaned in existingMap.values {
                modelContext.delete(orphaned)
            }
            
            try? modelContext.save()
        }
    }
    
    /// 指定日の天気データを更新
    func updateWeather(for date: Date, condition: String, high: Double?, low: Double?) {
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)
        
        if let index = healthSummaries.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: targetDate) }) {
            healthSummaries[index].weatherCondition = condition
            healthSummaries[index].highTemperature = high
            healthSummaries[index].lowTemperature = low
        } else {
            var summary = HealthSummary(date: targetDate)
            summary.weatherCondition = condition
            summary.highTemperature = high
            summary.lowTemperature = low
            healthSummaries.append(summary)
            healthSummaries.sort { $0.date > $1.date }
        }
        persistHealthSummaries()
    }

    // MARK: - Calendar

    func events(on date: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        
        // キャッシュチェック
        if let cached = eventsCache[dayStart] {
            return cached
        }
        
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let result = (calendarEvents + externalCalendarEvents)
            .filter { event in
                event.startDate < dayEnd && event.endDate > dayStart
            }
            .sorted(by: { $0.startDate < $1.startDate })
        
        // キャッシュに保存
        eventsCache[dayStart] = result
        return result
    }

    func addCalendarEvent(_ event: CalendarEvent) {
        eventsCache.removeAll()
        calendarEvents.append(event)
        persistCalendarEvents()
        scheduleEventNotification(event)
        rescheduleTodayOverviewReminderIfNeeded()
    }

    func updateCalendarEvent(_ event: CalendarEvent) {
        eventsCache.removeAll()
        guard let index = calendarEvents.firstIndex(where: { $0.id == event.id }) else { return }
        calendarEvents[index] = event
        persistCalendarEvents()
        scheduleEventNotification(event)
        rescheduleTodayOverviewReminderIfNeeded()
    }

    func deleteCalendarEvent(_ eventID: UUID) {
        eventsCache.removeAll()
        calendarEvents.removeAll { $0.id == eventID }
        persistCalendarEvents()
        NotificationService.shared.cancelEventReminder(eventId: eventID)
        rescheduleTodayOverviewReminderIfNeeded()
    }

    func updateExternalCalendarEvents(_ events: [CalendarEvent], range: ExternalCalendarRange? = nil) {
        eventsCache.removeAll()
        externalCalendarEvents = events
        if let range {
            externalCalendarRange = range
            persistExternalCalendarRange()
        }
        persistExternalCalendarEvents()
        rescheduleExternalEventNotifications()
        rescheduleTodayOverviewReminderIfNeeded()
    }

    func currentExternalCalendarRange() -> ExternalCalendarRange? {
        externalCalendarRange
    }

    @discardableResult
    func syncExternalCalendarsIfAuthorized(
        requestPermissionIfNeeded: Bool = false,
        anchorDate: Date = Date()
    ) async -> Bool {
        let calendarService = CalendarEventService()
        let granted = await calendarService.requestAccessIfNeeded(shouldPrompt: requestPermissionIfNeeded)
        guard granted else { return false }

        calendarService.refreshCalendarLinks(store: self)
        let range = currentExternalCalendarRange() ?? defaultExternalCalendarRange(for: anchorDate)

        do {
            let ekEvents = try await calendarService.fetchEvents(from: range.start, to: range.end)
            let external = mapExternalEvents(from: ekEvents)
            updateExternalCalendarEvents(external, range: range)
            updateLastCalendarSync(date: Date())
            return true
        } catch {
            return false
        }
    }

    var lastCalendarSyncDate: Date? {
        appState.lastCalendarSyncDate
    }

    func updateLastCalendarSync(date: Date) {
        appState.lastCalendarSyncDate = date
        persistAppState()
    }

    func updateCalendarLinks(with calendars: [EKCalendar]) {
        var links = appState.calendarCategoryLinks
        for calendar in calendars {
            let colorHex = calendar.cgColor?.hexString
            if let index = links.firstIndex(where: { $0.calendarIdentifier == calendar.calendarIdentifier }) {
                links[index].calendarTitle = calendar.title
                links[index].colorHex = colorHex
            } else {
                // Auto-map category based on calendar name
                let autoCategory = autoMapCategory(for: calendar.title)
                let link = CalendarCategoryLink(calendarIdentifier: calendar.calendarIdentifier,
                                                calendarTitle: calendar.title,
                                                categoryId: autoCategory,
                                                colorHex: colorHex)
                links.append(link)
            }
        }
        appState.calendarCategoryLinks = links
        persistAppState()
    }

    private func defaultExternalCalendarRange(for anchor: Date) -> ExternalCalendarRange {
        let calendar = Calendar.current
        let anchorMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)) ?? anchor
        let start = calendar.date(byAdding: .month, value: -6, to: anchorMonth) ?? anchorMonth
        let endMonthStart = calendar.date(byAdding: .month, value: 19, to: anchorMonth) ?? anchorMonth
        let end = calendar.date(byAdding: .second, value: -1, to: endMonthStart) ?? endMonthStart
        return ExternalCalendarRange(start: start, end: end)
    }

    private func mapExternalEvents(from ekEvents: [EKEvent]) -> [CalendarEvent] {
        let links = appState.calendarCategoryLinks
        let linkMap = Dictionary(uniqueKeysWithValues: links.map { ($0.calendarIdentifier, $0) })
        let defaultCategory = CategoryPalette.defaultCategoryName

        return ekEvents.compactMap { event in
            let identifier = event.calendar.calendarIdentifier
            if let link = linkMap[identifier] {
                guard let category = link.categoryId else { return nil }
                return CalendarEvent(event: event, categoryName: category)
            }
            return CalendarEvent(event: event, categoryName: defaultCategory)
        }
    }
    
    /// Auto-map calendar name to category based on keywords
    private func autoMapCategory(for calendarName: String) -> String? {
        let name = calendarName.lowercased()
        
        // Hide holidays
        if name.contains("祝日") || name.contains("holiday") {
            return nil
        }
        
        // Work-related keywords
        let workKeywords = ["仕事", "work", "業務", "会社", "office", "ビジネス", "business", "ミーティング", "meeting"]
        for keyword in workKeywords {
            if name.contains(keyword) {
                return "仕事"
            }
        }
        
        // Travel-related keywords
        let travelKeywords = ["旅行", "travel", "trip", "vacation", "休暇"]
        for keyword in travelKeywords {
            if name.contains(keyword) {
                return "旅行"
            }
        }
        
        // Hobby-related keywords  
        let hobbyKeywords = ["趣味", "hobby", "プライベート", "private", "個人", "personal"]
        for keyword in hobbyKeywords {
            if name.contains(keyword) {
                return "趣味"
            }
        }
        
        // Default: use the default category
        return CategoryPalette.defaultCategoryName
    }

    func updateCalendarLinkCategory(calendarIdentifier: String, categoryName: String?) {
        guard let index = appState.calendarCategoryLinks.firstIndex(where: { $0.calendarIdentifier == calendarIdentifier }) else {
            return
        }
        appState.calendarCategoryLinks[index].categoryId = categoryName
        persistAppState()
    }

    func renameCalendarCategory(from oldName: String, to newName: String) {
        let source = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard source.isEmpty == false, target.isEmpty == false, source != target else { return }

        eventsCache.removeAll()

        var hasInternalChanges = false
        for index in calendarEvents.indices where calendarEvents[index].calendarName == source {
            calendarEvents[index].calendarName = target
            hasInternalChanges = true
        }
        if hasInternalChanges {
            persistCalendarEvents()
        }

        var hasExternalChanges = false
        for index in externalCalendarEvents.indices where externalCalendarEvents[index].calendarName == source {
            externalCalendarEvents[index].calendarName = target
            hasExternalChanges = true
        }
        if hasExternalChanges {
            persistExternalCalendarEvents()
        }

        var hasLinkChanges = false
        for index in appState.calendarCategoryLinks.indices where appState.calendarCategoryLinks[index].categoryId == source {
            appState.calendarCategoryLinks[index].categoryId = target
            hasLinkChanges = true
        }
        if hasLinkChanges {
            persistAppState()
        }

        NotificationSettingsManager.shared.renameCategorySetting(oldName: source, newName: target)
        reapplyEventCategoryNotificationSettings()
    }

    func reapplyEventCategoryNotificationSettings() {
        let categories = Set((calendarEvents + externalCalendarEvents).map(\.calendarName))
        _ = NotificationSettingsManager.shared.ensureCategorySettings(for: Array(categories))

        for event in calendarEvents {
            scheduleEventNotification(event)
        }
        rescheduleExternalEventNotifications()
    }

    func reapplyEventCategoryNotificationSettings(
        previousSettings: [CategoryNotificationSetting],
        currentSettings: [CategoryNotificationSetting],
        previousParentEnabled: Bool,
        parentEnabled: Bool
    ) {
        let previousMap = Dictionary(uniqueKeysWithValues: previousSettings.map { ($0.categoryName, $0) })
        let currentMap = Dictionary(uniqueKeysWithValues: currentSettings.map { ($0.categoryName, $0) })

        var hasEventChanges = false

        for index in calendarEvents.indices {
            let event = calendarEvents[index]
            let previousSetting = previousMap[event.calendarName]
            let currentSetting = currentMap[event.calendarName]
            let previousDefault = previousParentEnabled
                ? eventCategoryDefaultReminderStrategy(for: event, setting: previousSetting)
                : nil
            let currentDefault = parentEnabled
                ? eventCategoryDefaultReminderStrategy(for: event, setting: currentSetting)
                : nil

            let explicitStrategy = explicitReminderStrategy(for: event)

            // 旧デフォルト由来の通知だけを追従更新し、個別変更は維持する
            guard reminderStrategy(explicitStrategy, matches: previousDefault) else {
                continue
            }

            if reminderStrategy(explicitStrategy, matches: currentDefault) {
                continue
            }

            applyReminderStrategy(currentDefault, to: &calendarEvents[index])
            hasEventChanges = true
        }

        if hasEventChanges {
            persistCalendarEvents()
        }

        reapplyEventCategoryNotificationSettings()
    }

    func reapplyTaskPriorityNotificationSettings(
        previousSettings: [PriorityNotificationSetting],
        currentSettings: [PriorityNotificationSetting],
        previousParentEnabled: Bool,
        parentEnabled: Bool
    ) {
        let previousMap = Dictionary(uniqueKeysWithValues: previousSettings.map { ($0.priority, $0) })
        let currentMap = Dictionary(uniqueKeysWithValues: currentSettings.map { ($0.priority, $0) })

        var changedTaskIDs: [UUID] = []

        for index in tasks.indices {
            let task = tasks[index]
            let priorityKey = task.priority.rawValue
            let previousSetting = previousMap[priorityKey]
            let currentSetting = currentMap[priorityKey]

            let previousDefault = previousParentEnabled
                ? taskPriorityDefaultReminderDate(for: task, setting: previousSetting)
                : nil
            let currentDefault = parentEnabled
                ? taskPriorityDefaultReminderDate(for: task, setting: currentSetting)
                : nil

            // 旧デフォルト由来の通知だけを追従更新し、個別変更は維持する
            guard reminderDate(tasks[index].reminderDate, matches: previousDefault) else {
                continue
            }

            if reminderDate(tasks[index].reminderDate, matches: currentDefault) {
                continue
            }

            tasks[index].reminderDate = currentDefault
            changedTaskIDs.append(tasks[index].id)
            scheduleTaskNotification(tasks[index])
        }

        guard changedTaskIDs.isEmpty == false else { return }

        persistTasks()
        for taskID in changedTaskIDs {
            let descriptor = FetchDescriptor<SDTask>(predicate: #Predicate { $0.id == taskID })
            if let existing = try? modelContext.fetch(descriptor).first,
               let task = tasks.first(where: { $0.id == taskID }) {
                existing.reminderDate = task.reminderDate
            }
        }
        try? modelContext.save()
    }

    // MARK: - Task CRUD

    func addTask(_ task: Task) {
        tasks.append(task)
        persistTasks()
        
        let sdTask = SDTask(domain: task)
        modelContext.insert(sdTask)
        try? modelContext.save()
        
        scheduleTaskNotification(task)
        rescheduleTodayOverviewReminderIfNeeded()
    }

    func updateTask(_ task: Task) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
        persistTasks()
        
        let taskID = task.id
        let descriptor = FetchDescriptor<SDTask>(predicate: #Predicate { $0.id == taskID })
        if let existing = try? modelContext.fetch(descriptor).first {
             existing.update(from: task)
             try? modelContext.save()
        }
        
        scheduleTaskNotification(task)
        rescheduleTodayOverviewReminderIfNeeded()
    }

    func deleteTasks(at offsets: IndexSet) {
        let idsToDelete = offsets.compactMap { index -> UUID? in
            guard tasks.indices.contains(index) else { return nil }
            return tasks[index].id
        }
        
        for index in offsets.sorted(by: >) where tasks.indices.contains(index) {
            NotificationService.shared.cancelTaskReminder(taskId: tasks[index].id)
            tasks.remove(at: index)
        }
        persistTasks()
        
        for id in idsToDelete {
             let descriptor = FetchDescriptor<SDTask>(predicate: #Predicate { $0.id == id })
             if let existing = try? modelContext.fetch(descriptor).first {
                 modelContext.delete(existing)
             }
        }
        try? modelContext.save()
        rescheduleTodayOverviewReminderIfNeeded()
    }

    func deleteTasks(withIDs ids: [UUID]) {
        for id in ids {
            NotificationService.shared.cancelTaskReminder(taskId: id)
        }
        tasks.removeAll { ids.contains($0.id) }
        persistTasks()
        
        for id in ids {
             let descriptor = FetchDescriptor<SDTask>(predicate: #Predicate { $0.id == id })
             if let existing = try? modelContext.fetch(descriptor).first {
                 modelContext.delete(existing)
             }
        }
        try? modelContext.save()
        rescheduleTodayOverviewReminderIfNeeded()
    }

    func toggleTaskCompletion(_ taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].isCompleted.toggle()
        // Set completedAt when completed, clear when uncompleted
        tasks[index].completedAt = tasks[index].isCompleted ? Date() : nil
        persistTasks()
        
        let descriptor = FetchDescriptor<SDTask>(predicate: #Predicate { $0.id == taskID })
        if let existing = try? modelContext.fetch(descriptor).first {
             existing.isCompleted = tasks[index].isCompleted
             existing.completedAt = tasks[index].completedAt
             try? modelContext.save()
        }
        rescheduleTodayOverviewReminderIfNeeded()
    }

    // MARK: - Diary CRUD

    func entry(for date: Date) -> DiaryEntry? {
        diaryEntries.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func upsert(entry: DiaryEntry, syncSwiftData: Bool = true) {
        let normalized = normalizeDiaryEntry(entry)
        if let index = diaryEntries.firstIndex(where: { $0.id == normalized.id }) {
            diaryEntries[index] = normalized
        } else {
            diaryEntries.append(normalized)
        }
        persistDiaryEntries()
        
        let isToday = Calendar.current.isDateInToday(entry.date)
        let hasContent = !normalized.text.isEmpty
        
        if isToday && diaryReminderEnabled && hasContent {
            NotificationService.shared.cancelDiaryReminder()
        }
        guard syncSwiftData else { return }
        syncDiaryEntryToSwiftData(normalized)
        try? modelContext.save()
    }
    
    // MARK: - Location Visit Tags
    
    func createLocationVisitTag(named rawName: String) throws -> LocationVisitTagDefinition {
        let name = try validatedLocationVisitTagName(rawName)
        let definition = LocationVisitTagDefinition(name: name,
                                                    sortOrder: locationVisitTagDefinitions.count)
        locationVisitTagDefinitions.append(definition)
        persistLocationVisitTags()
        return definition
    }
    
    func renameLocationVisitTag(id: UUID, to rawName: String) throws {
        guard let index = locationVisitTagDefinitions.firstIndex(where: { $0.id == id }) else {
            throw LocationVisitTagError.tagNotFound
        }
        let newName = try validatedLocationVisitTagName(rawName, excluding: id)
        let oldName = locationVisitTagDefinitions[index].name
        guard isSameTagName(oldName, newName) == false else { return }
        locationVisitTagDefinitions[index].name = newName
        persistLocationVisitTags()
        
        let changedEntries = applyVisitTagMutation { tags in
            var didChange = false
            for i in tags.indices where isSameTagName(tags[i], oldName) {
                tags[i] = newName
                didChange = true
            }
            return didChange
        }
        syncDiaryEntriesToSwiftData(changedEntries)
    }
    
    @discardableResult
    func deleteLocationVisitTag(id: UUID) -> Int {
        guard let index = locationVisitTagDefinitions.firstIndex(where: { $0.id == id }) else {
            return 0
        }
        let deletedName = locationVisitTagDefinitions[index].name
        locationVisitTagDefinitions.remove(at: index)
        normalizeLocationVisitTagOrderIfNeeded()
        persistLocationVisitTags()
        
        var affectedVisitCount = 0
        let changedEntries = applyVisitTagMutation { tags in
            let before = tags.count
            tags.removeAll { isSameTagName($0, deletedName) }
            if tags.count != before {
                affectedVisitCount += 1
                return true
            }
            return false
        }
        syncDiaryEntriesToSwiftData(changedEntries)
        return affectedVisitCount
    }
    
    func moveLocationVisitTag(from source: IndexSet, to destination: Int) {
        locationVisitTagDefinitions.move(fromOffsets: source, toOffset: destination)
        normalizeLocationVisitTagOrderIfNeeded()
        persistLocationVisitTags()
    }
    
    @discardableResult
    func reAddDefaultLocationVisitTags() -> Int {
        var addedCount = 0
        for name in Self.defaultLocationVisitTagNames where containsLocationVisitTag(named: name) == false {
            let definition = LocationVisitTagDefinition(name: name,
                                                        sortOrder: locationVisitTagDefinitions.count)
            locationVisitTagDefinitions.append(definition)
            addedCount += 1
        }
        if addedCount > 0 {
            normalizeLocationVisitTagOrderIfNeeded()
            persistLocationVisitTags()
        }
        return addedCount
    }

    // MARK: - Habits

    func records(for date: Date) -> [HabitRecord] {
        habitRecords.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func toggleHabit(_ habitID: UUID, on date: Date) {
        let calendar = Calendar.current
        let dateDay = calendar.startOfDay(for: date)
        
        // Check streak before toggling
        let streakBefore = calculateCurrentStreak(for: habitID, upTo: date)
        var isCompleting = true
        
        if let index = habitRecords.firstIndex(where: {
            $0.habitID == habitID && Calendar.current.isDate($0.date, inSameDayAs: date)
        }) {
            isCompleting = !habitRecords[index].isCompleted
            habitRecords[index].isCompleted.toggle()
            // If toggling to completed and date is before createdAt, update createdAt
            if habitRecords[index].isCompleted, let habitIndex = habits.firstIndex(where: { $0.id == habitID }) {
                let createdDay = calendar.startOfDay(for: habits[habitIndex].createdAt)
                if dateDay < createdDay {
                    habits[habitIndex].createdAt = dateDay
                    persistHabits()
                }
            }
        } else {
            let record = HabitRecord(habitID: habitID, date: date, isCompleted: true)
            habitRecords.append(record)
            // New record is completed, check if we need to update createdAt
            if let habitIndex = habits.firstIndex(where: { $0.id == habitID }) {
                let createdDay = calendar.startOfDay(for: habits[habitIndex].createdAt)
                if dateDay < createdDay {
                    habits[habitIndex].createdAt = dateDay
                    persistHabits()
                }
            }
        }
        persistHabitRecords()

        // Switch execution to non-UI blocking task if possible, but for data safety we do it here
        // Mirror to SwiftData
        if let updatedRecord = habitRecords.first(where: { $0.habitID == habitID && Calendar.current.isDate($0.date, inSameDayAs: date) }) {
             let recordID = updatedRecord.id
             let desc = FetchDescriptor<SDHabitRecord>(predicate: #Predicate { $0.id == recordID })
             if let existingRecord = try? modelContext.fetch(desc).first {
                 existingRecord.isCompleted = updatedRecord.isCompleted
             } else {
                 let newRecord = SDHabitRecord(domain: updatedRecord)
                 modelContext.insert(newRecord)
             }
        }
        
        // Sync Habit.createdAt if changed
        if let memoryHabit = habits.first(where: { $0.id == habitID }) {
            let habitID = memoryHabit.id
            let habitDesc = FetchDescriptor<SDHabit>(predicate: #Predicate { $0.id == habitID })
            if let sdHabit = try? modelContext.fetch(habitDesc).first {
                if sdHabit.createdAt != memoryHabit.createdAt {
                    sdHabit.createdAt = memoryHabit.createdAt
                }
            }
        }
        try? modelContext.save()
        reloadHabitWidgetTimeline()
        
        // Haptic feedback
        if isCompleting {
            let streakAfter = calculateCurrentStreak(for: habitID, upTo: date)
            if streakAfter > streakBefore && streakAfter >= 3 {
                // 3日以上の連続達成更新時は特別なハプティック
                HapticManager.streak()
                // 3日以上連続達成でポジティブアクションとして記録
                ReviewRequestManager.shared.registerPositiveAction()
                
                // ストリークマイルストーン達成時にトースト表示
                showStreakMilestoneToast(streak: streakAfter)
            } else {
                HapticManager.success()
            }
            
            // 全習慣達成チェック
            checkAllHabitsComplete(on: date)
        } else {
            HapticManager.light()
        }
    }
    
    /// ストリークマイルストーン達成時にトーストを表示
    private func showStreakMilestoneToast(streak: Int) {
        let milestones: [(days: Int, emoji: String, message: String, nextLabel: String?)] = [
            (365, "🌟", "1年達成！おめでとう！", nil),
            (200, "🎖️", "200日連続！レジェンド！", "次は365日！"),
            (100, "👑", "100日突破！", "次は200日！"),
            (50, "🏆", "50日連続達成！", "次は100日！"),
            (30, "🔥", "1ヶ月連続達成！", "次は50日！"),
            (21, "🔥", "3週間連続達成！", "次は30日！"),
            (14, "🔥", "2週間連続達成！", "次は21日！"),
            (7, "✨", "1週間連続達成！", "次は14日！"),
            (3, "💪", "3日連続達成！", "次は7日！")
        ]
        
        for milestone in milestones {
            if streak == milestone.days {
                var fullMessage = milestone.message
                if let next = milestone.nextLabel {
                    fullMessage += "\n\(next)"
                }
                ToastManager.shared.show(emoji: milestone.emoji, message: fullMessage)
                break
            }
        }
    }
    
    private func calculateCurrentStreak(for habitID: UUID, upTo date: Date) -> Int {
        let calendar = Calendar.current
        var streakCount = 0
        var currentDate = calendar.startOfDay(for: date)
        
        while true {
            let isCompleted = habitRecords.contains {
                $0.habitID == habitID &&
                calendar.isDate($0.date, inSameDayAs: currentDate) &&
                $0.isCompleted
            }
            
            if isCompleted {
                streakCount += 1
            } else {
                break
            }
            
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate) else { break }
            currentDate = previousDay
        }
        
        return streakCount
    }
    
    private func checkAllHabitsComplete(on date: Date) {
        let calendar = Calendar.current
        let activeHabits = habits.filter { !$0.isArchived && $0.schedule.isActive(on: date) }
        guard !activeHabits.isEmpty else { return }
        
        let allComplete = activeHabits.allSatisfy { habit in
            habitRecords.contains {
                $0.habitID == habit.id &&
                calendar.isDate($0.date, inSameDayAs: date) &&
                $0.isCompleted
            }
        }
        
        if allComplete {
            HapticManager.allHabitsComplete()
        }
    }

    func setHabitCompletion(_ habitID: UUID, on date: Date, completed: Bool) {
        let calendar = Calendar.current
        let dateDay = calendar.startOfDay(for: date)
        
        // If completing a habit on a date, potentially update the habit's createdAt
        if completed, let habitIndex = habits.firstIndex(where: { $0.id == habitID }) {
            let createdDay = calendar.startOfDay(for: habits[habitIndex].createdAt)
            if dateDay < createdDay {
                habits[habitIndex].createdAt = dateDay
                persistHabits()
            }
        }
        
        if let index = habitRecords.firstIndex(where: {
            $0.habitID == habitID && Calendar.current.isDate($0.date, inSameDayAs: date)
        }) {
            habitRecords[index].isCompleted = completed
        } else if completed {
            let record = HabitRecord(habitID: habitID, date: date, isCompleted: true)
            habitRecords.append(record)
        }
        persistHabitRecords()
        
        // Mirror to SwiftData
        if let updatedRecord = habitRecords.first(where: { $0.habitID == habitID && Calendar.current.isDate($0.date, inSameDayAs: date) }) {
             let recordID = updatedRecord.id
             let desc = FetchDescriptor<SDHabitRecord>(predicate: #Predicate { $0.id == recordID })
             if let existingRecord = try? modelContext.fetch(desc).first {
                 existingRecord.isCompleted = updatedRecord.isCompleted
             } else {
                 let newRecord = SDHabitRecord(domain: updatedRecord)
                 modelContext.insert(newRecord)
             }
        }
        if let memoryHabit = habits.first(where: { $0.id == habitID }) {
            let habitID = memoryHabit.id
            let habitDesc = FetchDescriptor<SDHabit>(predicate: #Predicate { $0.id == habitID })
            if let sdHabit = try? modelContext.fetch(habitDesc).first {
                if sdHabit.createdAt != memoryHabit.createdAt {
                     sdHabit.createdAt = memoryHabit.createdAt
                }
            }
        }
        try? modelContext.save()
        reloadHabitWidgetTimeline()
    }

    func addHabit(_ habit: Habit) {
        let newIndex = habits.count
        habits.append(habit)
        persistHabits()
        
        let sdHabit = SDHabit(domain: habit)
        sdHabit.orderIndex = newIndex
        modelContext.insert(sdHabit)
        try? modelContext.save()
        reloadHabitWidgetTimeline()
    }

    func updateHabit(_ habit: Habit) {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        habits[index] = habit
        persistHabits()
        
        let habitID = habit.id
        let descriptor = FetchDescriptor<SDHabit>(predicate: #Predicate { $0.id == habitID })
        if let existing = try? modelContext.fetch(descriptor).first {
             existing.update(from: habit)
             try? modelContext.save()
        }
        reloadHabitWidgetTimeline()
    }

    func deleteHabit(_ habitID: UUID) {
        // Soft delete: archive the habit instead of removing it
        guard let index = habits.firstIndex(where: { $0.id == habitID }) else { return }
        habits[index].isArchived = true
        habits[index].archivedAt = Date()
        persistHabits()
        
        let descriptor = FetchDescriptor<SDHabit>(predicate: #Predicate { $0.id == habitID })
        if let existing = try? modelContext.fetch(descriptor).first {
             existing.isArchived = true
             existing.archivedAt = habits[index].archivedAt
             try? modelContext.save()
        }
        reloadHabitWidgetTimeline()
    }
    
    func moveHabit(from source: IndexSet, to destination: Int) {
        habits.move(fromOffsets: source, toOffset: destination)
        persistHabits()
        
        // Update SwiftData order
        for (index, habit) in habits.enumerated() {
             let id = habit.id
             let descriptor = FetchDescriptor<SDHabit>(predicate: #Predicate { $0.id == id })
             if let existing = try? modelContext.fetch(descriptor).first {
                 if existing.orderIndex != index {
                     existing.orderIndex = index
                 }
             }
        }
        try? modelContext.save()
        reloadHabitWidgetTimeline()
    }

    // MARK: - Anniversaries

    func addAnniversary(_ anniversary: Anniversary) {
        let newIndex = anniversaries.count
        anniversaries.append(anniversary)
        persistAnniversaries()
        scheduleAnniversaryNotification(anniversary)
        
        let sdItem = SDAnniversary(domain: anniversary)
        sdItem.orderIndex = newIndex
        modelContext.insert(sdItem)
        try? modelContext.save()
        reloadAnniversaryWidgetTimeline()
    }

    func updateAnniversary(_ anniversary: Anniversary) {
        guard let index = anniversaries.firstIndex(where: { $0.id == anniversary.id }) else { return }
        anniversaries[index] = anniversary
        persistAnniversaries()
        scheduleAnniversaryNotification(anniversary)
        
        let id = anniversary.id
        let descriptor = FetchDescriptor<SDAnniversary>(predicate: #Predicate { $0.id == id })
        if let existing = try? modelContext.fetch(descriptor).first {
             existing.update(from: anniversary)
             try? modelContext.save()
        }
        reloadAnniversaryWidgetTimeline()
    }

    func deleteAnniversary(_ anniversaryID: UUID) {
        anniversaries.removeAll { $0.id == anniversaryID }
        persistAnniversaries()
        NotificationService.shared.cancelAnniversaryReminder(anniversaryId: anniversaryID)
        
        let descriptor = FetchDescriptor<SDAnniversary>(predicate: #Predicate { $0.id == anniversaryID })
        if let existing = try? modelContext.fetch(descriptor).first {
             modelContext.delete(existing)
             try? modelContext.save()
        }
        reloadAnniversaryWidgetTimeline()
    }
    
    func moveAnniversary(from source: IndexSet, to destination: Int) {
        anniversaries.move(fromOffsets: source, toOffset: destination)
        persistAnniversaries()
        
        for (index, item) in anniversaries.enumerated() {
             let id = item.id
             let descriptor = FetchDescriptor<SDAnniversary>(predicate: #Predicate { $0.id == id })
             if let existing = try? modelContext.fetch(descriptor).first {
                 if existing.orderIndex != index {
                     existing.orderIndex = index
                 }
             }
        }
        try? modelContext.save()
        reloadAnniversaryWidgetTimeline()
    }

    // MARK: - Memo Pad

    func updateMemoPad(text: String, syncSwiftData: Bool = true) {
        if text != memoPad.text {
            memoPad.text = text
            memoPad.lastUpdatedAt = Date()
        } else {
            guard syncSwiftData else { return }
        }
        persistMemoPad(syncSwiftData: syncSwiftData)
    }

    private static func loadMemoPad() -> MemoPad {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: memoPadDefaultsKey),
           let memo = try? JSONDecoder().decode(MemoPad.self, from: data) {
            return memo
        }
        return MemoPad()
    }

    private func persistMemoPad(syncSwiftData: Bool = true) {
        if let data = try? JSONEncoder().encode(memoPad) {
            UserDefaults.standard.set(data, forKey: Self.memoPadDefaultsKey)
        }
        guard syncSwiftData else { return }
        
        // SwiftData
        let descriptor = FetchDescriptor<SDMemoPad>()
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.text = memoPad.text
            existing.lastUpdatedAt = memoPad.lastUpdatedAt
        } else {
             let newPad = SDMemoPad(text: memoPad.text, lastUpdatedAt: memoPad.lastUpdatedAt)
             modelContext.insert(newPad)
        }
        try? modelContext.save()
    }

    // MARK: - App State

    private static func loadAppState() -> AppState {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: appStateDefaultsKey),
           let state = try? JSONDecoder().decode(AppState.self, from: data) {
            return state
        }
        return AppState()
    }

    private func persistAppState() {
        if let data = try? JSONEncoder().encode(appState) {
            UserDefaults.standard.set(data, forKey: Self.appStateDefaultsKey)
        }
        
        // SwiftData
        let descriptor = FetchDescriptor<SDAppState>()
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.lastCalendarSyncDate = appState.lastCalendarSyncDate
            existing.calendarCategoryLinks = appState.calendarCategoryLinks
            existing.diaryReminderEnabled = appState.diaryReminderEnabled
            existing.diaryReminderHour = appState.diaryReminderHour
            existing.diaryReminderMinute = appState.diaryReminderMinute
        } else {
             let newState = SDAppState(
                lastCalendarSyncDate: appState.lastCalendarSyncDate,
                calendarCategoryLinks: appState.calendarCategoryLinks,
                diaryReminderEnabled: appState.diaryReminderEnabled,
                diaryReminderHour: appState.diaryReminderHour,
                diaryReminderMinute: appState.diaryReminderMinute
             )
             modelContext.insert(newState)
        }
        try? modelContext.save()
    }

    // MARK: - Diary Reminder Settings

    var diaryReminderEnabled: Bool { appState.diaryReminderEnabled }
    var diaryReminderHour: Int { appState.diaryReminderHour }
    var diaryReminderMinute: Int { appState.diaryReminderMinute }

    func updateDiaryReminder(enabled: Bool, hour: Int, minute: Int) {
        appState.diaryReminderEnabled = enabled
        appState.diaryReminderHour = hour
        appState.diaryReminderMinute = minute
        persistAppState()
        
        if enabled {
            NotificationService.shared.scheduleDiaryReminder(hour: hour, minute: minute)
        } else {
            NotificationService.shared.cancelDiaryReminder()
        }
    }

    /// アプリ起動時に日記リマインダーを再スケジュール（今日書いていなければ）
    func rescheduleDiaryReminderIfNeeded() {
        guard diaryReminderEnabled else { return }
        
        // 今日の日記があるかチェック
        let today = Date()
        let hasTodayEntry = diaryEntries.contains { entry in
            Calendar.current.isDate(entry.date, inSameDayAs: today) && !entry.text.isEmpty
        }
        
        if hasTodayEntry {
            // 今日書いてあれば翌日用にスケジュール
            NotificationService.shared.cancelDiaryReminder()
            // 翌日の通知をスケジュール
            let calendar = Calendar.current
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
               let targetDate = calendar.date(bySettingHour: diaryReminderHour, minute: diaryReminderMinute, second: 0, of: tomorrow) {
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: targetDate)
                scheduleDiaryReminderForDate(components: components)
            }
        } else {
            // 今日まだ書いていなければ通常スケジュール
            NotificationService.shared.scheduleDiaryReminder(hour: diaryReminderHour, minute: diaryReminderMinute)
        }
    }

    private func scheduleDiaryReminderForDate(components: DateComponents) {
        let content = UNMutableNotificationContent()
        content.title = "日記を書きましょう"
        content.body = "今日の出来事を振り返ってみませんか？"
        content.sound = .default
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "diary-daily-reminder", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("日記通知スケジュールエラー: \(error)")
            }
        }
    }

    // MARK: - 今日の予定・タスク通知設定

    private var todayOverviewNotificationEnabled: Bool {
        NotificationSettingsManager.shared.isTodayOverviewNotificationEnabled
    }

    private var todayOverviewNotificationHour: Int {
        NotificationSettingsManager.shared.todayOverviewNotificationHour
    }

    private var todayOverviewNotificationMinute: Int {
        NotificationSettingsManager.shared.todayOverviewNotificationMinute
    }

    func updateTodayOverviewReminder(enabled: Bool, hour: Int, minute: Int) {
        NotificationSettingsManager.shared.isTodayOverviewNotificationEnabled = enabled
        NotificationSettingsManager.shared.todayOverviewNotificationHour = hour
        NotificationSettingsManager.shared.todayOverviewNotificationMinute = minute
        rescheduleTodayOverviewReminderIfNeeded()
    }

    func rescheduleTodayOverviewReminderIfNeeded(referenceDate: Date = Date()) {
        guard todayOverviewNotificationEnabled else {
            NotificationService.shared.cancelTodayOverviewReminder()
            return
        }

        let calendar = Calendar.current
        var fireDate = calendar.date(
            bySettingHour: todayOverviewNotificationHour,
            minute: todayOverviewNotificationMinute,
            second: 0,
            of: referenceDate
        ) ?? referenceDate

        if fireDate <= referenceDate {
            fireDate = calendar.date(byAdding: .day, value: 1, to: fireDate) ?? fireDate
        }

        let targetDate = calendar.startOfDay(for: fireDate)
        let targetEvents = events(on: targetDate)
        let targetTasks = tasks
            .filter { !$0.isCompleted && isTask($0, scheduledOn: targetDate) }
            .sorted(by: { lhs, rhs in
                if lhs.priority.rawValue != rhs.priority.rawValue {
                    return lhs.priority.rawValue > rhs.priority.rawValue
                }
                let lhsDate = lhs.startDate ?? lhs.endDate ?? .distantFuture
                let rhsDate = rhs.startDate ?? rhs.endDate ?? .distantFuture
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                return lhs.title < rhs.title
            })

        let body = todayOverviewBody(targetDate: targetDate, events: targetEvents, tasks: targetTasks)
        NotificationService.shared.scheduleTodayOverviewReminder(fireDate: fireDate, body: body)
    }

    private func todayOverviewBody(targetDate: Date, events: [CalendarEvent], tasks: [Task]) -> String {
        let eventLines = summarizedEventLines(events, on: targetDate, limit: 3)
        let taskLines = summarizedTaskLines(tasks, limit: 3)
        return [
            "予定",
            eventLines.joined(separator: "\n"),
            "タスク",
            taskLines.joined(separator: "\n")
        ].joined(separator: "\n")
    }

    private func summarizedEventLines(_ events: [CalendarEvent], on date: Date, limit: Int) -> [String] {
        let normalizedEvents = events.compactMap { event -> CalendarEvent? in
            let normalizedTitle = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalizedTitle.isEmpty == false else { return nil }
            var normalizedEvent = event
            normalizedEvent.title = normalizedTitle
            return normalizedEvent
        }

        guard normalizedEvents.isEmpty == false else {
            return ["なし"]
        }

        let listedLines = Array(normalizedEvents.prefix(limit)).map { event in
            todayOverviewEventLine(for: event, on: date)
        }
        let remainderCount = normalizedEvents.count - listedLines.count
        if remainderCount > 0 {
            return listedLines + ["ほか\(remainderCount)件"]
        }
        return listedLines
    }

    private func summarizedTaskLines(_ tasks: [Task], limit: Int) -> [String] {
        let normalizedTitles = tasks.map(\.title)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard normalizedTitles.isEmpty == false else {
            return ["なし"]
        }

        let listedLines = Array(normalizedTitles.prefix(limit)).map { "・\($0)" }
        let remainderCount = normalizedTitles.count - listedLines.count
        if remainderCount > 0 {
            return listedLines + ["ほか\(remainderCount)件"]
        }
        return listedLines
    }

    private func todayOverviewEventLine(for event: CalendarEvent, on date: Date) -> String {
        let calendar = Calendar.current
        let timeLabel: String
        if event.isAllDay {
            timeLabel = "終日"
        } else if calendar.isDate(event.startDate, inSameDayAs: date) {
            timeLabel = event.startDate.formattedTime()
        } else {
            timeLabel = "継続"
        }
        return "・\(timeLabel) \(event.title)"
    }

    // MARK: - Letter to the Future

    /// ホームに表示すべき手紙を取得
    /// - 開封可能（未開封）な手紙
    /// - または、開封済みだが配達日が今日の手紙
    /// - ただし、ユーザーが非表示にした場合は除く
    func deliverableLetters() -> [Letter] {
        return letters.filter { $0.shouldShowOnHome }
    }

    /// 今日届いた手紙（今日開封した or 今日配達された未開封）
    func todaysDeliveredLetters() -> [Letter] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return letters.filter { letter in
            let deliveryDay = calendar.startOfDay(for: letter.deliveryDate)
            let isDeliveredToday = deliveryDay == today
            let isDeliverableNow = letter.status == .sealed && Date() >= letter.deliveryDate
            let openedToday = letter.status == .opened && 
                              letter.openedAt.map { calendar.startOfDay(for: $0) == today } ?? false
            return (isDeliveredToday && isDeliverableNow) || openedToday
        }
    }

    func addLetter(_ letter: Letter) {
        letters.append(letter)
        
        let sdLetter = SDLetter(domain: letter)
        modelContext.insert(sdLetter)
        try? modelContext.save()
    }

    func updateLetter(_ letter: Letter) {
        guard let index = letters.firstIndex(where: { $0.id == letter.id }) else { return }
        letters[index] = letter
        
        let letterID = letter.id
        let descriptor = FetchDescriptor<SDLetter>(predicate: #Predicate { $0.id == letterID })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.update(from: letter)
            try? modelContext.save()
        }
    }
    
    func dismissLetterFromHome(_ letterID: UUID) {
        guard let index = letters.firstIndex(where: { $0.id == letterID }) else { return }
        letters[index].dismissFromHome()
        
        let descriptor = FetchDescriptor<SDLetter>(predicate: #Predicate { $0.id == letterID })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.update(from: letters[index])
            try? modelContext.save()
        }
    }

    func sealLetter(_ letterID: UUID) {
        guard let index = letters.firstIndex(where: { $0.id == letterID }) else { return }
        var letter = letters[index]
        letter.seal()
        letters[index] = letter
        
        let descriptor = FetchDescriptor<SDLetter>(predicate: #Predicate { $0.id == letterID })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.update(from: letter)
            try? modelContext.save()
        }
        
        // 通知をスケジュール
        scheduleLetterNotification(letter)
    }

    func openLetter(_ letterID: UUID) {
        guard let index = letters.firstIndex(where: { $0.id == letterID }) else { return }
        var letter = letters[index]
        letter.open()
        letters[index] = letter
        
        let descriptor = FetchDescriptor<SDLetter>(predicate: #Predicate { $0.id == letterID })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.update(from: letter)
            try? modelContext.save()
        }
        
        // 通知をキャンセル
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["letter-\(letterID.uuidString)"])
    }

    func deleteLetter(_ letterID: UUID) {
        letters.removeAll { $0.id == letterID }
        
        let descriptor = FetchDescriptor<SDLetter>(predicate: #Predicate { $0.id == letterID })
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            try? modelContext.save()
        }
        
        // 通知をキャンセル
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["letter-\(letterID.uuidString)"])
    }

    private func scheduleLetterNotification(_ letter: Letter) {
        guard letter.status == .sealed else { return }
        
        let content = UNMutableNotificationContent()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月d日"
        let dateString = formatter.string(from: letter.createdAt)
        
        content.title = "📨 手紙が届きました"
        content.body = "\(dateString)のあなたから手紙が届きました"
        content.sound = .default
        content.userInfo = ["letterID": letter.id.uuidString]
        
        let triggerDate = letter.deliveryDate
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(identifier: "letter-\(letter.id.uuidString)", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("手紙通知スケジュールエラー: \(error)")
            }
        }
    }

    // MARK: - Shared Letter (他ユーザーからの手紙)

    func addSharedLetter(_ letter: SharedLetter) {
        // 重複チェック
        guard !sharedLetters.contains(where: { $0.id == letter.id }) else {
            print("⚠️ 共有手紙は既に保存済み: \(letter.id)")
            return
        }
        
        sharedLetters.insert(letter, at: 0)  // 新しい順にソート
        
        let sdLetter = SDSharedLetter(domain: letter)
        modelContext.insert(sdLetter)
        try? modelContext.save()
        
        print("✅ 共有手紙をローカルに保存: \(letter.id)")
    }

    func deleteSharedLetter(_ letterID: String) {
        sharedLetters.removeAll { $0.id == letterID }
        
        let descriptor = FetchDescriptor<SDSharedLetter>(predicate: #Predicate { $0.id == letterID })
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            try? modelContext.save()
        }
        
        // 写真も削除
        deleteSharedLetterPhotos(letterID: letterID)
        
        print("✅ 共有手紙を削除: \(letterID)")
    }

    private func deleteSharedLetterPhotos(letterID: String) {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let letterDir = documentsDir.appendingPathComponent("SharedLetterPhotos/\(letterID)")
        try? FileManager.default.removeItem(at: letterDir)
    }

    private static func loadValue<T: Decodable>(forKey key: String, defaultValue: T) -> T {
        // Use Shared Defaults if possible
        let defaults = UserDefaults(suiteName: PersistenceController.appGroupIdentifier) ?? UserDefaults.standard
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(T.self, from: data) {
            return decoded
        }
        return defaultValue
    }

    private static func hasStoredUserDefaultsFootprintForInitialPermissions(includeAutoSeededKeys: Bool) -> Bool {
        var keys = [
            tasksDefaultsKey,
            diaryDefaultsKey,
            habitsDefaultsKey,
            habitRecordsDefaultsKey,
            anniversariesDefaultsKey,
            calendarEventsDefaultsKey,
            externalCalendarEventsDefaultsKey,
            externalCalendarRangeDefaultsKey,
            memoPadDefaultsKey,
            appStateDefaultsKey,
            healthSummariesDefaultsKey
        ]
        if includeAutoSeededKeys {
            keys.append(contentsOf: [
                locationVisitTagsDefaultsKey,
                locationVisitTagsSeededDefaultsKey
            ])
        }

        let sharedDefaults = UserDefaults(suiteName: PersistenceController.appGroupIdentifier)
        return keys.contains { key in
            sharedDefaults?.object(forKey: key) != nil || UserDefaults.standard.object(forKey: key) != nil
        }
    }

    static func normalizeDiaryEntries(_ entries: [DiaryEntry]) -> [DiaryEntry] {
        entries.map { entry in
            var normalized = entry
            normalized.mood = normalized.mood ?? .neutral
            normalized.conditionScore = normalized.conditionScore ?? 3
            for index in normalized.locations.indices {
                normalized.locations[index].visitTags = Self.normalizedVisitTags(normalized.locations[index].visitTags)
            }
            return normalized
        }
    }
    
    private func normalizeDiaryEntry(_ entry: DiaryEntry) -> DiaryEntry {
        var normalized = entry
        normalized.mood = normalized.mood ?? .neutral
        normalized.conditionScore = normalized.conditionScore ?? 3
        for index in normalized.locations.indices {
            normalized.locations[index].visitTags = Self.normalizedVisitTags(normalized.locations[index].visitTags)
        }
        return normalized
    }
    
    private static func normalizedTagKey(_ rawName: String) -> String {
        rawName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
    
    private static func normalizedVisitTags(_ tags: [String],
                                            limit: Int? = nil) -> [String] {
        let maxAllowedTags = limit ?? maxLocationVisitTagsPerVisit
        var seen: Set<String> = []
        var normalized: [String] = []
        for raw in tags {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            let key = normalizedTagKey(trimmed)
            guard seen.contains(key) == false else { continue }
            seen.insert(key)
            normalized.append(trimmed)
            if normalized.count >= maxAllowedTags {
                break
            }
        }
        return normalized
    }
    
    private func syncDiaryEntryToSwiftData(_ entry: DiaryEntry) {
        let entryID = entry.id
        let descriptor = FetchDescriptor<SDDiaryEntry>(predicate: #Predicate { $0.id == entryID })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.update(from: entry)
        } else {
            let newItem = SDDiaryEntry(domain: entry)
            modelContext.insert(newItem)
        }
    }
    
    private func syncDiaryEntriesToSwiftData(_ entries: [DiaryEntry]) {
        guard entries.isEmpty == false else { return }
        for entry in entries {
            syncDiaryEntryToSwiftData(entry)
        }
        try? modelContext.save()
    }
    
    private func applyVisitTagMutation(_ mutate: (inout [String]) -> Bool) -> [DiaryEntry] {
        var changedEntries: [DiaryEntry] = []
        for entryIndex in diaryEntries.indices {
            var entryChanged = false
            for locationIndex in diaryEntries[entryIndex].locations.indices {
                var tags = diaryEntries[entryIndex].locations[locationIndex].visitTags
                guard mutate(&tags) else { continue }
                diaryEntries[entryIndex].locations[locationIndex].visitTags = Self.normalizedVisitTags(tags)
                entryChanged = true
            }
            if entryChanged {
                diaryEntries[entryIndex] = normalizeDiaryEntry(diaryEntries[entryIndex])
                changedEntries.append(diaryEntries[entryIndex])
            }
        }
        if changedEntries.isEmpty == false {
            persistDiaryEntries()
        }
        return changedEntries
    }
    
    private func validatedLocationVisitTagName(_ rawName: String,
                                               excluding id: UUID? = nil) throws -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw LocationVisitTagError.emptyName
        }
        guard trimmed.count <= Self.maxLocationVisitTagNameLength else {
            throw LocationVisitTagError.nameTooLong(max: Self.maxLocationVisitTagNameLength)
        }
        guard containsLocationVisitTag(named: trimmed, excluding: id) == false else {
            throw LocationVisitTagError.duplicateName
        }
        return trimmed
    }
    
    private func containsLocationVisitTag(named name: String, excluding id: UUID? = nil) -> Bool {
        let target = Self.normalizedTagKey(name)
        return locationVisitTagDefinitions.contains {
            guard $0.id != id else { return false }
            return Self.normalizedTagKey($0.name) == target
        }
    }
    
    private func isSameTagName(_ lhs: String, _ rhs: String) -> Bool {
        Self.normalizedTagKey(lhs) == Self.normalizedTagKey(rhs)
    }
    
    private func seedDefaultLocationVisitTagsIfNeeded() {
        let defaults = UserDefaults(suiteName: PersistenceController.appGroupIdentifier) ?? UserDefaults.standard
        let hasSeeded = defaults.bool(forKey: Self.locationVisitTagsSeededDefaultsKey)
        guard hasSeeded == false else { return }
        
        if locationVisitTagDefinitions.isEmpty {
            locationVisitTagDefinitions = Self.defaultLocationVisitTagNames.enumerated().map { index, name in
                LocationVisitTagDefinition(name: name, sortOrder: index)
            }
            persistLocationVisitTags()
        }
        defaults.set(true, forKey: Self.locationVisitTagsSeededDefaultsKey)
    }
    
    private func normalizeLocationVisitTagOrderIfNeeded() {
        let sorted = locationVisitTagDefinitions.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.name < rhs.name
        }
        let normalized = sorted.enumerated().map { index, tag in
            var mutable = tag
            mutable.sortOrder = index
            return mutable
        }
        guard normalized != locationVisitTagDefinitions else { return }
        locationVisitTagDefinitions = normalized
        persistLocationVisitTags()
    }

    private func persist<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            let defaults = UserDefaults(suiteName: PersistenceController.appGroupIdentifier) ?? UserDefaults.standard
            defaults.set(data, forKey: key)
            // Backup to standard for safety? Not strictly needed if we fully migrate, but good for now.
        }
    }

    private func persistTasks() {
        persist(tasks, forKey: Self.tasksDefaultsKey)
    }

    private func persistDiaryEntries() {
        persist(diaryEntries, forKey: Self.diaryDefaultsKey)
    }
    
    private func persistLocationVisitTags() {
        persist(locationVisitTagDefinitions, forKey: Self.locationVisitTagsDefaultsKey)
    }

    private func persistHabits() {
        persist(habits, forKey: Self.habitsDefaultsKey)
    }

    private func persistHabitRecords() {
        persist(habitRecords, forKey: Self.habitRecordsDefaultsKey)
    }

    private func persistAnniversaries() {
        persist(anniversaries, forKey: Self.anniversariesDefaultsKey)
    }

    private func persistCalendarEvents() {
        persist(calendarEvents, forKey: Self.calendarEventsDefaultsKey)
        
        // Full Sync to SwiftData
        let descriptor = FetchDescriptor<SDCalendarEvent>()
        if let existingItems = try? modelContext.fetch(descriptor) {
            let existingMap = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })
            var validIDs: Set<UUID> = []

            for event in calendarEvents {
                validIDs.insert(event.id)
                if let existing = existingMap[event.id] {
                    existing.update(from: event)
                } else {
                    let newEvent = SDCalendarEvent(domain: event)
                    modelContext.insert(newEvent)
                }
            }

            // Delete removed
            for existing in existingItems {
                if !validIDs.contains(existing.id) {
                    modelContext.delete(existing)
                }
            }
            try? modelContext.save()
        }
    }

    private func persistExternalCalendarEvents() {
        persist(externalCalendarEvents, forKey: Self.externalCalendarEventsDefaultsKey)
    }

    private func persistExternalCalendarRange() {
        persist(externalCalendarRange, forKey: Self.externalCalendarRangeDefaultsKey)
    }

    private func reloadHabitWidgetTimeline() {
        WidgetCenter.shared.reloadTimelines(ofKind: "HabitWidget")
    }

    private func reloadAnniversaryWidgetTimeline() {
        WidgetCenter.shared.reloadTimelines(ofKind: "AnniversaryWidget")
    }

    private enum EventReminderStrategy {
        case relative(minutesBefore: Int)
        case absolute(reminderDate: Date)
    }

    private func effectiveReminderStrategy(for event: CalendarEvent) -> EventReminderStrategy? {
        if let explicit = explicitReminderStrategy(for: event) {
            return explicit
        }

        guard NotificationSettingsManager.shared.isEventCategoryNotificationEnabled else {
            return nil
        }

        let setting = NotificationSettingsManager.shared.getOrCreateSetting(for: event.calendarName)
        return eventCategoryDefaultReminderStrategy(for: event, setting: setting)
    }

    private func explicitReminderStrategy(for event: CalendarEvent) -> EventReminderStrategy? {
        if let minutes = event.reminderMinutes, minutes > 0 {
            return .relative(minutesBefore: minutes)
        }
        if let reminderDate = event.reminderDate {
            return .absolute(reminderDate: reminderDate)
        }
        return nil
    }

    private func eventCategoryDefaultReminderStrategy(for event: CalendarEvent, setting: CategoryNotificationSetting?) -> EventReminderStrategy? {
        guard let setting, setting.enabled else { return nil }
        if setting.useRelativeTime {
            return .relative(minutesBefore: setting.minutesBefore)
        }

        let reminderDate = Calendar.current.date(
            bySettingHour: setting.hour,
            minute: setting.minute,
            second: 0,
            of: event.startDate
        ) ?? event.startDate
        return .absolute(reminderDate: reminderDate)
    }

    private func applyReminderStrategy(_ strategy: EventReminderStrategy?, to event: inout CalendarEvent) {
        switch strategy {
        case .relative(let minutesBefore):
            event.reminderMinutes = minutesBefore
            event.reminderDate = nil
        case .absolute(let reminderDate):
            event.reminderMinutes = nil
            event.reminderDate = reminderDate
        case nil:
            event.reminderMinutes = nil
            event.reminderDate = nil
        }
    }

    private func reminderStrategy(_ lhs: EventReminderStrategy?, matches rhs: EventReminderStrategy?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (.relative(lhsMinutes), .relative(rhsMinutes)):
            return lhsMinutes == rhsMinutes
        case let (.absolute(lhsDate), .absolute(rhsDate)):
            return Calendar.current.compare(lhsDate, to: rhsDate, toGranularity: .minute) == .orderedSame
        default:
            return false
        }
    }

    private func rescheduleExternalEventNotifications() {
        let now = Date()
        let maxScheduledExternalReminders = 48

        struct PendingExternalReminder {
            let event: CalendarEvent
            let strategy: EventReminderStrategy
            let fireDate: Date
        }

        let candidates: [PendingExternalReminder] = externalCalendarEvents.compactMap { event in
            guard let strategy = effectiveReminderStrategy(for: event) else { return nil }

            let fireDate: Date
            switch strategy {
            case .relative(let minutesBefore):
                fireDate = event.startDate.addingTimeInterval(-Double(minutesBefore * 60))
            case .absolute(let reminderDate):
                fireDate = reminderDate
            }

            guard fireDate > now else { return nil }
            return PendingExternalReminder(event: event, strategy: strategy, fireDate: fireDate)
        }

        let remindersToSchedule = candidates
            .sorted(by: { $0.fireDate < $1.fireDate })
            .prefix(maxScheduledExternalReminders)

        externalReminderRescheduleGeneration &+= 1
        let generation = externalReminderRescheduleGeneration

        NotificationService.shared.cancelAllReminders(ofType: .externalEvent) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.externalReminderRescheduleGeneration == generation else { return }

                for candidate in remindersToSchedule {
                    let externalEventKey = self.externalEventReminderKey(for: candidate.event)
                    switch candidate.strategy {
                    case .relative(let minutesBefore):
                        NotificationService.shared.scheduleExternalEventReminder(
                            externalEventKey: externalEventKey,
                            title: candidate.event.title,
                            startDate: candidate.event.startDate,
                            minutesBefore: minutesBefore
                        )
                    case .absolute(let reminderDate):
                        NotificationService.shared.scheduleExternalEventReminderAtDate(
                            externalEventKey: externalEventKey,
                            title: candidate.event.title,
                            reminderDate: reminderDate
                        )
                    }
                }
            }
        }
    }

    private func externalEventReminderKey(for event: CalendarEvent) -> String {
        let source = event.sourceCalendarIdentifier ?? "unknown"
        let start = Int(event.startDate.timeIntervalSince1970)
        let end = Int(event.endDate.timeIntervalSince1970)
        let signature = "\(event.id.uuidString)|\(source)|\(start)|\(end)|\(event.isAllDay)|\(event.title)"
        return stableHash(signature)
    }

    private func stableHash(_ value: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return String(hash, radix: 16)
    }

    private func scheduleEventNotification(_ event: CalendarEvent) {
        // キャンセルしてから再スケジュール
        NotificationService.shared.cancelEventReminder(eventId: event.id)

        guard let strategy = effectiveReminderStrategy(for: event) else { return }

        switch strategy {
        case .relative(let minutesBefore):
            NotificationService.shared.scheduleEventReminder(
                eventId: event.id,
                title: event.title,
                startDate: event.startDate,
                minutesBefore: minutesBefore
            )
        case .absolute(let reminderDate):
            NotificationService.shared.scheduleEventReminderAtDate(
                eventId: event.id,
                title: event.title,
                reminderDate: reminderDate
            )
        }
    }

    private func scheduleTaskNotification(_ task: Task) {
        // キャンセルしてから再スケジュール
        NotificationService.shared.cancelTaskReminder(taskId: task.id)
        if let reminderDate = task.reminderDate {
            NotificationService.shared.scheduleTaskReminder(
                taskId: task.id,
                title: task.title,
                reminderDate: reminderDate
            )
        }
    }

    private func taskPriorityDefaultReminderDate(for task: Task, setting: PriorityNotificationSetting?) -> Date? {
        guard let setting, setting.enabled else { return nil }
        let baseDate = task.startDate ?? task.endDate
        guard let baseDate else { return nil }
        return Calendar.current.date(bySettingHour: setting.hour, minute: setting.minute, second: 0, of: baseDate)
    }

    private func reminderDate(_ lhs: Date?, matches rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return Calendar.current.compare(lhs, to: rhs, toGranularity: .minute) == .orderedSame
        default:
            return false
        }
    }

    private func isTask(_ task: Task, scheduledOn date: Date) -> Bool {
        let calendar = Calendar.current
        let start = task.startDate ?? task.endDate
        let end = task.endDate ?? task.startDate
        guard let anchor = start ?? end else { return false }
        let normalizedStart = calendar.startOfDay(for: start ?? anchor)
        let normalizedEnd = calendar.startOfDay(for: end ?? anchor)
        let target = calendar.startOfDay(for: date)
        return normalizedStart...normalizedEnd ~= target
    }

    private func scheduleAnniversaryNotification(_ anniversary: Anniversary) {
        // キャンセルしてから再スケジュール
        NotificationService.shared.cancelAnniversaryReminder(anniversaryId: anniversary.id)
        
        if let daysBefore = anniversary.reminderDaysBefore,
           let time = anniversary.reminderTime {
            // 相対時間（X日前）
            NotificationService.shared.scheduleAnniversaryReminder(
                anniversaryId: anniversary.id,
                title: anniversary.title,
                targetDate: anniversary.targetDate,
                daysBefore: daysBefore,
                time: time,
                repeatsYearly: anniversary.repeatsYearly
            )
        } else if let reminderDate = anniversary.reminderDate {
            // 絶対日時指定
            NotificationService.shared.scheduleAnniversaryReminderAtDate(
                anniversaryId: anniversary.id,
                title: anniversary.title,
                reminderDate: reminderDate
            )
        }
    }

    // MARK: - Sample Data (DEBUG only)

    #if DEBUG
    private func seedJapaneseScheduleForScreenshotsIfNeeded() {
        let arguments = Set(ProcessInfo.processInfo.arguments)
        guard Self.screenshotsModeLaunchArguments.isDisjoint(with: arguments) == false else { return }

        let minimumEventCountForScreenshots = 18
        guard calendarEvents.count < minimumEventCountForScreenshots else { return }

        var mergedEvents = calendarEvents
        let seededEvents = makeJapaneseSampleScheduleEvents(referenceDate: Date())
        for event in seededEvents where containsSimilarCalendarEvent(event, in: mergedEvents) == false {
            mergedEvents.append(event)
        }

        guard mergedEvents.count != calendarEvents.count else { return }
        mergedEvents.sort {
            if $0.startDate == $1.startDate {
                return $0.endDate < $1.endDate
            }
            return $0.startDate < $1.startDate
        }
        calendarEvents = mergedEvents
        eventsCache.removeAll()
        persistCalendarEvents()
    }

    private func makeJapaneseSampleScheduleEvents(referenceDate: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)

        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: today) ?? today
        }

        func timed(_ title: String, _ dayOffset: Int, _ startHour: Int, _ startMinute: Int, _ endHour: Int, _ endMinute: Int, _ calendarName: String) -> CalendarEvent {
            let targetDay = day(dayOffset)
            let start = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: targetDay) ?? targetDay
            let end = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: targetDay) ?? start.addingTimeInterval(3_600)
            return CalendarEvent(
                title: title,
                startDate: start,
                endDate: end,
                calendarName: calendarName
            )
        }

        func allDay(_ title: String, _ dayOffset: Int, _ lengthDays: Int, _ calendarName: String) -> CalendarEvent {
            let start = day(dayOffset)
            let end = calendar.date(byAdding: .day, value: max(1, lengthDays), to: start) ?? start.addingTimeInterval(86_400)
            return CalendarEvent(
                title: title,
                startDate: start,
                endDate: end,
                calendarName: calendarName,
                isAllDay: true
            )
        }

        return [
            timed("朝の散歩", -2, 7, 0, 7, 30, "健康"),
            timed("チーム朝会", -1, 9, 30, 10, 0, "仕事"),
            timed("週次ふりかえり", -1, 18, 30, 19, 15, "仕事"),
            timed("チーム朝会", 0, 9, 30, 10, 0, "仕事"),
            timed("仕様確認ミーティング", 0, 11, 0, 12, 0, "仕事"),
            timed("ランチ（中華）", 0, 12, 30, 13, 20, "プライベート"),
            timed("E2EE手紙の下書き", 0, 21, 0, 21, 30, "タイムカプセル"),
            timed("ジム", 1, 19, 0, 20, 0, "健康"),
            timed("買い物", 2, 18, 30, 19, 30, "プライベート"),
            allDay("日帰り旅行", 3, 1, "旅行"),
            timed("カレンダー整理", 4, 20, 30, 21, 0, "プライベート"),
            timed("チーム朝会", 5, 9, 30, 10, 0, "仕事"),
            timed("デザインレビュー", 5, 15, 0, 16, 0, "仕事"),
            timed("歯科検診", 7, 10, 30, 11, 15, "健康"),
            timed("習慣チェック", 8, 21, 0, 21, 20, "習慣"),
            allDay("出張（大阪）", 10, 2, "仕事"),
            timed("メモ整理", 13, 20, 0, 20, 40, "学習"),
            timed("写真整理", 15, 21, 0, 21, 40, "プライベート"),
            timed("タイムカプセル作成", 18, 20, 0, 21, 0, "タイムカプセル"),
            timed("読書", 21, 22, 0, 22, 40, "学習"),
            timed("チーム朝会", 22, 9, 30, 10, 0, "仕事"),
            timed("美容院", 25, 14, 0, 15, 0, "プライベート"),
            allDay("実家へ帰省", 29, 2, "家族"),
            timed("翌月の計画づくり", 34, 20, 0, 21, 0, "プライベート"),
            timed("月次レビュー", 40, 18, 0, 19, 0, "仕事"),
            timed("振り返りと日記", 44, 21, 0, 21, 40, "習慣")
        ]
    }

    private func containsSimilarCalendarEvent(_ candidate: CalendarEvent, in events: [CalendarEvent]) -> Bool {
        events.contains {
            $0.title == candidate.title &&
            $0.calendarName == candidate.calendarName &&
            abs($0.startDate.timeIntervalSince(candidate.startDate)) < 1 &&
            abs($0.endDate.timeIntervalSince(candidate.endDate)) < 1 &&
            $0.isAllDay == candidate.isAllDay
        }
    }

    private func seedSampleDataIfNeeded() {
        guard tasks.isEmpty && diaryEntries.isEmpty && habits.isEmpty && anniversaries.isEmpty && calendarEvents.isEmpty else { return }
        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart)
        tasks = [
            Task(title: "Morning workout",
                 detail: "20 min yoga",
                 startDate: todayStart,
                 endDate: todayStart,
                 priority: .medium),
            Task(title: "Design review",
                 detail: "Bujo dashboard layout",
                 startDate: todayStart,
                 endDate: todayStart,
                 priority: .high),
            Task(title: "Buy groceries",
                 startDate: tomorrow,
                 endDate: calendar.date(byAdding: .day, value: 2, to: tomorrow) ?? tomorrow,
                 priority: .low)
        ]

        let sampleNotes = [
            "ランニングで気分がすっきり。ミーティングも穏やかに進んだ。",
            "睡眠不足で少しぼんやり。夜は早めに休む予定。",
            "在宅で集中できた。コードレビューも褒められた。",
            "移動が多くて歩き疲れたけれど、夕方のコーヒーで復活。",
            "週末モードでのんびり。散歩して深呼吸。",
            "雨で外に出られず、ストレッチだけ。少し肩が重い。",
            "たっぷり寝たのでエネルギー満タン。新しいアイデアが浮かんだ。"
        ]
        diaryEntries = (0..<7).compactMap { offset -> DiaryEntry? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: todayStart) else {
                return nil
            }
            let moodLevel: MoodLevel = {
                switch offset {
                case 0: return .veryHigh
                case 1: return .high
                case 2: return .neutral
                case 3: return .low
                case 4: return .neutral
                case 5: return .veryLow
                default: return .high
                }
            }()
            let condition = max(1, min(5, 5 - offset + Int.random(in: -1...1)))
            return DiaryEntry(date: date,
                              text: sampleNotes[min(offset, sampleNotes.count - 1)],
                              mood: moodLevel,
                              conditionScore: condition,
                              locationName: "自宅",
                              latitude: 35.68,
                              longitude: 139.76)
        }

        let habit1 = Habit(title: "Meditation", iconName: "brain.head.profile", colorHex: "#F97316", schedule: .daily)
        let habit2 = Habit(title: "Drink Water", iconName: "drop.fill", colorHex: "#0EA5E9", schedule: .custom(days: [.monday, .wednesday, .friday]))
        let habit3 = Habit(title: "Read 20 pages", iconName: "book.fill", colorHex: "#22C55E", schedule: .weekdays)
        habits = [habit1, habit2, habit3]

        habitRecords = [
            HabitRecord(habitID: habit1.id, date: now, isCompleted: true),
            HabitRecord(habitID: habit3.id, date: now, isCompleted: false)
        ]

        anniversaries = [
            Anniversary(title: "Next vacation", targetDate: calendar.date(byAdding: .day, value: 45, to: now) ?? now, type: .countdown, repeatsYearly: false),
            Anniversary(title: "Started Bullet Journal", targetDate: calendar.date(byAdding: .year, value: -2, to: now) ?? now, type: .since, repeatsYearly: true)
        ]

        calendarEvents = [
            CalendarEvent(title: "Team stand-up", startDate: calendar.date(bySettingHour: 9, minute: 30, second: 0, of: now) ?? now,
                          endDate: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now) ?? now, calendarName: "Work"),
            CalendarEvent(title: "Lunch with Sara", startDate: calendar.date(bySettingHour: 12, minute: 30, second: 0, of: now) ?? now,
                          endDate: calendar.date(bySettingHour: 13, minute: 30, second: 0, of: now) ?? now, calendarName: "Personal"),
            CalendarEvent(title: "Offsite", startDate: todayStart,
                          endDate: calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart.addingTimeInterval(86_400),
                          calendarName: "Work",
                          isAllDay: true),
            CalendarEvent(title: "Yoga class", startDate: calendar.date(byAdding: .day, value: 1, to: now)?.addingTimeInterval(18_000) ?? now,
                          endDate: calendar.date(byAdding: .day, value: 1, to: now)?.addingTimeInterval(19_800) ?? now, calendarName: "Wellness")
        ]
        persistTasks()
        persistDiaryEntries()
        persistHabits()
        persistHabitRecords()
        persistAnniversaries()
        persistCalendarEvents()
    }
    #endif
}
