//
//  lifelogApp.swift
//  lifelog
//
//  Created by inazumimakoto on 2025/11/13.
//

import SwiftUI
import UserNotifications

/// 通知タップをハンドリングするデリゲート
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    
    /// フォアグラウンドで通知を受信した場合の処理
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // フォアグラウンドでもバナーとサウンドを表示
        completionHandler([.banner, .sound])
    }
    
    /// 通知をタップした時の処理
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        // 手紙の通知かチェック
        if let letterIDString = userInfo["letterID"] as? String,
           let letterID = UUID(uuidString: letterIDString) {
            // メインスレッドで DeepLinkManager を更新
            DispatchQueue.main.async {
                DeepLinkManager.shared.handleLetterNotification(letterID: letterID)
            }
        }
        
        completionHandler()
    }
}

@main
struct lifelogApp: App {
    @StateObject private var store = AppDataStore()
    @StateObject private var deepLinkManager = DeepLinkManager.shared
    
    /// 通知デリゲート（強参照で保持）
    private let notificationDelegate = NotificationDelegate()

    init() {
        CategoryPalette.initializeIfNeeded()
        
        // 通知デリゲートを設定
        UNUserNotificationCenter.current().delegate = notificationDelegate
        
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
                    .environmentObject(deepLinkManager)
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
