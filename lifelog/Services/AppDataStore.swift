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
    @Published private(set) var appState: AppState = AppState()

    private static let tasksDefaultsKey = "Tasks_Storage_V1"
    private static let diaryDefaultsKey = "DiaryEntries_Storage_V1"
    private static let habitsDefaultsKey = "Habits_Storage_V1"
    private static let habitRecordsDefaultsKey = "HabitRecords_Storage_V1"
    private static let anniversariesDefaultsKey = "Anniversaries_Storage_V1"
    private static let calendarEventsDefaultsKey = "CalendarEvents_Storage_V1"
    private static let memoPadDefaultsKey = "MemoPad_Storage_V1"
    private static let appStateDefaultsKey = "AppState_Storage_V1"
    private static let healthSummariesDefaultsKey = "HealthSummaries_Storage_V1"

    // MARK: - Init

    init() {
        tasks = Self.loadValue(forKey: Self.tasksDefaultsKey, defaultValue: [])
        let loadedDiaries: [DiaryEntry] = Self.loadValue(forKey: Self.diaryDefaultsKey, defaultValue: [])
        let needsDiaryNormalization = loadedDiaries.contains { $0.mood == nil || $0.conditionScore == nil }
        diaryEntries = Self.normalizeDiaryEntries(loadedDiaries)
        habits = Self.loadValue(forKey: Self.habitsDefaultsKey, defaultValue: [])
        habitRecords = Self.loadValue(forKey: Self.habitRecordsDefaultsKey, defaultValue: [])
        anniversaries = Self.loadValue(forKey: Self.anniversariesDefaultsKey, defaultValue: [])
        calendarEvents = Self.loadValue(forKey: Self.calendarEventsDefaultsKey, defaultValue: [])
        memoPad = Self.loadMemoPad()
        appState = Self.loadAppState()
        if needsDiaryNormalization {
            persistDiaryEntries()
        }
        #if DEBUG
        seedSampleDataIfNeeded()
        #endif
        _Concurrency.Task {
            await loadHealthData()
        }
    }
    
    func loadHealthData() async {
        // Load cached data first
        let cached: [HealthSummary] = Self.loadValue(forKey: Self.healthSummariesDefaultsKey, defaultValue: [])
        if !cached.isEmpty {
            self.healthSummaries = cached
        }
        
        let authorized = await HealthKitManager.shared.requestAuthorization()
        if authorized {
            // Fetch recent 7 days for quick update, then full year in background
            let recentFetched = await HealthKitManager.shared.fetchHealthData(for: 7)
            if !recentFetched.isEmpty {
                mergeHealthSummaries(recentFetched)
            }
            
            // Fetch full year (365 days) - this runs after recent data is shown
            let fullFetched = await HealthKitManager.shared.fetchHealthData(for: 365)
            if !fullFetched.isEmpty {
                mergeHealthSummaries(fullFetched)
                persistHealthSummaries()
            }
        }
    }
    
    private func mergeHealthSummaries(_ newData: [HealthSummary]) {
        var summaryDict = Dictionary(uniqueKeysWithValues: healthSummaries.map { ($0.date, $0) })
        for summary in newData {
            summaryDict[summary.date] = summary
        }
        healthSummaries = Array(summaryDict.values).sorted { $0.date > $1.date }
    }
    
    private func persistHealthSummaries() {
        persist(healthSummaries, forKey: Self.healthSummariesDefaultsKey)
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
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return (calendarEvents + externalCalendarEvents)
            .filter { event in
                event.startDate < dayEnd && event.endDate > dayStart
            }
            .sorted(by: { $0.startDate < $1.startDate })
    }

    func addCalendarEvent(_ event: CalendarEvent) {
        calendarEvents.append(event)
        persistCalendarEvents()
        scheduleEventNotification(event)
    }

    func updateCalendarEvent(_ event: CalendarEvent) {
        guard let index = calendarEvents.firstIndex(where: { $0.id == event.id }) else { return }
        calendarEvents[index] = event
        persistCalendarEvents()
        scheduleEventNotification(event)
    }

    func deleteCalendarEvent(_ eventID: UUID) {
        calendarEvents.removeAll { $0.id == eventID }
        persistCalendarEvents()
        NotificationService.shared.cancelEventReminder(eventId: eventID)
    }

    func updateExternalCalendarEvents(_ events: [CalendarEvent]) {
        externalCalendarEvents = events
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

    // MARK: - Task CRUD

    func addTask(_ task: Task) {
        tasks.append(task)
        persistTasks()
        scheduleTaskNotification(task)
    }

    func updateTask(_ task: Task) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
        persistTasks()
        scheduleTaskNotification(task)
    }

    func deleteTasks(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where tasks.indices.contains(index) {
            NotificationService.shared.cancelTaskReminder(taskId: tasks[index].id)
            tasks.remove(at: index)
        }
        persistTasks()
    }

    func deleteTasks(withIDs ids: [UUID]) {
        for id in ids {
            NotificationService.shared.cancelTaskReminder(taskId: id)
        }
        tasks.removeAll { ids.contains($0.id) }
        persistTasks()
    }

    func toggleTaskCompletion(_ taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].isCompleted.toggle()
        persistTasks()
    }

    // MARK: - Diary CRUD

    func entry(for date: Date) -> DiaryEntry? {
        diaryEntries.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func upsert(entry: DiaryEntry) {
        var normalized = entry
        normalized.mood = normalized.mood ?? .neutral
        normalized.conditionScore = normalized.conditionScore ?? 3
        if let index = diaryEntries.firstIndex(where: { $0.id == normalized.id }) {
            diaryEntries[index] = normalized
        } else {
            diaryEntries.append(normalized)
        }
        persistDiaryEntries()
        
        // 今日の日記を書いたら（内容があれば）その日のリマインダーをキャンセル
        let isToday = Calendar.current.isDateInToday(entry.date)
        let hasContent = !normalized.text.isEmpty
        
        if isToday && diaryReminderEnabled && hasContent {
            NotificationService.shared.cancelDiaryReminder()
        }
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
        
        // Haptic feedback
        if isCompleting {
            let streakAfter = calculateCurrentStreak(for: habitID, upTo: date)
            if streakAfter > streakBefore && streakAfter >= 3 {
                // 3日以上の連続達成更新時は特別なハプティック
                HapticManager.streak()
                // 3日以上連続達成でポジティブアクションとして記録
                ReviewRequestManager.shared.registerPositiveAction()
            } else {
                HapticManager.success()
            }
            
            // 全習慣達成チェック
            checkAllHabitsComplete(on: date)
        } else {
            HapticManager.light()
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
        let activeHabits = habits.filter { $0.schedule.isActive(on: date) }
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
    }

    func addHabit(_ habit: Habit) {
        habits.append(habit)
        persistHabits()
    }

    func updateHabit(_ habit: Habit) {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        habits[index] = habit
        persistHabits()
    }

    func deleteHabit(_ habitID: UUID) {
        // Soft delete: archive the habit instead of removing it
        // This preserves historical completion data
        guard let index = habits.firstIndex(where: { $0.id == habitID }) else { return }
        habits[index].isArchived = true
        habits[index].archivedAt = Date()
        persistHabits()
    }
    
    func moveHabit(from source: IndexSet, to destination: Int) {
        habits.move(fromOffsets: source, toOffset: destination)
        persistHabits()
    }

    // MARK: - Anniversaries

    func addAnniversary(_ anniversary: Anniversary) {
        anniversaries.append(anniversary)
        persistAnniversaries()
        scheduleAnniversaryNotification(anniversary)
    }

    func updateAnniversary(_ anniversary: Anniversary) {
        guard let index = anniversaries.firstIndex(where: { $0.id == anniversary.id }) else { return }
        anniversaries[index] = anniversary
        persistAnniversaries()
        scheduleAnniversaryNotification(anniversary)
    }

    func deleteAnniversary(_ anniversaryID: UUID) {
        anniversaries.removeAll { $0.id == anniversaryID }
        persistAnniversaries()
        NotificationService.shared.cancelAnniversaryReminder(anniversaryId: anniversaryID)
    }
    
    func moveAnniversary(from source: IndexSet, to destination: Int) {
        anniversaries.move(fromOffsets: source, toOffset: destination)
        persistAnniversaries()
    }

    // MARK: - Memo Pad

    func updateMemoPad(text: String) {
        guard text != memoPad.text else { return }
        memoPad.text = text
        memoPad.lastUpdatedAt = Date()
        persistMemoPad()
    }

    private static func loadMemoPad() -> MemoPad {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: memoPadDefaultsKey),
           let memo = try? JSONDecoder().decode(MemoPad.self, from: data) {
            return memo
        }
        return MemoPad()
    }

    private func persistMemoPad() {
        if let data = try? JSONEncoder().encode(memoPad) {
            UserDefaults.standard.set(data, forKey: Self.memoPadDefaultsKey)
        }
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

    // MARK: - Persistence Helpers

    private static func loadValue<T: Decodable>(forKey key: String, defaultValue: T) -> T {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(T.self, from: data) {
            return decoded
        }
        return defaultValue
    }

    private static func normalizeDiaryEntries(_ entries: [DiaryEntry]) -> [DiaryEntry] {
        entries.map { entry in
            var normalized = entry
            normalized.mood = normalized.mood ?? .neutral
            normalized.conditionScore = normalized.conditionScore ?? 3
            return normalized
        }
    }

    private func persist<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func persistTasks() {
        persist(tasks, forKey: Self.tasksDefaultsKey)
    }

    private func persistDiaryEntries() {
        persist(diaryEntries, forKey: Self.diaryDefaultsKey)
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
    }

    private func scheduleEventNotification(_ event: CalendarEvent) {
        // キャンセルしてから再スケジュール
        NotificationService.shared.cancelEventReminder(eventId: event.id)
        
        if let minutes = event.reminderMinutes, minutes > 0 {
            // 相対時間（X分前）
            NotificationService.shared.scheduleEventReminder(
                eventId: event.id,
                title: event.title,
                startDate: event.startDate,
                minutesBefore: minutes
            )
        } else if let reminderDate = event.reminderDate {
            // 絶対日時指定
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
            NotificationService.shared.scheduleTaskReminder(
                taskId: anniversary.id,
                title: anniversary.title,
                reminderDate: reminderDate
            )
        }
    }

    // MARK: - Sample Data (DEBUG only)

    #if DEBUG
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
