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

    @StateObject private var appLockService = AppLockService.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(store)
                    .environment(\.locale, Locale(identifier: "ja_JP"))
                    .onAppear {
                        // 日記リマインダーを再スケジュール（今日書いていなければ通知）
                        store.rescheduleDiaryReminderIfNeeded()
                    }
                
                if !appLockService.isUnlocked && appLockService.isAppLockEnabled {
                    LockView()
                        .transition(.opacity)
                        .zIndex(999)
                }
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .inactive || newPhase == .background {
                    appLockService.lock()
                } else if newPhase == .active {
                    // アプリがアクティブになった時にロックが有効なら認証を試みる
                    if appLockService.isAppLockEnabled && !appLockService.isUnlocked {
                        appLockService.authenticate()
                    }
                }
            }
        }
    }
}
