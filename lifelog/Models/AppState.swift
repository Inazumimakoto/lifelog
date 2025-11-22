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
}
