//
//  ContentView.swift
//  lifelog
//
//  Created by inazumimakoto on 2025/11/13.
//

import SwiftUI
import WidgetKit

enum WallpaperCalendarAnnouncementState {
    static let hasSeenKey = "hasSeenWallpaperCalendarAnnouncementV1"
}

struct ContentView: View {
    // Only destination view models observe their data sources. Observing the whole
    // store here invalidated every tab when a diary, habit or health value changed.
    let store: AppDataStore
    // Keep UIKit presentations behind the launch animation; see docs/ui-guidelines.md §起動時の表示.
    var isStartupComplete: Bool = true
    @EnvironmentObject private var deepLinkManager: DeepLinkManager
    @ObservedObject private var monetization = MonetizationService.shared
    @ObservedObject private var deepLinkHandler = DeepLinkHandler.shared
    @ObservedObject private var appLockService = AppLockService.shared
    @AppStorage("isMemoTextHidden") private var isMemoTextHidden: Bool = false
    @AppStorage("requiresMemoOpenAuthentication") private var requiresMemoOpenAuthentication: Bool = false
    @State private var selection: Int = 0
    @State private var lastSelection: Int = 0
    @State private var calendarResetTrigger: Int = 0
    @State private var calendarDateFromWidget: Date?
    @State private var habitsResetTrigger: Int = 0
    
    /// ディープリンクで開く手紙
    @State private var letterToOpen: Letter? = nil
    
    /// 共有手紙用
    @State private var sharedLetterToOpen: LetterReceivingService.ReceivedLetter? = nil
    @State private var showSharedLetterOpening = false
    
    /// 招待後に手紙を書く画面を表示
    @State private var showLetterSharingFromInvite = false
    @State private var showPaywall = false
    @State private var premiumAlertMessage: String?
    @State private var showMemoEditorFromWidget = false
    @State private var isHandlingWidgetDestination = false
    @State private var hasAuthorizedPendingWidgetMemo = false
    @State private var showStoreRecoveryNotice = false
    @AppStorage(WallpaperCalendarAnnouncementState.hasSeenKey) private var hasSeenWallpaperCalendarAnnouncement = false
    @State private var showWallpaperCalendarAnnouncement = false
    @State private var showSettingsFromWallpaperCalendarAnnouncement = false
    @AppStorage(InitialPermissionsState.completedKey) private var hasCompletedInitialPermissionsSetup = false
    @State private var showInitialPermissionsSetup = false

    private var canPresentStartupContent: Bool {
        isStartupComplete && (appLockService.isAppLockEnabled == false || appLockService.isUnlocked)
    }

    private var mainTabs: some View {
        TabView(selection: $selection) {
            navigationStack(for: 0) {
                TodayView(store: store)
            }
            .tabItem {
                Label("ホーム", systemImage: "sun.max.fill")
            }
            .tag(0)

            navigationStack(for: 1) {
                JournalView(store: store,
                            resetTrigger: calendarResetTrigger,
                            requestedDate: $calendarDateFromWidget)
            }
            .tabItem {
                Label("カレンダー", systemImage: "calendar")
            }
            .tag(1)

            // docs/requirements.md §買い物: 日付に依存しないリストへ直接アクセス。
            navigationStack(for: 4) {
                ShoppingListView(store: store)
            }
            .tabItem {
                Label("買い物", systemImage: "cart")
            }
            .tag(4)

            navigationStack(for: 2) {
                HabitsCountdownView(store: store, resetTrigger: habitsResetTrigger)
            }
            .tabItem {
                Label("習慣", systemImage: "checkmark.circle")
            }
            .tag(2)

            navigationStack(for: 3) {
                HealthDashboardView(store: store)
            }
            .tabItem {
                Label("ヘルス", systemImage: "heart.fill")
            }
            .tag(3)
        }
        .onChange(of: selection) { oldSelection, newSelection in
            // 他のタブからカレンダータブに戻った時にリセット
            if newSelection == 1 && oldSelection != 1 {
                calendarResetTrigger += 1
            }
            // 習慣タブに戻った時に習慣表示にリセット
            if newSelection == 2 && oldSelection != 2 {
                habitsResetTrigger += 1
            }
            if newSelection == lastSelection {
                // Scroll to top
            }
            lastSelection = newSelection
        }
        .toast()
    }

    private var letterRoutingContent: some View {
        mainTabs
        // ディープリンク: 未来への手紙の通知タップ
        .onChange(of: deepLinkManager.pendingLetterID) { _, letterID in
            handlePendingLetterIfNeeded(letterID)
        }
        // ディープリンク: 共有手紙の通知タップ
        .onChange(of: deepLinkManager.pendingSharedLetterID) { _, letterID in
            handlePendingSharedLetterIfNeeded(letterID)
        }
        .fullScreenCover(item: $letterToOpen) { letter in
            LetterOpeningView(letter: letter) {
                store.openLetter(letter.id)
                deepLinkManager.clearPendingLetter()
            }
        }
        .fullScreenCover(isPresented: $showSharedLetterOpening) {
            if let letter = sharedLetterToOpen {
                SharedLetterOpeningView(letter: letter)
                    .environmentObject(store)
                    .onDisappear {
                        sharedLetterToOpen = nil
                        deepLinkManager.clearPendingSharedLetter()
                    }
            }
        }
        .onChange(of: sharedLetterToOpen) { _, newLetter in
            if newLetter != nil {
                showSharedLetterOpening = true
            }
        }
    }

    private var invitePresentationContent: some View {
        letterRoutingContent
        // 招待リンクの確認シート
        .sheet(isPresented: startupPresentationBinding($deepLinkHandler.showInviteConfirmation)) {
            InviteConfirmationView()
        }
        // 招待リンク用サインインフロー
        .sheet(isPresented: startupPresentationBinding($deepLinkHandler.showSignInFlow)) {
            InviteSignInFlowView()
        }
        // 招待リンクのエラーアラート
        .alert("招待リンク", isPresented: Binding(
            get: { canPresentStartupContent && deepLinkHandler.errorMessage != nil },
            set: { if canPresentStartupContent && !$0 { deepLinkHandler.errorMessage = nil } }
        )) {
            Button("OK") {
                deepLinkHandler.clear()
            }
        } message: {
            Text(deepLinkHandler.errorMessage ?? "")
        }
        // 友達追加成功のガイドアラート
        .alert("友達を追加しました！", isPresented: startupPresentationBinding($deepLinkHandler.showAddedSuccess)) {
            Button("手紙を書く画面へ") {
                deepLinkHandler.showAddedSuccess = false
                showLetterSharingFromInvite = true
            }
            Button("また今度", role: .cancel) {
                deepLinkHandler.showAddedSuccess = false
            }
        } message: {
            let friendName = deepLinkHandler.addedFriendName ?? "友達"
            Text("\(friendName)さんと友達になりました！\n\n設定 → ひみつの機能 → 大切な人への手紙\nからいつでも手紙が書けます")
        }
        // 招待後の手紙画面
        .sheet(isPresented: $showLetterSharingFromInvite) {
            NavigationStack {
                LetterSharingView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる") {
                                showLetterSharingFromInvite = false
                            }
                        }
                    }
            }
        }
    }

    private var noticePresentationContent: some View {
        invitePresentationContent
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView()
        }
        .alert("プレミアム機能", isPresented: Binding(
            get: { premiumAlertMessage != nil },
            set: { if $0 == false { premiumAlertMessage = nil } }
        )) {
            Button("プランを見る") {
                showPaywall = true
            }
            Button("あとで", role: .cancel) { }
        } message: {
            Text(premiumAlertMessage ?? "")
        }
        // データベース破損から自動復旧した場合の通知。
        // 黙って空のデータで起動するとユーザーが「全部消えた」とだけ
        // 受け取るため、何が起きたかを必ず伝える。
        .alert("データベースを初期化しました", isPresented: $showStoreRecoveryNotice) {
            Button("OK") { }
        } message: {
            Text("保存データの読み込みに失敗したため、新しいデータベースで起動しました。以前のデータファイルは端末内に退避されています。お問い合わせいただければ復旧を試みられる場合があります。")
        }
    }

    private var startupLifecycleContent: some View {
        noticePresentationContent
        .onAppear {
            syncMemoPrivacySettingsToSharedDefaults()
            handleStartupPresentationsIfNeeded()
        }
        .onChange(of: isStartupComplete) { _, isComplete in
            if isComplete {
                handleStartupPresentationsIfNeeded()
            }
        }
        .onChange(of: isMemoTextHidden) { _, _ in
            syncMemoPrivacySettingsToSharedDefaults()
            WidgetCenter.shared.reloadTimelines(ofKind: "MemoWidget")
        }
        .onChange(of: requiresMemoOpenAuthentication) { _, _ in
            syncMemoPrivacySettingsToSharedDefaults()
            WidgetCenter.shared.reloadTimelines(ofKind: "MemoWidget")
        }
        .onChange(of: deepLinkManager.pendingWidgetDestination) { _, destination in
            handleWidgetDestinationIfNeeded(destination)
        }
        .onChange(of: appLockService.isUnlocked) { _, _ in
            handleStartupPresentationsIfNeeded()
        }
    }

    var body: some View {
        startupLifecycleContent
        .modifier(WallpaperCalendarAnnouncementOverlayModifier(
            isPresented: $showWallpaperCalendarAnnouncement,
            onDismiss: dismissWallpaperCalendarAnnouncement,
            onOpenSettings: openSettingsFromWallpaperCalendarAnnouncement
        ))
        .sheet(isPresented: $showSettingsFromWallpaperCalendarAnnouncement) {
            NavigationStack {
                SettingsView(openWallpaperCalendarOnAppear: true)
            }
        }
        .fullScreenCover(isPresented: $showInitialPermissionsSetup) {
            InitialPermissionsSetupView(store: store) {
                hasCompletedInitialPermissionsSetup = true
                showInitialPermissionsSetup = false
                handleInitialPermissionsSetupCompletion()
            }
        }
        .fullScreenCover(isPresented: $showMemoEditorFromWidget) {
            NavigationStack {
                MemoEditorView(store: store)
            }
        }
    }

    private func startupPresentationBinding(_ presentation: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { canPresentStartupContent && presentation.wrappedValue },
            set: { if canPresentStartupContent { presentation.wrappedValue = $0 } }
        )
    }

    private func handleStartupPresentationsIfNeeded() {
        guard canPresentStartupContent else { return }
        consumeStoreRecoveryFlagIfNeeded()
        handleWidgetDestinationIfNeeded(deepLinkManager.pendingWidgetDestination)
        handlePendingLetterIfNeeded(deepLinkManager.pendingLetterID)
        handlePendingSharedLetterIfNeeded(deepLinkManager.pendingSharedLetterID)
        presentInitialPermissionsSetupIfNeeded()
        presentWallpaperCalendarAnnouncementIfNeeded()
    }

    private func handlePendingLetterIfNeeded(_ letterID: UUID?) {
        guard canPresentStartupContent, let letterID else { return }
        guard monetization.canUseLetters else {
            deepLinkManager.clearPendingLetter()
            premiumAlertMessage = monetization.lettersMessage()
            return
        }
        // 開封可能な手紙を検索
        if let letter = store.letters.first(where: { $0.id == letterID && $0.isDeliverable }) {
            letterToOpen = letter
        } else {
            // 見つからない場合（すでに開封済みなど）はクリア
            deepLinkManager.clearPendingLetter()
        }
    }

    private func handlePendingSharedLetterIfNeeded(_ letterID: String?) {
        guard canPresentStartupContent, let letterID else { return }
        guard monetization.canUseLetters else {
            deepLinkManager.clearPendingSharedLetter()
            premiumAlertMessage = monetization.lettersMessage()
            return
        }
        fetchSharedLetter(id: letterID)
    }
    
    private func fetchSharedLetter(id: String) {
        _Concurrency.Task {
            do {
                let letters = try await LetterReceivingService.shared.getReceivedLetters()
                if let letter = letters.first(where: { $0.id == id && $0.status == "delivered" }) {
                    await MainActor.run {
                        guard canPresentStartupContent else { return }
                        sharedLetterToOpen = letter
                    }
                } else {
                    // 見つからない（既読など）
                    await MainActor.run {
                        guard canPresentStartupContent else { return }
                        deepLinkManager.clearPendingSharedLetter()
                    }
                }
            } catch {
                await MainActor.run {
                    guard canPresentStartupContent else { return }
                    deepLinkManager.clearPendingSharedLetter()
                }
            }
        }
    }

    private func handleWidgetDestinationIfNeeded(_ destination: DeepLinkManager.WidgetDestination?) {
        guard canPresentStartupContent, let destination, !isHandlingWidgetDestination else { return }

        isHandlingWidgetDestination = true

        _Concurrency.Task { @MainActor in
            defer { isHandlingWidgetDestination = false }
            guard canPresentStartupContent else { return }

            switch destination {
            case .calendar(let date):
                hasAuthorizedPendingWidgetMemo = false
                deepLinkManager.clearPendingWidgetDestination()
                calendarDateFromWidget = date
                selection = 1
            case .memo:
                if isMemoTextHidden, requiresMemoOpenAuthentication, !hasAuthorizedPendingWidgetMemo {
                    let isAuthorized = await appLockService.authenticateForSensitiveAction(reason: "メモを開くには認証が必要です")
                    guard isAuthorized else {
                        deepLinkManager.clearPendingWidgetDestination()
                        return
                    }
                    // Retain this result if LocalAuthentication made the app
                    // inactive and the app lock must be unlocked again first.
                    hasAuthorizedPendingWidgetMemo = true
                }

                guard canPresentStartupContent else { return }
                hasAuthorizedPendingWidgetMemo = false
                deepLinkManager.clearPendingWidgetDestination()
                selection = 0
                showMemoEditorFromWidget = true
            }
        }
    }

    private func presentInitialPermissionsSetupIfNeeded() {
        guard canPresentStartupContent, hasCompletedInitialPermissionsSetup == false else { return }
        if store.hasExistingUserFootprintForInitialPermissions {
            hasCompletedInitialPermissionsSetup = true
            return
        }
        guard appLockService.isAppLockEnabled == false || appLockService.isUnlocked else { return }
        showInitialPermissionsSetup = true
    }

    private func handleInitialPermissionsSetupCompletion() {
        store.rescheduleDiaryReminderIfNeeded()
        store.rescheduleTodayOverviewReminderIfNeeded()
        WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "HabitWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "AnniversaryWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "MemoWidget")

        _Concurrency.Task {
            await store.loadHealthData()
            await store.syncExternalCalendarsIfAuthorized()
        }
    }

    private func presentWallpaperCalendarAnnouncementIfNeeded() {
        guard canPresentStartupContent,
              hasCompletedInitialPermissionsSetup,
              monetization.canUseWallpaperCalendar,
              hasSeenWallpaperCalendarAnnouncement == false,
              showWallpaperCalendarAnnouncement == false,
              showSettingsFromWallpaperCalendarAnnouncement == false,
              appLockService.isAppLockEnabled == false || appLockService.isUnlocked
        else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard canPresentStartupContent,
                  hasCompletedInitialPermissionsSetup,
                  monetization.canUseWallpaperCalendar,
                  hasSeenWallpaperCalendarAnnouncement == false,
                  showWallpaperCalendarAnnouncement == false,
                  showSettingsFromWallpaperCalendarAnnouncement == false,
                  appLockService.isAppLockEnabled == false || appLockService.isUnlocked
            else {
                return
            }
            showWallpaperCalendarAnnouncement = true
        }
    }

    private func dismissWallpaperCalendarAnnouncement() {
        hasSeenWallpaperCalendarAnnouncement = true
        showWallpaperCalendarAnnouncement = false
    }

    private func openSettingsFromWallpaperCalendarAnnouncement() {
        hasSeenWallpaperCalendarAnnouncement = true
        showWallpaperCalendarAnnouncement = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            showSettingsFromWallpaperCalendarAnnouncement = true
        }
    }

    /// ストア復旧フラグを読み取り、一度だけユーザーに通知する
    private func consumeStoreRecoveryFlagIfNeeded() {
        guard canPresentStartupContent else { return }
        let defaults = UserDefaults(suiteName: PersistenceController.appGroupIdentifier)
        guard defaults?.bool(forKey: PersistenceController.storeRecoveryOccurredKey) == true else { return }
        defaults?.removeObject(forKey: PersistenceController.storeRecoveryOccurredKey)
        showStoreRecoveryNotice = true
    }

    private func syncMemoPrivacySettingsToSharedDefaults() {
        let shared = UserDefaults(suiteName: PersistenceController.appGroupIdentifier) ?? UserDefaults.standard
        shared.set(isMemoTextHidden, forKey: "isMemoTextHidden")
        shared.set(requiresMemoOpenAuthentication, forKey: "requiresMemoOpenAuthentication")
    }

    @ViewBuilder
    private func navigationStack<Content: View>(for tag: Int, @ViewBuilder content: @escaping () -> Content) -> some View {
        NavigationStack {
            ScrollViewReader { proxy in
                content()
                    .id("scroll-view-\(tag)")
                    .onChange(of: selection) { _, newSelection in
                        if newSelection == lastSelection {
                            withAnimation {
                                proxy.scrollTo("scroll-view-\(tag)", anchor: .top)
                            }
                        }
                    }
            }
        }
    }
}
