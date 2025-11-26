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

    private static let memoPadDefaultsKey = "MemoPad_Storage_V1"
    private static let appStateDefaultsKey = "AppState_Storage_V1"

    // MARK: - Init

    init() {
        memoPad = Self.loadMemoPad()
        appState = Self.loadAppState()
        #if DEBUG
        seedSampleDataIfNeeded()
        #endif
        _Concurrency.Task {
            await loadHealthData()
        }
    }
    
    func loadHealthData() async {
        let authorized = await HealthKitManager.shared.requestAuthorization()
        if authorized {
            let fetched = await HealthKitManager.shared.fetchHealthData(for: 30)
            if fetched.isEmpty == false {
                self.healthSummaries = fetched
            }
        }
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
    }

    func updateCalendarEvent(_ event: CalendarEvent) {
        guard let index = calendarEvents.firstIndex(where: { $0.id == event.id }) else { return }
        calendarEvents[index] = event
    }

    func deleteCalendarEvent(_ eventID: UUID) {
        calendarEvents.removeAll { $0.id == eventID }
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
        let defaultCategory = CategoryPalette.defaultCategoryName
        for calendar in calendars {
            if let index = links.firstIndex(where: { $0.calendarIdentifier == calendar.calendarIdentifier }) {
                links[index].calendarTitle = calendar.title
                links[index].colorHex = calendar.cgColor.hexString
            } else {
                let shouldHide = calendar.title.contains("祝日")
                let link = CalendarCategoryLink(calendarIdentifier: calendar.calendarIdentifier,
                                                calendarTitle: calendar.title,
                                                categoryId: shouldHide ? nil : defaultCategory,
                                                colorHex: calendar.cgColor.hexString)
                links.append(link)
            }
        }
        appState.calendarCategoryLinks = links
        persistAppState()
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
    }

    func updateTask(_ task: Task) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
    }

    func deleteTasks(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where tasks.indices.contains(index) {
            tasks.remove(at: index)
        }
    }

    func deleteTasks(withIDs ids: [UUID]) {
        tasks.removeAll { ids.contains($0.id) }
    }

    func toggleTaskCompletion(_ taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].isCompleted.toggle()
    }

    // MARK: - Diary CRUD

    func entry(for date: Date) -> DiaryEntry? {
        diaryEntries.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func upsert(entry: DiaryEntry) {
        if let index = diaryEntries.firstIndex(where: { $0.id == entry.id }) {
            diaryEntries[index] = entry
        } else {
            diaryEntries.append(entry)
        }
    }

    // MARK: - Habits

    func records(for date: Date) -> [HabitRecord] {
        habitRecords.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func toggleHabit(_ habitID: UUID, on date: Date) {
        if let index = habitRecords.firstIndex(where: {
            $0.habitID == habitID && Calendar.current.isDate($0.date, inSameDayAs: date)
        }) {
            habitRecords[index].isCompleted.toggle()
        } else {
            let record = HabitRecord(habitID: habitID, date: date, isCompleted: true)
            habitRecords.append(record)
        }
    }

    func setHabitCompletion(_ habitID: UUID, on date: Date, completed: Bool) {
        if let index = habitRecords.firstIndex(where: {
            $0.habitID == habitID && Calendar.current.isDate($0.date, inSameDayAs: date)
        }) {
            habitRecords[index].isCompleted = completed
        } else if completed {
            let record = HabitRecord(habitID: habitID, date: date, isCompleted: true)
            habitRecords.append(record)
        }
    }

    func addHabit(_ habit: Habit) {
        habits.append(habit)
    }

    func updateHabit(_ habit: Habit) {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        habits[index] = habit
    }

    // MARK: - Anniversaries

    func addAnniversary(_ anniversary: Anniversary) {
        anniversaries.append(anniversary)
    }

    func updateAnniversary(_ anniversary: Anniversary) {
        guard let index = anniversaries.firstIndex(where: { $0.id == anniversary.id }) else { return }
        anniversaries[index] = anniversary
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
            CalendarEvent(title: "Yoga class", startDate: calendar.date(byAdding: .day, value: 1, to: now)?.addingTimeInterval(18_000) ?? now,
                          endDate: calendar.date(byAdding: .day, value: 1, to: now)?.addingTimeInterval(19_800) ?? now, calendarName: "Wellness")
        ]


    }
    #endif
}
