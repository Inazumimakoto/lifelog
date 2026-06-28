//
//  AppDataStore+Notifications.swift
//  lifelog
//

import Foundation
import UserNotifications
import os

extension AppDataStore {

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
        content.title = String(localized: "日記を書きましょう")
        content.body = String(localized: "今日の出来事を振り返ってみませんか？")
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "diary-daily-reminder", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                AppLogger.notifications.error("日記通知スケジュールエラー: \(error)")
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
            String(localized: "予定"),
            eventLines.joined(separator: "\n"),
            String(localized: "タスク"),
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
            return [String(localized: "なし")]
        }

        let listedLines = Array(normalizedEvents.prefix(limit)).map { event in
            todayOverviewEventLine(for: event, on: date)
        }
        let remainderCount = normalizedEvents.count - listedLines.count
        if remainderCount > 0 {
            return listedLines + [String(localized: "ほか\(remainderCount)件")]
        }
        return listedLines
    }

    private func summarizedTaskLines(_ tasks: [Task], limit: Int) -> [String] {
        let normalizedTitles = tasks.map(\.title)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard normalizedTitles.isEmpty == false else {
            return [String(localized: "なし")]
        }

        let listedLines = Array(normalizedTitles.prefix(limit)).map { "・\($0)" }
        let remainderCount = normalizedTitles.count - listedLines.count
        if remainderCount > 0 {
            return listedLines + [String(localized: "ほか\(remainderCount)件")]
        }
        return listedLines
    }

    private func todayOverviewEventLine(for event: CalendarEvent, on date: Date) -> String {
        let calendar = Calendar.current
        let timeLabel: String
        if event.isAllDay {
            timeLabel = String(localized: "終日")
        } else if calendar.isDate(event.startDate, inSameDayAs: date) {
            timeLabel = event.startDate.formattedTime()
        } else {
            timeLabel = String(localized: "継続")
        }
        return "・\(timeLabel) \(event.title)"
    }

}
