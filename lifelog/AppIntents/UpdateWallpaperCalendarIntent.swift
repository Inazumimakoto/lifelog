//
//  UpdateWallpaperCalendarIntent.swift
//  lifelog
//
//  Created by Codex on 2026/04/27.
//

import AppIntents
import Foundation
import UniformTypeIdentifiers

struct UpdateWallpaperCalendarIntent: AppIntent {
    static var title: LocalizedStringResource = "壁紙カレンダーを更新"
    static var description = IntentDescription("ロック画面用のカレンダー画像を作成します。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let url = try await MainActor.run {
            try WallpaperCalendarRenderer().render(force: false)
        }
        let data = try Data(contentsOf: url)
        let file = IntentFile(
            data: data,
            filename: "lifelify-wallpaper-calendar.jpg",
            type: .jpeg
        )
        return .result(value: file, dialog: "壁紙カレンダーを作成しました。")
    }
}

struct LifelogShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: UpdateWallpaperCalendarIntent(),
            phrases: [
                "\(.applicationName)で壁紙カレンダーを更新",
                "\(.applicationName)のロック画面カレンダーを更新"
            ],
            shortTitle: "壁紙カレンダーを更新",
            systemImageName: "calendar"
        )
    }

    static var shortcutTileColor: ShortcutTileColor {
        .blue
    }
}
