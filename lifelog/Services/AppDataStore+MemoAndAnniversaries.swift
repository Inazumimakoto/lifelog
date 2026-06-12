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
        persistAnniversaries()
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
        persistAnniversaries()
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
        persistAnniversaries()
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
        saveContext()
        reloadAnniversaryWidgetTimeline()
    }

    // MARK: - Memo Pad

    func updateMemoPad(text: String, syncSwiftData: Bool = true) {
        if syncSwiftData == false {
            persistMemoPadDraft(text: text)
            return
        }

        if text != memoPad.text {
            memoPad.text = text
            memoPad.lastUpdatedAt = Date()
        } else {
            guard syncSwiftData else { return }
        }
        persistMemoPad(syncSwiftData: syncSwiftData)
    }

    private func persistMemoPadDraft(text: String) {
        var draft = memoPad
        if text != draft.text {
            draft.text = text
            draft.lastUpdatedAt = Date()
        }
        if let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: Self.memoPadDefaultsKey)
        }
    }

    private static func loadMemoPad() -> MemoPad {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: memoPadDefaultsKey),
           let memo = try? JSONDecoder().decode(MemoPad.self, from: data) {
            return memo
        }
        return MemoPad()
    }

    func persistMemoPad(syncSwiftData: Bool = true) {
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
        saveContext()
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

    func persistAppState() {
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

    func persistAnniversaries() {
        persist(anniversaries, forKey: Self.anniversariesDefaultsKey)
    }

}
