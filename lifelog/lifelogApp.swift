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
#if DEBUG
    @StateObject private var shoppingConnection = ShoppingConnectionService.shared
    @State private var shoppingConnectionSheet: ShoppingConnectionSheet?

    private struct ShoppingConnectionSheet: Identifiable {
        let id = UUID()
    }
#endif
    
    init() {
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
#if DEBUG
                        store.shoppingSync.resume()
#endif
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
#if DEBUG
                presentShoppingConnectionIfAllowed()
#endif
            }
#if DEBUG
            .sheet(item: $shoppingConnectionSheet, onDismiss: {
                shoppingConnection.dismissConnection()
                presentShoppingConnectionIfAllowed()
            }) { _ in
                ZStack {
                    NavigationStack {
                        ShoppingConnectionView(service: shoppingConnection, sync: store.shoppingSync)
                    }
                    .opacity(isShoppingConnectionLocked ? 0 : 1)
                    .allowsHitTesting(!isShoppingConnectionLocked)
                    .accessibilityHidden(isShoppingConnectionLocked)
                    if isShoppingConnectionLocked {
                        LockView()
                            .zIndex(999)
                    }
                }
            }
            .onChange(of: shoppingConnection.presentationRequested) { _, _ in
                presentShoppingConnectionIfAllowed()
            }
            .onChange(of: appLockService.isUnlocked) { _, _ in
                presentShoppingConnectionIfAllowed()
                if appLockService.isUnlocked { store.shoppingSync.resume() }
            }
#endif
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .inactive || newPhase == .background {
                    appLockService.lock()
                } else if newPhase == .active {
                    // アプリがアクティブになった時にロックが有効なら認証を試みる
                    if hasFinishedStartup && appLockService.isAppLockEnabled && !appLockService.isUnlocked {
                        appLockService.authenticate()
                    }
#if DEBUG
                    presentShoppingConnectionIfAllowed()
                    store.shoppingSync.resume()
#endif

                    syncMemoPrivacySettingsToSharedDefaults()
                    store.resumeDiaryPhotoSync()
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
#if DEBUG
                if url.host == "lifelify-connect-dev.inazumimakoto.workers.dev" {
                    _ = shoppingConnection.handleApprovalURL(url)
                    presentShoppingConnectionIfAllowed()
                    return
                }
#endif
                if deepLinkManager.handleWidgetURL(url) {
                    return
                }
                DeepLinkHandler.shared.handleURL(url)
            }
        }
    }

#if DEBUG
    private var isShoppingConnectionLocked: Bool {
        appLockService.isAppLockEnabled && !appLockService.isUnlocked
    }

    private func presentShoppingConnectionIfAllowed() {
        guard shoppingConnection.presentationRequested, shoppingConnectionSheet == nil,
              hasFinishedStartup, scenePhase == .active, !isShoppingConnectionLocked else { return }
        shoppingConnectionSheet = ShoppingConnectionSheet()
    }
#endif

    private func syncMemoPrivacySettingsToSharedDefaults() {
        let shared = UserDefaults(suiteName: PersistenceController.appGroupIdentifier) ?? UserDefaults.standard
        let standard = UserDefaults.standard

        let isMemoTextHidden = standard.bool(forKey: "isMemoTextHidden")
        let requiresMemoOpenAuthentication = standard.bool(forKey: "requiresMemoOpenAuthentication")

        shared.set(isMemoTextHidden, forKey: "isMemoTextHidden")
        shared.set(requiresMemoOpenAuthentication, forKey: "requiresMemoOpenAuthentication")
    }
}
