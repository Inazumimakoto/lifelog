//
//  AppDataStore+Notifications.swift
//  lifelog
//

import Foundation
import UserNotifications
import os

extension AppDataStore {

    /// Recreate existing reservations once when iOS starts accepting them again.
    func restoreRemindersAfterNotificationAuthorization(referenceDate: Date = Date()) {
        guard areNotificationUpdatesEnabled else { return }
        rescheduleDiaryReminderIfNeeded(referenceDate: referenceDate)
        rescheduleTodayOverviewReminderIfNeeded(referenceDate: referenceDate)
        reapplyEventCategoryNotificationSettings(referenceDate: referenceDate)
        for task in tasks where !task.isCompleted {
            if let reminderDate = task.reminderDate, reminderDate > referenceDate {
                taskNotificationService.scheduleTaskReminder(taskId: task.id, title: task.title, reminderDate: reminderDate)
            }
        }
        for anniversary in anniversaries where anniversary.reminderDate != nil || anniversary.reminderDaysBefore != nil {
            scheduleAnniversaryNotification(anniversary)
        }
        syncLetterDeliveryNotifications(referenceDate: referenceDate)
    }

    // MARK: - Diary Reminder Settings

    // Older Settings screens saved these preferences in UserDefaults. Reads are
    // side-effect free so an unavailable SwiftData record can't be overwritten.
    var diaryReminderEnabled: Bool {
        diaryReminderDefaults?.object(forKey: "diaryReminderEnabled") as? Bool ?? appState.diaryReminderEnabled
    }
    var diaryReminderHour: Int {
        diaryReminderDefaults?.object(forKey: "diaryReminderHour") as? Int ?? appState.diaryReminderHour
    }
    var diaryReminderMinute: Int {
        diaryReminderDefaults?.object(forKey: "diaryReminderMinute") as? Int ?? appState.diaryReminderMinute
    }

    func updateDiaryReminder(enabled: Bool, hour: Int, minute: Int) {
        diaryReminderDefaults?.set(enabled, forKey: "diaryReminderEnabled")
        diaryReminderDefaults?.set(hour, forKey: "diaryReminderHour")
        diaryReminderDefaults?.set(minute, forKey: "diaryReminderMinute")
        appState.diaryReminderEnabled = enabled
        appState.diaryReminderHour = hour
        appState.diaryReminderMinute = minute
        persistAppState()

        rescheduleDiaryReminderIfNeeded()
    }

    /// アプリ起動時に日記リマインダーを再スケジュール（今日書いていなければ）
    func rescheduleDiaryReminderIfNeeded(referenceDate: Date = Date()) {
        guard areNotificationUpdatesEnabled else { return }
        guard hasLoadedAppState || diaryReminderDefaults?.object(forKey: "diaryReminderEnabled") != nil else { return }
        guard diaryReminderEnabled else {
            dailyNotificationService.cancelDiaryReminder()
            return
        }

        // 今日の日記があるかチェック
        let today = referenceDate
        let hasTodayEntry = diaryEntries.contains { entry in
            Calendar.current.isDate(entry.date, inSameDayAs: today) && !entry.text.isEmpty
        }

        let calendar = Calendar.current
        var targetDay = calendar.startOfDay(for: today)
        guard let todayFireDate = calendar.date(bySettingHour: diaryReminderHour, minute: diaryReminderMinute,
                                                second: 0, of: targetDay) else { return }
        if hasTodayEntry || todayFireDate <= today {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: targetDay) else { return }
            targetDay = tomorrow
        }
        // Select the day before resolving the clock time: a nonexistent time on
        // today's DST transition must not change tomorrow's configured hour.
        guard let targetDate = calendar.date(bySettingHour: diaryReminderHour, minute: diaryReminderMinute,
                                             second: 0, of: targetDay) else { return }
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: targetDate)
        dailyNotificationService.scheduleDiaryReminder(components: components)
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
        guard areNotificationUpdatesEnabled else { return }
        guard todayOverviewNotificationEnabled else {
            dailyNotificationService.cancelTodayOverviewReminder()
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
        dailyNotificationService.scheduleTodayOverviewReminder(fireDate: fireDate, body: body)
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
