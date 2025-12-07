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

// CalendarCategoryLink moved to Models.swift for shared access
