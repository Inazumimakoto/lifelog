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
import WidgetKit



@main
struct lifelogApp: App {
    // AppDelegateを接続
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    @StateObject private var storeOwner = AppDataStoreOwner()
    @State private var hasFinishedStartup = false
    private var store: AppDataStore { storeOwner.store }
    @ObservedObject private var deepLinkManager = DeepLinkManager.shared
    @ObservedObject private var monetizationService = MonetizationService.shared
    
    init() {
        // Remove the retired AI analysis quota; see docs/ai-analysis-retirement.md.
        UserDefaults.standard.removeObject(forKey: "devpc_llm_usage")
        if !PersistenceController.isRunningTests {
            RetiredIntegrationCredentials.removeIfNeeded()
        }
        CategoryPalette.initializeIfNeeded()
    }

    @ObservedObject private var appLockService = AppLockService.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView(store: store, isStartupComplete: hasFinishedStartup)
                    .environmentObject(store)
                    .environmentObject(deepLinkManager)
                    .allowsHitTesting(hasFinishedStartup)
                    .accessibilityHidden(!hasFinishedStartup)
                    .onAppear {
                        // 日記リマインダーを再スケジュール（今日書いていなければ通知）
                        syncMemoPrivacySettingsToSharedDefaults()
                        store.resumeDiaryPhotoSync()
                        store.rescheduleDiaryReminderIfNeeded()
                        store.rescheduleTodayOverviewReminderIfNeeded()
                        WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
                        WidgetCenter.shared.reloadTimelines(ofKind: "HabitWidget")
                        WidgetCenter.shared.reloadTimelines(ofKind: "AnniversaryWidget")
                        WidgetCenter.shared.reloadTimelines(ofKind: "MemoWidget")
                        _Concurrency.Task {
                            await monetizationService.refreshStatus()
                        }
                    }
                
                if !appLockService.isUnlocked && appLockService.isAppLockEnabled {
                    LockView()
                        .allowsHitTesting(hasFinishedStartup)
                        .accessibilityHidden(!hasFinishedStartup)
                        .transition(.opacity)
                        .zIndex(999)
                }

                if !hasFinishedStartup {
                    StartupLogoView {
                        hasFinishedStartup = true
                    }
                    .zIndex(1000)
                }
            }
            .onChange(of: hasFinishedStartup) { _, isComplete in
                guard isComplete else { return }
                if scenePhase == .active && appLockService.isAppLockEnabled && !appLockService.isUnlocked {
                    appLockService.authenticate()
                }
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .inactive || newPhase == .background {
                    appLockService.lock()
                } else if newPhase == .active {
                    if !PersistenceController.isRunningTests {
                        RetiredIntegrationCredentials.removeIfNeeded()
                    }
                    // アプリがアクティブになった時にロックが有効なら認証を試みる
                    if hasFinishedStartup && appLockService.isAppLockEnabled && !appLockService.isUnlocked {
                        appLockService.authenticate()
                    }

                    syncMemoPrivacySettingsToSharedDefaults()
                    store.resumeDiaryPhotoSync()
                    store.refreshCalendarRemindersIfNeeded()
                    store.rescheduleTodayOverviewReminderIfNeeded()
                    WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
                    WidgetCenter.shared.reloadTimelines(ofKind: "HabitWidget")
                    WidgetCenter.shared.reloadTimelines(ofKind: "AnniversaryWidget")
                    WidgetCenter.shared.reloadTimelines(ofKind: "MemoWidget")
                    
                    // 最終ログイン日時を更新（手紙の生存確認用）
                    _Concurrency.Task {
                        await AuthService.shared.updateLastLoginAt()
                        await monetizationService.refreshStatus()
                    }
                }
            }
            // Universal Links (招待リンク) のハンドリング
            .onOpenURL { url in
                if deepLinkManager.handleWidgetURL(url) {
                    return
                }
                DeepLinkHandler.shared.handleURL(url)
            }
        }
    }

    private func syncMemoPrivacySettingsToSharedDefaults() {
        let shared = UserDefaults(suiteName: PersistenceController.appGroupIdentifier) ?? UserDefaults.standard
        let standard = UserDefaults.standard

        let isMemoTextHidden = standard.bool(forKey: "isMemoTextHidden")
        let requiresMemoOpenAuthentication = standard.bool(forKey: "requiresMemoOpenAuthentication")

        shared.set(isMemoTextHidden, forKey: "isMemoTextHidden")
        shared.set(requiresMemoOpenAuthentication, forKey: "requiresMemoOpenAuthentication")
    }
}
