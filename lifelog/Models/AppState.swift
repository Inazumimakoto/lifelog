//
//  AppState.swift
//  lifelog
//
//  Created by Codex on 2025/11/22.
//

import Foundation

struct AppState: Codable {
    /// 外部カレンダーを最後に同期した日時
    var lastCalendarSyncDate: Date? = nil
    /// iOSカレンダーとlifelogカテゴリの対応
    var calendarCategoryLinks: [CalendarCategoryLink] = []
    /// 日記リマインダー設定
    var diaryReminderEnabled: Bool = false
    var diaryReminderHour: Int = 21
    var diaryReminderMinute: Int = 0
}

struct CalendarCategoryLink: Identifiable, Codable, Equatable {
    /// EventKit の EKCalendar.calendarIdentifier
    let calendarIdentifier: String
    /// 表示用タイトル
    var calendarTitle: String
    /// 対応させる lifelog カテゴリ名（nilなら取り込まない）
    var categoryId: String?
    /// iOSカレンダーの色 (hex)
    var colorHex: String?

    var id: String { calendarIdentifier }
}
