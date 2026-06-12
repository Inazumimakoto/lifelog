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
import os

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        // Firebase初期化
        FirebaseApp.configure()

        // Messagingデリゲート設定
        Messaging.messaging().delegate = self

        // 通知デリゲート設定
        UNUserNotificationCenter.current().delegate = self

        // 通知許可の OS ダイアログは初期設定フローから順番に出す。
        // 既に許可済みの場合だけ APNs 登録を復元する。
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            default:
                break
            }
        }

        return true
    }

    // MARK: - APNs Token

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // トークン値はリリースで <private> に伏せられる
        AppLogger.notifications.debug("APNsトークン取得成功: \(deviceToken.map { String(format: "%02.2hhx", $0) }.joined())")
        // APNsトークンをFirebase Messagingに設定
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppLogger.notifications.error("リモート通知の登録に失敗: \(error)")
    }

    // MARK: - MessagingDelegate

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        // トークン値はリリースで <private> に伏せられる
        AppLogger.notifications.debug("FCMトークン取得: \(token.prefix(20))...")
        
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
