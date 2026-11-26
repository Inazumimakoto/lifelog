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
    @State private var hasFinishedStartup = false
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

    private var canRefreshNotifications: Bool {
        storeOwner.store != nil && hasFinishedStartup && scenePhase == .active &&
            (!appLockService.isAppLockEnabled || appLockService.isUnlocked)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let store = storeOwner.store {
                    ContentView(store: store, isStartupComplete: hasFinishedStartup)
                        .environmentObject(store)
                        .environmentObject(deepLinkManager)
                        .allowsHitTesting(hasFinishedStartup)
                        .accessibilityHidden(!hasFinishedStartup)
                        .onAppear {
                            syncMemoPrivacySettingsToSharedDefaults()
                            store.resumeDiaryPhotoSync()
                            WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
                            WidgetCenter.shared.reloadTimelines(ofKind: "HabitWidget")
                            WidgetCenter.shared.reloadTimelines(ofKind: "AnniversaryWidget")
                            WidgetCenter.shared.reloadTimelines(ofKind: "MemoWidget")
                            _Concurrency.Task {
                                await monetizationService.refreshStatus()
                            }
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
            .modifier(AppThemeAppearance(
                canChangeIcon: hasFinishedStartup && scenePhase == .active && !PersistenceController.isRunningTests
            ))
            .environmentObject(appIconCoordinator)
            .task(id: canRefreshNotifications) {
                guard let store = storeOwner.store, canRefreshNotifications,
                      !PersistenceController.isRunningTests,
                      !PersistenceController.isSimulatorDemoMode else { return }
                // Reveal the home first. Notification IPC must never extend the
                // startup logo or run again from a second onAppear path (§起動時の表示).
                await _Concurrency.Task.yield()
                guard !_Concurrency.Task.isCancelled, canRefreshNotifications else { return }
                store.refreshNotificationsAfterStartup()
                await NotificationService.shared.refreshAuthorizationStatus()
            }
            .onReceive(NotificationService.shared.authorizationBecameAvailable) { _ in
                if !UIApplication.shared.isRegisteredForRemoteNotifications {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                storeOwner.store?.restoreRemindersAfterNotificationAuthorization()
            }
            .onChange(of: hasFinishedStartup) { _, isComplete in
                guard isComplete else { return }
                if scenePhase == .active && appLockService.isAppLockEnabled && !appLockService.isUnlocked {
                    appLockService.authenticate()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
                storeOwner.openIfNeeded()
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

                    storeOwner.openIfNeeded()
                    guard let store = storeOwner.store else { return }
                    syncMemoPrivacySettingsToSharedDefaults()
                    store.resumeDiaryPhotoSync()
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
