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
        saveContext()
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
        saveContext()
        reloadHabitWidgetTimeline()
    }

    func addHabit(_ habit: Habit) {
        let newIndex = habits.count
        habits.append(habit)
        persistHabits()

        let sdHabit = SDHabit(domain: habit)
        sdHabit.orderIndex = newIndex
        modelContext.insert(sdHabit)
        saveContext()
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
             saveContext()
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
             saveContext()
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
        saveContext()
        reloadHabitWidgetTimeline()
    }

    // MARK: - Habit Widget Helper

    func reloadHabitWidgetTimeline() {
        WidgetCenter.shared.reloadTimelines(ofKind: "HabitWidget")
    }

    // MARK: - Habit Persisters

    func persistHabits() {
        persist(habits, forKey: Self.habitsDefaultsKey)
    }

    func persistHabitRecords() {
        persist(habitRecords, forKey: Self.habitRecordsDefaultsKey)
    }

}
