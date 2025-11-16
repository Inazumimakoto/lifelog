//
//  AppDataStore.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import Combine
import HealthKit

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

    // MARK: - Init

    init() {
        seedSampleData()
        _Concurrency.Task {
            await loadHealthData()
        }
    }
    
#if targetEnvironment(simulator)
    func loadHealthData() async {
        // シミュレーターでは HealthKit から取得できないのでサンプルデータのままにする
    }
#else
    func loadHealthData() async {
        let authorized = await HealthKitManager.shared.requestAuthorization()
        if authorized {
            let fetched = await HealthKitManager.shared.fetchHealthData(for: 30)
            if fetched.isEmpty == false {
                self.healthSummaries = fetched
            }
        }
    }
#endif

    // MARK: - Calendar

    func events(on date: Date) -> [CalendarEvent] {
        calendarEvents.filter { Calendar.current.isDate($0.startDate, inSameDayAs: date) }
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

    // MARK: - Sample Data

    private func seedSampleData() {
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

        diaryEntries = [
            DiaryEntry(date: now,
                       text: "今日は集中力も高く、プロジェクトが順調に進んだ。",
                       mood: .high,
                       conditionScore: 4,
                       locationName: "自宅デスク",
                       latitude: 35.6804,
                       longitude: 139.7690),
            DiaryEntry(date: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
                       text: "",
                       mood: .neutral,
                       conditionScore: 3,
                       locationName: nil)
        ]

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

        healthSummaries = (0..<10).compactMap { offset -> HealthSummary? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: todayStart),
                  let previousDay = calendar.date(byAdding: .day, value: -1, to: date),
                  let sleepStart = calendar.date(bySettingHour: 23,
                                                 minute: Int.random(in: 0...45),
                                                 second: 0,
                                                 of: previousDay),
                  let sleepEnd = calendar.date(bySettingHour: Int.random(in: 6...7),
                                               minute: Int.random(in: 0...50),
                                               second: 0,
                                               of: date) else {
                return nil
            }
            let sleepHours = sleepEnd.timeIntervalSince(sleepStart) / 3600
            return HealthSummary(date: date,
                                 steps: Int.random(in: 4_500...12_000),
                                 sleepHours: sleepHours,
                                 activeEnergy: Double.random(in: 250...620),
                                 moveMinutes: Double.random(in: 35...90),
                                 exerciseMinutes: Double.random(in: 20...50),
                                 standHours: Double.random(in: 8...13),
                                 sleepStart: sleepStart,
                                 sleepEnd: sleepEnd,
                                 sleepStages: SleepStage.demoSequence(referenceDate: date))
        }
    }
}
