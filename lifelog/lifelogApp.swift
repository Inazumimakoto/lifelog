//
//  lifelogApp.swift
//  lifelog
//
//  Created by inazumimakoto on 2025/11/13.
//

import SwiftUI

@main
struct lifelogApp: App {
    @StateObject private var store = AppDataStore()

    init() {
        CategoryPalette.initializeIfNeeded()
        
        // 通知許可をリクエスト
        _Concurrency.Task {
            let granted = await NotificationService.shared.requestAuthorization()
            if granted {
                print("✅ 通知許可が取得されました")
            } else {
                print("❌ 通知許可が拒否されました")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .onAppear {
                    // 日記リマインダーを再スケジュール（今日書いていなければ通知）
                    store.rescheduleDiaryReminderIfNeeded()
                }
        }
    }
}
