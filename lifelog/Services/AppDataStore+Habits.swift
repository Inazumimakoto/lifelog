//
//  AppDataStore+Habits.swift
//  lifelog
//

import Foundation
import SwiftData
import SwiftUI
import WidgetKit

extension AppDataStore {

    // MARK: - Habits

    func records(for date: Date) -> [HabitRecord] {
        habitRecords.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func toggleHabit(_ habitID: UUID, on date: Date) {
        let calendar = Calendar.current
        let dateDay = calendar.startOfDay(for: date)

        // Build the history index once; scanning every record for each streak
        // day made long-running habits block checkbox feedback on the main actor.
        var completedDays = HabitCompletionQuery.completedDays(for: habitID,
                                                                from: habitRecords,
                                                                calendar: calendar)
        let streakBefore = HabitCompletionQuery.currentDailyStreak(upTo: date,
                                                                  completedDays: completedDays,
                                                                  calendar: calendar)
        var isCompleting = true

        if let index = habitRecords.firstIndex(where: {
            $0.habitID == habitID && Calendar.current.isDate($0.date, inSameDayAs: date)
        }) {
            isCompleting = !habitRecords[index].isCompleted
            habitRecords[index].isCompleted.toggle()
        } else {
            let record = HabitRecord(habitID: habitID, date: date, isCompleted: true)
            habitRecords.append(record)
        }

        if isCompleting { backdateHabitCreationIfNeeded(habitID, on: dateDay, calendar: calendar) }
        persistHabitCompletion(habitID, on: date, calendar: calendar)

        // Haptic feedback
        if isCompleting {
            completedDays.insert(dateDay)
            let streakAfter = HabitCompletionQuery.currentDailyStreak(upTo: date,
                                                                     completedDays: completedDays,
                                                                     calendar: calendar)
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

    private func checkAllHabitsComplete(on date: Date) {
        let calendar = Calendar.current
        let activeHabits = habits.filter { !$0.isArchived && $0.schedule.isActive(on: date) }
        guard !activeHabits.isEmpty else { return }

        let completedIDs = HabitCompletionQuery.completedHabitIDs(on: date,
                                                                  from: habitRecords,
                                                                  calendar: calendar)
        let allComplete = activeHabits.allSatisfy { completedIDs.contains($0.id) }

        if allComplete {
            HapticManager.allHabitsComplete()
        }
    }

    func setHabitCompletion(_ habitID: UUID, on date: Date, completed: Bool) {
        let calendar = Calendar.current
        let dateDay = calendar.startOfDay(for: date)

        if completed { backdateHabitCreationIfNeeded(habitID, on: dateDay, calendar: calendar) }

        if let index = habitRecords.firstIndex(where: {
            $0.habitID == habitID && Calendar.current.isDate($0.date, inSameDayAs: date)
        }) {
            habitRecords[index].isCompleted = completed
        } else if completed {
            let record = HabitRecord(habitID: habitID, date: date, isCompleted: true)
            habitRecords.append(record)
        }

        persistHabitCompletion(habitID, on: date, calendar: calendar)
    }

    private func backdateHabitCreationIfNeeded(_ habitID: UUID, on dateDay: Date, calendar: Calendar) {
        guard let habitIndex = habits.firstIndex(where: { $0.id == habitID }) else { return }
        let createdDay = calendar.startOfDay(for: habits[habitIndex].createdAt)
        if dateDay < createdDay { habits[habitIndex].createdAt = dateDay }
    }

    /// Both completion entry points keep the first record for the day and its ID.
    private func persistHabitCompletion(_ habitID: UUID, on date: Date, calendar: Calendar) {
        if let updatedRecord = habitRecords.first(where: {
            $0.habitID == habitID && calendar.isDate($0.date, inSameDayAs: date)
        }) {
            let recordID = updatedRecord.id
            let descriptor = FetchDescriptor<SDHabitRecord>(predicate: #Predicate { $0.id == recordID })
            if let existingRecord = try? modelContext.fetch(descriptor).first {
                existingRecord.isCompleted = updatedRecord.isCompleted
            } else {
                modelContext.insert(SDHabitRecord(domain: updatedRecord))
            }
        }

        if let memoryHabit = habits.first(where: { $0.id == habitID }) {
            let habitID = memoryHabit.id
            let descriptor = FetchDescriptor<SDHabit>(predicate: #Predicate { $0.id == habitID })
            if let sdHabit = try? modelContext.fetch(descriptor).first,
               sdHabit.createdAt != memoryHabit.createdAt {
                sdHabit.createdAt = memoryHabit.createdAt
            }
        }
        saveContext()
        reloadHabitWidgetTimeline()
    }

    func addHabit(_ habit: Habit) {
        let newIndex = habits.count
        habits.append(habit)

        let sdHabit = SDHabit(domain: habit)
        sdHabit.orderIndex = newIndex
        modelContext.insert(sdHabit)
        saveContext()
        reloadHabitWidgetTimeline()
    }

    func updateHabit(_ habit: Habit) {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        habits[index] = habit

        let habitID = habit.id
        let descriptor = FetchDescriptor<SDHabit>(predicate: #Predicate { $0.id == habitID })
        if let existing = try? modelContext.fetch(descriptor).first {
             existing.update(from: habit)
             saveContext()
        }
        reloadHabitWidgetTimeline()
    }

    func deleteHabit(_ habitID: UUID) {
        // Soft delete: archive the habit instead of removing it
        guard let index = habits.firstIndex(where: { $0.id == habitID }) else { return }
        habits[index].isArchived = true
        habits[index].archivedAt = Date()

        let descriptor = FetchDescriptor<SDHabit>(predicate: #Predicate { $0.id == habitID })
        if let existing = try? modelContext.fetch(descriptor).first {
             existing.isArchived = true
             existing.archivedAt = habits[index].archivedAt
             saveContext()
        }
        reloadHabitWidgetTimeline()
    }

    func moveHabit(from source: IndexSet, to destination: Int) {
        habits.move(fromOffsets: source, toOffset: destination)

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
        saveContext()
        reloadHabitWidgetTimeline()
    }

    // MARK: - Habit Widget Helper

    func reloadHabitWidgetTimeline() {
        WidgetCenter.shared.reloadTimelines(ofKind: "HabitWidget")
    }

    // MARK: - Habit Persisters

}
