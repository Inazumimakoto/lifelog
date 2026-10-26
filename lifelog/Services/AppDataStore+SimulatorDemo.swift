import Foundation
import SwiftData
import WidgetKit
import os

#if DEBUG && targetEnvironment(simulator)
extension AppDataStore {
    /// Local demo fixtures only (docs/requirements.md §4.11); never compiled into a physical-device build.
    func seedSimulatorDemoDataIfNeeded() {
        guard PersistenceController.isSimulatorDemoMode, hasSimulatorDemoConfiguration else { return }
        let defaults = UserDefaults(suiteName: PersistenceController.appGroupIdentifier)!
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        do {
            try seedSimulatorReviewMapDataIfNeeded(today: today, defaults: defaults, isDemoMode: true)
            try seedSupplementalSimulatorDemoDataIfNeeded(referenceDate: today, isDemoMode: true)
            try seedSimulatorScheduleDataIfNeeded(today: today, defaults: defaults, isDemoMode: true)
        } catch {
            modelContext.rollback()
            AppLogger.data.error("Simulator home fixtures could not be saved: \(error)")
        }
    }

    @discardableResult
    func seedSimulatorScheduleDataIfNeeded(today: Date, defaults: UserDefaults, isDemoMode: Bool) throws -> Bool {
        guard isDemoMode, hasSimulatorDemoConfiguration else { return false }
        let calendar = Calendar.current
        let seededDayKey = "simulatorDemo.seededDay.v1"
        let wasSeededToday = (defaults.object(forKey: seededDayKey) as? Date) == today

        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: today)!
        }
        func identifier(_ index: Int) -> UUID {
            UUID(uuidString: String(format: "DE000000-0000-4000-8000-%012d", index))!
        }
        func event(_ index: Int, _ title: String, offset: Int, hour: Int, category: String) -> CalendarEvent {
            let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day(offset))!
            return CalendarEvent(
                id: identifier(index), title: title, startDate: start,
                endDate: calendar.date(byAdding: .hour, value: 1, to: start)!,
                calendarName: category
            )
        }

        var demoEvents = [
            event(1, String(localized: "チーム朝会"), offset: 0, hour: 10, category: "仕事"),
            event(2, String(localized: "買い物"), offset: 0, hour: 17, category: "趣味")
        ]
        for (index, offset) in [-4, -2, 2, 4, 5, 7, 10, 12, 15, 18, 21, 24].enumerated() {
            demoEvents.append(event(
                index + 10,
                index.isMultiple(of: 2) ? String(localized: "デザインレビュー") : String(localized: "ジム"),
                offset: offset,
                hour: index.isMultiple(of: 2) ? 14 : 19,
                category: index.isMultiple(of: 2) ? "仕事" : "趣味"
            ))
        }
        demoEvents.append(CalendarEvent(
            id: identifier(30), title: String(localized: "日帰り旅行"),
            startDate: day(9), endDate: day(10), calendarName: "旅行", isAllDay: true
        ))
        let demoTasks = [
            Task(id: identifier(101), title: String(localized: "Design review"), startDate: today, endDate: today, priority: .high),
            Task(id: identifier(102), title: String(localized: "読書"), startDate: today, endDate: today, priority: .medium),
            Task(id: identifier(103), title: String(localized: "Buy groceries"), startDate: day(1), endDate: day(1), priority: .low),
            Task(id: identifier(104), title: String(localized: "写真整理"), startDate: day(3), endDate: day(3), priority: .medium)
        ]

        let savedEvents = try modelContext.fetch(FetchDescriptor<SDCalendarEvent>())
        let savedTasks = try modelContext.fetch(FetchDescriptor<SDTask>())
        let hasAllEvents = Set(demoEvents.map(\.id)).isSubset(of: Set(savedEvents.map(\.id)))
        let hasAllTasks = Set(demoTasks.map(\.id)).isSubset(of: Set(savedTasks.map(\.id)))
        guard !wasSeededToday || !hasAllEvents || !hasAllTasks else { return false }
        for event in demoEvents {
            if let existing = savedEvents.first(where: { $0.id == event.id }) {
                existing.update(from: event)
            } else {
                modelContext.insert(SDCalendarEvent(domain: event))
            }
        }
        for task in demoTasks {
            if let existing = savedTasks.first(where: { $0.id == task.id }) {
                existing.update(from: task)
            } else {
                modelContext.insert(SDTask(domain: task))
            }
        }
        try modelContext.save()
        calendarEvents = try modelContext.fetch(FetchDescriptor<SDCalendarEvent>()).map { CalendarEvent(sd: $0) }
        tasks = try modelContext.fetch(FetchDescriptor<SDTask>()).map { Task(sd: $0) }
        eventsCache.removeAll()
        // The demo widget shares only this suite. Remove any old screenshot calendar cache.
        defaults.removeObject(forKey: Self.externalCalendarEventsDefaultsKey)
        defaults.removeObject(forKey: Self.externalCalendarRangeDefaultsKey)
        defaults.set(today, forKey: seededDayKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
        return true
    }

    private var hasSimulatorDemoConfiguration: Bool {
        modelContext.container.configurations.count == 1 &&
            modelContext.container.configurations.first?.url.lastPathComponent == "simulator-demo.store"
    }

    /// Parameterized mode lets tests use their isolated store and defaults suite
    /// without enabling demo mode or writing to the normal app's preferences.
    @discardableResult
    func seedSimulatorReviewMapDataIfNeeded(today: Date, defaults: UserDefaults, isDemoMode: Bool) throws -> Bool {
        guard isDemoMode, hasSimulatorDemoConfiguration else { return false }
        let seededDayKey = "demo.reviewMap.seededDay.v1"
        let wasSeededToday = (defaults.object(forKey: seededDayKey) as? Date) == today
        let calendar = Calendar.current
        let fixtures = SimulatorReviewMapFixtures.entries(referenceDate: today).map { entry in
            var updated = entry
            if calendar.isDate(updated.date, inSameDayAs: today) {
                updated.text = String(localized: "ランニングで気分がすっきり。ミーティングも穏やかに進んだ。")
                updated.mood = .veryHigh
                updated.conditionScore = 5
            }
            return updated
        }
        let savedDiaries = try modelContext.fetch(FetchDescriptor<SDDiaryEntry>())
        var changed = false
        for entry in fixtures {
            if let existing = savedDiaries.first(where: { $0.id == entry.id }) {
                let saved = DiaryEntry(sd: existing)
                let expectedPlaces = Set(entry.locations.map(\.id))
                let savedPlaces = Set(saved.locations.map(\.id))
                let hasCompletePlaces = expectedPlaces.isSubset(of: savedPlaces)
                let needsTodaySummary = calendar.isDate(entry.date, inSameDayAs: today) &&
                    (saved.text != entry.text || saved.mood != entry.mood || saved.conditionScore != entry.conditionScore)
                guard !wasSeededToday || !hasCompletePlaces ||
                        !calendar.isDate(saved.date, inSameDayAs: entry.date) || needsTodaySummary else { continue }
                existing.update(from: entry)
            } else {
                modelContext.insert(SDDiaryEntry(domain: entry))
            }
            changed = true
        }
        if changed {
            try modelContext.save()
            let reloadedDiaries = try modelContext.fetch(FetchDescriptor<SDDiaryEntry>()).map { DiaryEntry(sd: $0) }
            diaryEntries = Self.normalizeDiaryEntries(reloadedDiaries)
        }
        defaults.set(today, forKey: seededDayKey)
        return changed
    }

    @discardableResult
    func seedSupplementalSimulatorDemoDataIfNeeded(referenceDate: Date, isDemoMode: Bool) throws -> Bool {
        guard isDemoMode, hasSimulatorDemoConfiguration else { return false }
        let fixtures = SimulatorDemoFixtures.snapshot(referenceDate: referenceDate)
        let calendar = Calendar.current
        let storedHabits = try modelContext.fetch(FetchDescriptor<SDHabit>())
        let storedRecords = try modelContext.fetch(FetchDescriptor<SDHabitRecord>())
        let storedAnniversaries = try modelContext.fetch(FetchDescriptor<SDAnniversary>())
        let storedHealth = try modelContext.fetch(FetchDescriptor<SDHealthSummary>())
        let storedMemos = try modelContext.fetch(FetchDescriptor<SDMemoPad>())
        let storedLetters = try modelContext.fetch(FetchDescriptor<SDLetter>())
        let storedPlaces = try modelContext.fetch(FetchDescriptor<SDShoppingPlace>())
        let storedItems = try modelContext.fetch(FetchDescriptor<SDShoppingItem>())
        var changed = false

        let habitIDs = Set(storedHabits.map(\.id))
        var habitOrder = (storedHabits.map(\.orderIndex).max() ?? -1) + 1
        for habit in fixtures.habits where !habitIDs.contains(habit.id) {
            let stored = SDHabit(domain: habit)
            stored.orderIndex = habitOrder
            habitOrder += 1
            modelContext.insert(stored)
            changed = true
        }
        let recordIDs = Set(storedRecords.map(\.id))
        for record in fixtures.habitRecords where !recordIDs.contains(record.id) &&
            !storedRecords.contains(where: { $0.habitID == record.habitID && calendar.isDate($0.date, inSameDayAs: record.date) }) {
            modelContext.insert(SDHabitRecord(domain: record))
            changed = true
        }
        let anniversaryIDs = Set(storedAnniversaries.map(\.id))
        var anniversaryOrder = (storedAnniversaries.map(\.orderIndex).max() ?? -1) + 1
        for anniversary in fixtures.anniversaries where !anniversaryIDs.contains(anniversary.id) {
            let stored = SDAnniversary(domain: anniversary)
            stored.orderIndex = anniversaryOrder
            anniversaryOrder += 1
            modelContext.insert(stored)
            changed = true
        }
        let healthDates = Set(storedHealth.map { calendar.startOfDay(for: $0.date) })
        let healthIDs = Set(storedHealth.map(\.id))
        // Fill the new preview-only health fields on existing owned demo days.
        // Their saved measurements and any non-demo summaries stay intact.
        for fixture in fixtures.healthSummaries {
            guard let stored = storedHealth.first(where: { $0.id == fixture.id }) else { continue }
            if stored.fitnessMoveModeRaw == nil {
                stored.activeEnergyGoal = fixture.activeEnergyGoal
                stored.moveMinutesGoal = fixture.moveMinutesGoal
                stored.exerciseMinutesGoal = fixture.exerciseMinutesGoal
                stored.standHoursGoal = fixture.standHoursGoal
                stored.fitnessMoveModeRaw = fixture.fitnessMoveMode?.rawValue
                changed = true
            }
            if stored.sleepStages.isEmpty,
               stored.sleepHours == fixture.sleepHours,
               stored.sleepEnd == fixture.sleepEnd {
                stored.sleepStart = fixture.sleepStart
                stored.sleepStages = fixture.sleepStages
                changed = true
            }
        }
        for health in fixtures.healthSummaries where !healthDates.contains(calendar.startOfDay(for: health.date)) &&
            !healthIDs.contains(health.id) {
            modelContext.insert(SDHealthSummary(domain: health))
            changed = true
        }
        if let memo = storedMemos.first {
            if memo.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                memo.text = fixtures.memo.text
                memo.lastUpdatedAt = fixtures.memo.lastUpdatedAt
                changed = true
            }
        } else {
            modelContext.insert(SDMemoPad(text: fixtures.memo.text, lastUpdatedAt: fixtures.memo.lastUpdatedAt))
            changed = true
        }
        let letterIDs = Set(storedLetters.map(\.id))
        for letter in fixtures.letters where !letterIDs.contains(letter.id) {
            // Direct local persistence keeps this draft away from delivery,
            // notification, pairing, and account integration paths.
            modelContext.insert(SDLetter(domain: letter))
            changed = true
        }
        let placeIDs = Set(storedPlaces.map(\.id))
        var placeOrder = (storedPlaces.map(\.orderIndex).max() ?? -1) + 1
        for place in fixtures.shoppingPlaces where !placeIDs.contains(place.id) {
            modelContext.insert(SDShoppingPlace(id: place.id, name: place.name, orderIndex: placeOrder))
            placeOrder += 1
            changed = true
        }
        let itemIDs = Set(storedItems.map(\.id))
        for item in fixtures.shoppingItems where !itemIDs.contains(item.id) {
            modelContext.insert(SDShoppingItem(domain: item))
            changed = true
        }
        guard changed else { return false }
        try modelContext.save()
        habits = try modelContext.fetch(FetchDescriptor<SDHabit>(sortBy: [SortDescriptor(\.orderIndex)]))
            .map { Habit(sd: $0) }
        habitRecords = try modelContext.fetch(FetchDescriptor<SDHabitRecord>()).map { HabitRecord(sd: $0) }
        anniversaries = try modelContext.fetch(FetchDescriptor<SDAnniversary>(sortBy: [SortDescriptor(\.orderIndex)]))
            .map { Anniversary(sd: $0) }
        try reloadSimulatorDemoHealthSummaries()
        if let memo = try modelContext.fetch(FetchDescriptor<SDMemoPad>()).first { memoPad = MemoPad(sd: memo) }
        letters = try modelContext.fetch(FetchDescriptor<SDLetter>()).map { Letter(sd: $0) }
        try shoppingStore.reload()
        return true
    }
}
#endif
