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
    /// Keep choices for temporarily unavailable calendars outside the visible list.
    var unavailableCalendarCategoryLinks: [CalendarCategoryLink] = []
    /// 日記リマインダー設定
    var diaryReminderEnabled: Bool = false
    var diaryReminderHour: Int = 21
    var diaryReminderMinute: Int = 0
}

extension AppState {
    private enum CodingKeys: String, CodingKey {
        case lastCalendarSyncDate, calendarCategoryLinks, unavailableCalendarCategoryLinks
        case diaryReminderEnabled, diaryReminderHour, diaryReminderMinute
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        lastCalendarSyncDate = try values.decodeIfPresent(Date.self, forKey: .lastCalendarSyncDate)
        calendarCategoryLinks = try values.decodeIfPresent([CalendarCategoryLink].self, forKey: .calendarCategoryLinks) ?? []
        unavailableCalendarCategoryLinks = try values.decodeIfPresent(
            [CalendarCategoryLink].self, forKey: .unavailableCalendarCategoryLinks
        ) ?? []
        diaryReminderEnabled = try values.decodeIfPresent(Bool.self, forKey: .diaryReminderEnabled) ?? false
        diaryReminderHour = try values.decodeIfPresent(Int.self, forKey: .diaryReminderHour) ?? 21
        diaryReminderMinute = try values.decodeIfPresent(Int.self, forKey: .diaryReminderMinute) ?? 0
    }
}

// CalendarCategoryLink moved to Models.swift for shared access
