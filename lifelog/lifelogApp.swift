//
//  lifelogApp.swift
//  lifelog
//
//  Created by inazumimakoto on 2025/11/13.
//

import SwiftUI
import UserNotifications
import FirebaseCore
import FirebaseMessaging

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
        
        // 共有手紙の通知かチェック（Cloud Functionsから送信）
        if let type = userInfo["type"] as? String,
           type == "letter",
           let letterIdString = userInfo["letterId"] as? String {
            DispatchQueue.main.async {
                DeepLinkManager.shared.handleSharedLetterNotification(letterID: letterIdString)
            }
            completionHandler()
            return
        }
        
        // 未来への手紙の通知かチェック（ローカル通知）
        if let letterIDString = userInfo["letterID"] as? String,
           let letterID = UUID(uuidString: letterIDString) {
            DispatchQueue.main.async {
                DeepLinkManager.shared.handleLetterNotification(letterID: letterID)
            }
        }
        
        completionHandler()
    }
}

/// FCMトークンを受け取るためのデリゲート
class FCMDelegate: NSObject, MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("✅ FCMトークン取得: \(token.prefix(20))...")
        
        // トークンをFirestoreに保存
        _Concurrency.Task {
            await AuthService.shared.saveFCMToken(token)
        }
    }
}

@main
struct lifelogApp: App {
    @StateObject private var store = AppDataStore()
    @StateObject private var deepLinkManager = DeepLinkManager.shared
    
    /// 通知デリゲート（強参照で保持）
    private let notificationDelegate = NotificationDelegate()
    private let fcmDelegate = FCMDelegate()

    init() {
        // Firebase初期化
        FirebaseApp.configure()
        
        CategoryPalette.initializeIfNeeded()
        
        // 通知デリゲートを設定
        UNUserNotificationCenter.current().delegate = notificationDelegate
        
        // FCMデリゲートを設定
        Messaging.messaging().delegate = fcmDelegate
        
        // 通知許可をリクエスト
        _Concurrency.Task {
            let granted = await NotificationService.shared.requestAuthorization()
            if granted {
                print("✅ 通知許可が取得されました")
                // リモート通知を登録
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
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
