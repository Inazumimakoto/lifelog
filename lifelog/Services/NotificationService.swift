//
//  NotificationService.swift
//  lifelog
//
//  Created by Codex on 2025/12/06.
//

import Foundation
import UserNotifications
import UIKit
import os

/// 通知タイプの識別子
enum NotificationType: String {
    case event = "event"
    case externalEvent = "external-event"
    case recurringEvent = "recurring-event"
    case task = "task"
    case anniversary = "anniversary"
    case diary = "diary"
    case todayOverview = "today-overview"
}

/// ローカル通知を管理するサービス
class NotificationService {
    static let shared = NotificationService()
    
    private let center = UNUserNotificationCenter.current()
    private let referenceDate: () -> Date
    private let requestHandler: ((UNNotificationRequest) -> Void)?
    private let cancellationHandler: (([String]) -> Void)?
    private var injectedPendingIdentifiers: Set<String> = []

    init(referenceDate: @escaping () -> Date = { Date() },
         requestHandler: ((UNNotificationRequest) -> Void)? = nil,
         cancellationHandler: (([String]) -> Void)? = nil) {
        self.referenceDate = referenceDate
        self.requestHandler = requestHandler
        self.cancellationHandler = cancellationHandler
    }

    // This service has no actor-bound teardown. Avoid Swift 6.2's crashing
    // MainActor back-deployment deinit when synchronous callers release it.
    nonisolated deinit {}
    
    // MARK: - 通知許可
    
    /// 通知許可をリクエスト
    func requestAuthorization(registerForRemoteNotifications: Bool = false) async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted && registerForRemoteNotifications {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            return granted
        } catch {
            AppLogger.notifications.error("通知許可リクエストエラー: \(error)")
            return false
        }
    }
    
    /// 現在の通知許可状態を取得
    func getAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }
    
    // MARK: - 予定リマインダー
    
    /// 予定の通知をスケジュール
    func scheduleEventReminder(eventId: UUID, title: String, startDate: Date, minutesBefore: Int) {
        guard minutesBefore > 0 else { return }
        scheduleEventReminderAtDate(eventId: eventId, title: title,
                                    reminderDate: startDate.addingTimeInterval(-Double(minutesBefore * 60)))
    }

    /// 予定の通知をスケジュール（日時指定）
    func scheduleEventReminderAtDate(eventId: UUID, title: String, reminderDate: Date) {
        scheduleOneTimeReminder(identifier: identifier(for: .event, key: eventId.uuidString),
                                title: String(localized: "予定のリマインダー"), body: title,
                                fireDate: reminderDate, errorMessage: "予定通知スケジュールエラー")
    }

    /// 予定の通知をキャンセル
    func cancelEventReminder(eventId: UUID) {
        cancel(identifier: identifier(for: .event, key: eventId.uuidString))
    }

    func scheduleRecurringEventReminder(occurrenceID: UUID, title: String, reminderDate: Date) {
        scheduleOneTimeReminder(identifier: identifier(for: .recurringEvent, key: occurrenceID.uuidString),
                                title: String(localized: "予定のリマインダー"), body: title,
                                fireDate: reminderDate, errorMessage: "繰り返し予定通知スケジュールエラー")
    }

    /// 外部予定の通知をスケジュール
    func scheduleExternalEventReminder(externalEventKey: String, title: String, startDate: Date, minutesBefore: Int) {
        guard minutesBefore > 0 else { return }
        scheduleExternalEventReminderAtDate(externalEventKey: externalEventKey, title: title,
                                            reminderDate: startDate.addingTimeInterval(-Double(minutesBefore * 60)))
    }

    /// 外部予定の通知をスケジュール（日時指定）
    func scheduleExternalEventReminderAtDate(externalEventKey: String, title: String, reminderDate: Date) {
        scheduleOneTimeReminder(identifier: identifier(for: .externalEvent, key: externalEventKey),
                                title: String(localized: "予定のリマインダー"), body: title,
                                fireDate: reminderDate, errorMessage: "外部予定通知スケジュールエラー")
    }
    /// Disabling a default can cancel its cached request without scheduling or requesting permission.
    func cancelExternalEventReminder(externalEventKey: String) {
        cancel(identifier: identifier(for: .externalEvent, key: externalEventKey))
    }

    // MARK: - タスクリマインダー
    
    /// タスクの通知をスケジュール
    func scheduleTaskReminder(taskId: UUID, title: String, reminderDate: Date) {
        scheduleOneTimeReminder(identifier: identifier(for: .task, key: taskId.uuidString),
                                title: String(localized: "タスクのリマインダー"), body: title,
                                fireDate: reminderDate, errorMessage: "タスク通知スケジュールエラー")
    }
    
    /// タスクの通知をキャンセル
    func cancelTaskReminder(taskId: UUID) {
        cancel(identifier: identifier(for: .task, key: taskId.uuidString))
    }
    
    // MARK: - 記念日リマインダー
    
    /// 記念日の通知をスケジュール
    func scheduleAnniversaryReminder(anniversaryId: UUID, title: String, targetDate: Date, daysBefore: Int, time: Date, repeatsYearly: Bool = false, calendar: Calendar = .current) {
        
        // 次の記念日を計算（今年または来年）
        var nextDate = targetDate
        let today = referenceDate()
        while repeatsYearly && nextDate < today {
            nextDate = calendar.date(byAdding: .year, value: 1, to: nextDate) ?? nextDate
        }
        
        // 通知日を計算
        guard let reminderDate = calendar.date(byAdding: .day, value: -daysBefore, to: nextDate) else { return }
        
        // 時間を設定
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        var dateComponents = calendar.dateComponents([.month, .day], from: reminderDate)
        dateComponents.hour = timeComponents.hour
        dateComponents.minute = timeComponents.minute
        dateComponents.calendar = calendar
        dateComponents.timeZone = calendar.timeZone
        
        // 毎年繰り返さない場合は年も指定
        if !repeatsYearly {
            dateComponents.year = calendar.component(.year, from: reminderDate)
            // 過去の日付ならスキップ
            guard let finalDate = calendar.date(from: dateComponents), finalDate > today else { return }
        }
        
        let notificationTitle: String
        if daysBefore == 0 {
            notificationTitle = String(localized: "今日は記念日です")
        } else {
            notificationTitle = String(localized: "記念日まであと\(daysBefore)日")
        }
        scheduleCalendarNotification(identifier: identifier(for: .anniversary, key: anniversaryId.uuidString),
                                     title: notificationTitle, body: title,
                                     components: dateComponents, repeats: repeatsYearly,
                                     errorMessage: "記念日通知スケジュールエラー")
    }

    /// 記念日の通知をキャンセル
    func cancelAnniversaryReminder(anniversaryId: UUID) {
        cancel(identifier: identifier(for: .anniversary, key: anniversaryId.uuidString))
    }
    
    /// 記念日の通知をスケジュール（日時指定）
    func scheduleAnniversaryReminderAtDate(anniversaryId: UUID, title: String, reminderDate: Date) {
        scheduleOneTimeReminder(identifier: identifier(for: .anniversary, key: anniversaryId.uuidString),
                                title: String(localized: "記念日のリマインダー"), body: title,
                                fireDate: reminderDate, errorMessage: "記念日通知スケジュールエラー")
    }

    // MARK: - 日記リマインダー
    
    private let diaryReminderIdentifier = "diary-daily-reminder"
    private let todayOverviewReminderIdentifier = "today-overview-reminder"
    
    /// 日記リマインダーをスケジュール（翌日以降の次の通知時刻）
    func scheduleDiaryReminder(hour: Int, minute: Int) {
        // まずキャンセル
        cancelDiaryReminder()
        
        let calendar = Calendar.current
        let now = referenceDate()
        
        // 今日の指定時刻を計算
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: now)
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        guard var targetDate = calendar.date(from: dateComponents) else { return }
        
        // 今日の時刻が過ぎていれば翌日にする
        if targetDate <= now {
            targetDate = calendar.date(byAdding: .day, value: 1, to: targetDate) ?? targetDate
        }
        
        let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: targetDate)
        scheduleDiaryReminder(components: triggerComponents)
    }

    /// 日記リマインダーをスケジュール（通知対象日の計算は呼び出し元で行う）
    func scheduleDiaryReminder(components: DateComponents) {
        scheduleCalendarNotification(identifier: diaryReminderIdentifier,
                                     title: String(localized: "日記を書きましょう"),
                                     body: String(localized: "今日の出来事を振り返ってみませんか？"),
                                     components: components,
                                     errorMessage: "日記通知スケジュールエラー")
    }
    
    /// 日記リマインダーをキャンセル
    func cancelDiaryReminder() {
        cancel(identifier: diaryReminderIdentifier)
    }

    // MARK: - 今日の予定・タスク通知

    /// 今日の予定・タスク通知をスケジュール（次回1件のみ）
    func scheduleTodayOverviewReminder(fireDate: Date, body: String) {
        guard fireDate > referenceDate() else { return }

        cancelTodayOverviewReminder()

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        scheduleCalendarNotification(identifier: todayOverviewReminderIdentifier,
                                     title: String(localized: "今日の予定・タスク"), body: body,
                                     components: components,
                                     errorMessage: "今日の予定・タスク通知スケジュールエラー")
    }

    /// 今日の予定・タスク通知をキャンセル
    func cancelTodayOverviewReminder() {
        cancel(identifier: todayOverviewReminderIdentifier)
    }

    // MARK: - 共通の通知作成

    /// 通知ごとの日時判定・キャンセル方針を保ったまま、要求の作成と送信を共通化する。
    func scheduleCalendarNotification(identifier: String, title: String, body: String,
                                      components: DateComponents, repeats: Bool = false,
                                      userInfo: [AnyHashable: Any] = [:], errorMessage: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        if let requestHandler {
            injectedPendingIdentifiers.insert(identifier)
            requestHandler(request)
        } else {
            center.add(request) { error in
                if let error {
                    AppLogger.notifications.error("\(errorMessage): \(error)")
                }
            }
        }
    }

    private func scheduleOneTimeReminder(identifier: String, title: String, body: String,
                                         fireDate: Date, errorMessage: String) {
        guard fireDate > referenceDate() else { return }
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        scheduleCalendarNotification(identifier: identifier, title: title, body: body,
                                     components: components, errorMessage: errorMessage)
    }

    private func identifier(for type: NotificationType, key: String) -> String {
        "\(type.rawValue)-\(key)"
    }

    private func cancel(identifier: String) {
        injectedPendingIdentifiers.remove(identifier)
        if let cancellationHandler {
            cancellationHandler([identifier])
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
        }
    }
    
    // MARK: - 全通知管理
    
    /// 特定タイプの全通知をキャンセル
    func cancelAllReminders(ofType type: NotificationType, completion: (() -> Void)? = nil) {
        cancelAllReminders(ofTypes: [type], completion: completion)
    }

    func cancelAllReminders(ofTypes types: [NotificationType], shouldCancel: @escaping () -> Bool = { true },
                            completion: (() -> Void)? = nil) {
        let prefixes = types.map { $0.rawValue + "-" }
        if requestHandler != nil {
            guard shouldCancel() else { return }
            let identifiers = injectedPendingIdentifiers.filter { identifier in
                prefixes.contains { identifier.hasPrefix($0) }
            }
            injectedPendingIdentifiers.subtract(identifiers)
            cancellationHandler?(Array(identifiers))
            completion?()
            return
        }
        center.getPendingNotificationRequests { requests in
            let identifiers = requests
                .filter { request in prefixes.contains { request.identifier.hasPrefix($0) } }
                .map { $0.identifier }
            DispatchQueue.main.async {
                // Validate before cancellation too: an older asynchronous read
                // must not remove requests that a newer plan has just replaced.
                guard shouldCancel() else { return }
                self.center.removePendingNotificationRequests(withIdentifiers: identifiers)
                completion?()
            }
        }
    }
}
