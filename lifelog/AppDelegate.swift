//
//  AppDelegate.swift
//  lifelog
//
//  Created by inazumimakoto on 2025/12/13.
//

import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        print("🚀🚀🚀 AppDelegate didFinishLaunchingWithOptions 開始 🚀🚀🚀")
        
        // Firebase初期化
        FirebaseApp.configure()
        print("✅ Firebase初期化完了")
        
        // Messagingデリゲート設定
        Messaging.messaging().delegate = self
        print("✅ Messagingデリゲート設定完了")
        
        // 通知デリゲート設定
        UNUserNotificationCenter.current().delegate = self
        print("✅ 通知デリゲート設定完了")
        
        // 通知許可リクエスト
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(
            options: authOptions,
            completionHandler: { granted, error in
                print("📣 通知許可結果: granted=\(granted), error=\(String(describing: error))")
            }
        )
        
        print("📱 registerForRemoteNotifications を呼び出します...")
        application.registerForRemoteNotifications()
        print("📱 registerForRemoteNotifications 呼び出し完了")
        
        print("🚀🚀🚀 AppDelegate didFinishLaunchingWithOptions 終了 🚀🚀🚀")
        return true
    }
    
    // MARK: - APNs Token
    
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("✅ APNsトークン取得成功: \(deviceToken.map { String(format: "%02.2hhx", $0) }.joined())")
        // APNsトークンをFirebase Messagingに設定
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌❌❌ リモート通知の登録に失敗 ❌❌❌")
        print("エラー詳細: \(error)")
        print("エラーの説明: \(error.localizedDescription)")
    }
    
    // MARK: - MessagingDelegate
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("✅ FCMトークン取得: \(token.prefix(20))...")
        
        // トークンをFirestoreに保存
        _Concurrency.Task {
            await AuthService.shared.saveFCMToken(token)
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    // フォアグラウンドでの通知受信
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    
    // 通知タップ時の処理
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        // 共有手紙の通知かチェック（Cloud Functionsから送信）
        if let type = userInfo["type"] as? String,
           type == "letter",
           let letterIdString = userInfo["letterId"] as? String {
            DispatchQueue.main.async {
                DeepLinkManager.shared.handleSharedLetterNotification(letterID: letterIdString)
            }
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
