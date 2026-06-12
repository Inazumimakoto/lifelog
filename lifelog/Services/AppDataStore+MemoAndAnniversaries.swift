//
//  AppDataStore+MemoAndAnniversaries.swift
//  lifelog
//

import Foundation
import SwiftData
import SwiftUI
import WidgetKit

extension AppDataStore {

    // MARK: - Anniversaries

    func addAnniversary(_ anniversary: Anniversary) {
        let newIndex = anniversaries.count
        anniversaries.append(anniversary)
        scheduleAnniversaryNotification(anniversary)

        let sdItem = SDAnniversary(domain: anniversary)
        sdItem.orderIndex = newIndex
        modelContext.insert(sdItem)
        saveContext()
        reloadAnniversaryWidgetTimeline()
    }

    func updateAnniversary(_ anniversary: Anniversary) {
        guard let index = anniversaries.firstIndex(where: { $0.id == anniversary.id }) else { return }
        anniversaries[index] = anniversary
        scheduleAnniversaryNotification(anniversary)

        let id = anniversary.id
        let descriptor = FetchDescriptor<SDAnniversary>(predicate: #Predicate { $0.id == id })
        if let existing = try? modelContext.fetch(descriptor).first {
             existing.update(from: anniversary)
             saveContext()
        }
        reloadAnniversaryWidgetTimeline()
    }

    func deleteAnniversary(_ anniversaryID: UUID) {
        anniversaries.removeAll { $0.id == anniversaryID }
        NotificationService.shared.cancelAnniversaryReminder(anniversaryId: anniversaryID)

        let descriptor = FetchDescriptor<SDAnniversary>(predicate: #Predicate { $0.id == anniversaryID })
        if let existing = try? modelContext.fetch(descriptor).first {
             modelContext.delete(existing)
             saveContext()
        }
        reloadAnniversaryWidgetTimeline()
    }

    func moveAnniversary(from source: IndexSet, to destination: Int) {
        anniversaries.move(fromOffsets: source, toOffset: destination)

        for (index, item) in anniversaries.enumerated() {
             let id = item.id
             let descriptor = FetchDescriptor<SDAnniversary>(predicate: #Predicate { $0.id == id })
             if let existing = try? modelContext.fetch(descriptor).first {
                 if existing.orderIndex != index {
                     existing.orderIndex = index
                 }
             }
        }
        saveContext()
        reloadAnniversaryWidgetTimeline()
    }

    // MARK: - Memo Pad

    func updateMemoPad(text: String, syncSwiftData: Bool = true) {
        // syncSwiftData == false は打鍵ごとの軽量パス。下書きの
        // UserDefaults 書き込みは読み戻し処理のない死に書き込みだったため
        // 削除した(確定保存はエディタを閉じる時の true 呼び出しが行う)。
        if syncSwiftData == false {
            return
        }

        if text != memoPad.text {
            memoPad.text = text
            memoPad.lastUpdatedAt = Date()
        } else {
            guard syncSwiftData else { return }
        }
        persistMemoPad()
    }

    func persistMemoPad() {
        // SwiftData
        let descriptor = FetchDescriptor<SDMemoPad>()
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.text = memoPad.text
            existing.lastUpdatedAt = memoPad.lastUpdatedAt
        } else {
             let newPad = SDMemoPad(text: memoPad.text, lastUpdatedAt: memoPad.lastUpdatedAt)
             modelContext.insert(newPad)
        }
        saveContext()
    }

    // MARK: - App State


    func persistAppState() {
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
        saveContext()
    }

    // MARK: - Anniversary Notification Helper

    func scheduleAnniversaryNotification(_ anniversary: Anniversary) {
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

    // MARK: - Anniversary Widget Helper

    func reloadAnniversaryWidgetTimeline() {
        WidgetCenter.shared.reloadTimelines(ofKind: "AnniversaryWidget")
    }

    // MARK: - Anniversary Persister

}
