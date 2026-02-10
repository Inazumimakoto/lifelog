//
//  NotificationService.swift
//  lifelog
//
//  Created by Codex on 2025/12/06.
//

import Foundation
import UserNotifications

/// 通知タイプの識別子
enum NotificationType: String {
    case event = "event"
    case externalEvent = "external-event"
    case task = "task"
    case anniversary = "anniversary"
    case diary = "diary"
    case todayOverview = "today-overview"
}

/// ローカル通知を管理するサービス
class NotificationService {
    static let shared = NotificationService()
    
    private let center = UNUserNotificationCenter.current()
    
    private init() {}
    
    // MARK: - 通知許可
    
    /// 通知許可をリクエスト
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("通知許可リクエストエラー: \(error)")
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
        
        let notificationDate = startDate.addingTimeInterval(-Double(minutesBefore * 60))
        guard notificationDate > Date() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "予定のリマインダー"
        content.body = title
        content.sound = .default
        
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: notificationDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let identifier = "\(NotificationType.event.rawValue)-\(eventId.uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        center.add(request) { error in
            if let error = error {
                print("予定通知スケジュールエラー: \(error)")
            }
        }
    }
    
    /// 予定の通知をスケジュール（日時指定）
    func scheduleEventReminderAtDate(eventId: UUID, title: String, reminderDate: Date) {
        guard reminderDate > Date() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "予定のリマインダー"
        content.body = title
        content.sound = .default
        
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let identifier = "\(NotificationType.event.rawValue)-\(eventId.uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        center.add(request) { error in
            if let error = error {
                print("予定通知スケジュールエラー: \(error)")
            }
        }
    }
    
    /// 予定の通知をキャンセル
    func cancelEventReminder(eventId: UUID) {
        let identifier = "\(NotificationType.event.rawValue)-\(eventId.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// 外部予定の通知をスケジュール
    func scheduleExternalEventReminder(externalEventKey: String, title: String, startDate: Date, minutesBefore: Int) {
        guard minutesBefore > 0 else { return }

        let notificationDate = startDate.addingTimeInterval(-Double(minutesBefore * 60))
        guard notificationDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "予定のリマインダー"
        content.body = title
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: notificationDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let identifier = "\(NotificationType.externalEvent.rawValue)-\(externalEventKey)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                print("外部予定通知スケジュールエラー: \(error)")
            }
        }
    }

    /// 外部予定の通知をスケジュール（日時指定）
    func scheduleExternalEventReminderAtDate(externalEventKey: String, title: String, reminderDate: Date) {
        guard reminderDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "予定のリマインダー"
        content.body = title
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let identifier = "\(NotificationType.externalEvent.rawValue)-\(externalEventKey)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                print("外部予定通知スケジュールエラー: \(error)")
            }
        }
    }
    
    // MARK: - タスクリマインダー
    
    /// タスクの通知をスケジュール
    func scheduleTaskReminder(taskId: UUID, title: String, reminderDate: Date) {
        guard reminderDate > Date() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "タスクのリマインダー"
        content.body = title
        content.sound = .default
        
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let identifier = "\(NotificationType.task.rawValue)-\(taskId.uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        center.add(request) { error in
            if let error = error {
                print("タスク通知スケジュールエラー: \(error)")
            }
        }
    }
    
    /// タスクの通知をキャンセル
    func cancelTaskReminder(taskId: UUID) {
        let identifier = "\(NotificationType.task.rawValue)-\(taskId.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
    
    // MARK: - 記念日リマインダー
    
    /// 記念日の通知をスケジュール
    func scheduleAnniversaryReminder(anniversaryId: UUID, title: String, targetDate: Date, daysBefore: Int, time: Date, repeatsYearly: Bool = false) {
        let calendar = Calendar.current
        
        // 次の記念日を計算（今年または来年）
        var nextDate = targetDate
        let today = Date()
        while nextDate < today {
            nextDate = calendar.date(byAdding: .year, value: 1, to: nextDate) ?? nextDate
        }
        
        // 通知日を計算
        guard let reminderDate = calendar.date(byAdding: .day, value: -daysBefore, to: nextDate) else { return }
        
        // 時間を設定
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        var dateComponents = calendar.dateComponents([.month, .day], from: reminderDate)
        dateComponents.hour = timeComponents.hour
        dateComponents.minute = timeComponents.minute
        
        // 毎年繰り返さない場合は年も指定
        if !repeatsYearly {
            dateComponents.year = calendar.component(.year, from: reminderDate)
            // 過去の日付ならスキップ
            guard let finalDate = calendar.date(from: dateComponents), finalDate > today else { return }
        }
        
        let content = UNMutableNotificationContent()
        if daysBefore == 0 {
            content.title = "今日は記念日です"
        } else {
            content.title = "記念日まであと\(daysBefore)日"
        }
        content.body = title
        content.sound = .default
        
        // repeatsYearly: 毎年繰り返す（年を含めないtrigger）
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: repeatsYearly)
        
        let identifier = "\(NotificationType.anniversary.rawValue)-\(anniversaryId.uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        center.add(request) { error in
            if let error = error {
                print("記念日通知スケジュールエラー: \(error)")
            }
        }
    }
    
    /// 記念日の通知をキャンセル
    func cancelAnniversaryReminder(anniversaryId: UUID) {
        let identifier = "\(NotificationType.anniversary.rawValue)-\(anniversaryId.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
    
    /// 記念日の通知をスケジュール（日時指定）
    func scheduleAnniversaryReminderAtDate(anniversaryId: UUID, title: String, reminderDate: Date) {
        guard reminderDate > Date() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "記念日のリマインダー"
        content.body = title
        content.sound = .default
        
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let identifier = "\(NotificationType.anniversary.rawValue)-\(anniversaryId.uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        center.add(request) { error in
            if let error = error {
                print("記念日通知スケジュールエラー: \(error)")
            }
        }
    }
    
    // MARK: - 日記リマインダー
    
    private let diaryReminderIdentifier = "diary-daily-reminder"
    private let todayOverviewReminderIdentifier = "today-overview-reminder"
    
    /// 日記リマインダーをスケジュール（翌日以降の次の通知時刻）
    func scheduleDiaryReminder(hour: Int, minute: Int) {
        // まずキャンセル
        cancelDiaryReminder()
        
        let calendar = Calendar.current
        let now = Date()
        
        // 今日の指定時刻を計算
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: now)
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        guard var targetDate = calendar.date(from: dateComponents) else { return }
        
        // 今日の時刻が過ぎていれば翌日にする
        if targetDate <= now {
            targetDate = calendar.date(byAdding: .day, value: 1, to: targetDate) ?? targetDate
        }
        
        let content = UNMutableNotificationContent()
        content.title = "日記を書きましょう"
        content.body = "今日の出来事を振り返ってみませんか？"
        content.sound = .default
        
        let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: targetDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        let request = UNNotificationRequest(identifier: diaryReminderIdentifier, content: content, trigger: trigger)
        
        center.add(request) { error in
            if let error = error {
                print("日記通知スケジュールエラー: \(error)")
            }
        }
    }
    
    /// 日記リマインダーをキャンセル
    func cancelDiaryReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [diaryReminderIdentifier])
    }

    // MARK: - 今日の予定・タスク通知

    /// 今日の予定・タスク通知をスケジュール（次回1件のみ）
    func scheduleTodayOverviewReminder(fireDate: Date, body: String) {
        guard fireDate > Date() else { return }

        cancelTodayOverviewReminder()

        let content = UNMutableNotificationContent()
        content.title = "今日の予定・タスク"
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: todayOverviewReminderIdentifier, content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                print("今日の予定・タスク通知スケジュールエラー: \(error)")
            }
        }
    }

    /// 今日の予定・タスク通知をキャンセル
    func cancelTodayOverviewReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [todayOverviewReminderIdentifier])
    }
    
    // MARK: - 全通知管理
    
    /// 特定タイプの全通知をキャンセル
    func cancelAllReminders(ofType type: NotificationType, completion: (() -> Void)? = nil) {
        center.getPendingNotificationRequests { requests in
            let identifiers = requests
                .filter { $0.identifier.hasPrefix(type.rawValue) }
                .map { $0.identifier }
            self.center.removePendingNotificationRequests(withIdentifiers: identifiers)
            completion?()
        }
    }
}
