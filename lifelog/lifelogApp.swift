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
    
    @StateObject private var appIconCoordinator = AppIconCoordinator()
    @StateObject private var storeOwner = AppDataStoreOwner()
    @ObservedObject private var deepLinkManager = DeepLinkManager.shared
    
    init() {
        StartupProfiler.shared.mark("lifelogApp.init.start")
        // Remove the retired AI analysis quota; see docs/ai-analysis-retirement.md.
        UserDefaults.standard.removeObject(forKey: "devpc_llm_usage")
        if !PersistenceController.isRunningTests {
            RetiredIntegrationCredentials.removeIfNeeded()
            ReviewRequestManager.shared.recordAppLaunch()
        }
        CategoryPalette.initializeIfNeeded()
        StartupProfiler.shared.mark("lifelogApp.init.end")
    }

    @ObservedObject private var appLockService = AppLockService.shared
    @Environment(\.scenePhase) private var scenePhase

    private var isForegroundReady: Bool {
        scenePhase == .active
    }

    private var canRefreshNotifications: Bool {
        storeOwner.store != nil && isForegroundReady &&
            (!appLockService.isAppLockEnabled || appLockService.isUnlocked)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let store = storeOwner.store {
                    ContentView(store: store)
                        .environmentObject(store)
                        .environmentObject(deepLinkManager)
                        .task(id: isForegroundReady) {
                            guard isForegroundReady else { return }
                            // Let Home's first interactive frame and below-fold mount settle before Stage 2 hydration.
                            try? await _Concurrency.Task.sleep(for: .milliseconds(150))
                            guard !_Concurrency.Task.isCancelled, isForegroundReady else { return }
                            await store.loadRemainingHistoryIncrementally()
                            guard !_Concurrency.Task.isCancelled, isForegroundReady else { return }
                            store.startDeferredHealthSyncIfNeeded()
                            syncMemoPrivacySettingsToSharedDefaults()
                            store.resumeDiaryPhotoSync()
                            WidgetCenter.shared.reloadAllTimelines()
                            async let lastLogin: Void = AuthService.shared.updateLastLoginAt()
                            await MonetizationService.shared.refreshStatus()
                            await lastLogin
                        }
                } else {
                    ContentUnavailableView {
                        Label {
                            Text("startup.unavailable.title", tableName: "RecoveryStartup")
                        } icon: {
                            Image(systemName: "externaldrive.badge.exclamationmark")
                        }
                    } description: {
                        Text("startup.unavailable.message", tableName: "RecoveryStartup")
                    } actions: {
                        Button { storeOwner.openIfNeeded() } label: {
                            Text("startup.retry", tableName: "RecoveryStartup")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if !appLockService.isUnlocked && appLockService.isAppLockEnabled {
                    LockView()
                        .transition(.opacity)
                        .zIndex(999)
                }
            }
            .modifier(AppThemeAppearance(
                canChangeIcon: scenePhase == .active && !PersistenceController.isRunningTests
            ))
            .environmentObject(appIconCoordinator)
            .task(id: canRefreshNotifications) {
                guard let store = storeOwner.store, canRefreshNotifications,
                      !PersistenceController.isRunningTests,
                      !PersistenceController.isSimulatorDemoMode else { return }
                // Reveal the home first and let Stage 2 incremental hydration run smoothly.
                try? await _Concurrency.Task.sleep(for: .milliseconds(250))
                guard !_Concurrency.Task.isCancelled, canRefreshNotifications else { return }
                await store.loadRemainingHistoryIncrementally()
                guard !_Concurrency.Task.isCancelled, canRefreshNotifications else { return }
                StartupProfiler.shared.measure("notifications.refreshAfterStartup") {
                    store.refreshNotificationsAfterStartup()
                }
                await NotificationService.shared.refreshAuthorizationStatus()
            }
            .onReceive(NotificationService.shared.authorizationBecameAvailable) { _ in
                if !UIApplication.shared.isRegisteredForRemoteNotifications {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                storeOwner.store?.restoreRemindersAfterNotificationAuthorization()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
                storeOwner.openIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .inactive || newPhase == .background {
                    appLockService.lock()
                } else if newPhase == .active {
                    if !PersistenceController.isRunningTests {
                        RetiredIntegrationCredentials.removeIfNeeded()
                    }
                    // アプリがアクティブになった時にロックが有効なら認証を試みる
                    if appLockService.isAppLockEnabled && !appLockService.isUnlocked {
                        appLockService.authenticate()
                    }

                    storeOwner.openIfNeeded()
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
