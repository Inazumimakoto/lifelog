//
//  ContentView.swift
//  lifelog
//
//  Created by inazumimakoto on 2025/11/13.
//

import SwiftUI
import WidgetKit

struct ContentView: View {
    @EnvironmentObject private var store: AppDataStore
    @EnvironmentObject private var deepLinkManager: DeepLinkManager
    @ObservedObject private var monetization = MonetizationService.shared
    @ObservedObject private var deepLinkHandler = DeepLinkHandler.shared
    @StateObject private var appLockService = AppLockService.shared
    @AppStorage("isMemoTextHidden") private var isMemoTextHidden: Bool = false
    @AppStorage("requiresMemoOpenAuthentication") private var requiresMemoOpenAuthentication: Bool = false
    @State private var selection: Int = 0
    @State private var lastSelection: Int = 0
    @State private var calendarResetTrigger: Int = 0
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

    var body: some View {
        TabView(selection: $selection) {
            navigationStack(for: 0) {
                TodayView(store: store)
            }
            .tabItem {
                Label("ホーム", systemImage: "sun.max.fill")
            }
            .tag(0)

            navigationStack(for: 1) {
                JournalView(store: store, resetTrigger: calendarResetTrigger)
            }
            .tabItem {
                Label("カレンダー", systemImage: "calendar")
            }
            .tag(1)

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
        // ディープリンク: 未来への手紙の通知タップ
        .onChange(of: deepLinkManager.pendingLetterID) { _, letterID in
            guard let letterID = letterID else { return }
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
        // ディープリンク: 共有手紙の通知タップ
        .onChange(of: deepLinkManager.pendingSharedLetterID) { _, letterID in
            guard let letterID = letterID else { return }
            guard monetization.canUseLetters else {
                deepLinkManager.clearPendingSharedLetter()
                premiumAlertMessage = monetization.lettersMessage()
                return
            }
            fetchSharedLetter(id: letterID)
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
        // 招待リンクの確認シート
        .sheet(isPresented: $deepLinkHandler.showInviteConfirmation) {
            InviteConfirmationView()
        }
        // 招待リンク用サインインフロー
        .sheet(isPresented: $deepLinkHandler.showSignInFlow) {
            InviteSignInFlowView()
        }
        // 招待リンクのエラーアラート
        .alert("招待リンク", isPresented: Binding(
            get: { deepLinkHandler.errorMessage != nil },
            set: { if !$0 { deepLinkHandler.errorMessage = nil } }
        )) {
            Button("OK") {
                deepLinkHandler.clear()
            }
        } message: {
            Text(deepLinkHandler.errorMessage ?? "")
        }
        // 友達追加成功のガイドアラート
        .alert("友達を追加しました！", isPresented: $deepLinkHandler.showAddedSuccess) {
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
        .onAppear {
            syncMemoPrivacySettingsToSharedDefaults()
            handleWidgetDestinationIfNeeded(deepLinkManager.pendingWidgetDestination)
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
        .fullScreenCover(isPresented: $showMemoEditorFromWidget) {
            NavigationStack {
                MemoEditorView(store: store)
            }
        }
    }
    
    private func fetchSharedLetter(id: String) {
        _Concurrency.Task {
            do {
                let letters = try await LetterReceivingService.shared.getReceivedLetters()
                if let letter = letters.first(where: { $0.id == id && $0.status == "delivered" }) {
                    await MainActor.run {
                        sharedLetterToOpen = letter
                    }
                } else {
                    // 見つからない（既読など）
                    await MainActor.run {
                        deepLinkManager.clearPendingSharedLetter()
                    }
                }
            } catch {
                await MainActor.run {
                    deepLinkManager.clearPendingSharedLetter()
                }
            }
        }
    }

    private func handleWidgetDestinationIfNeeded(_ destination: DeepLinkManager.WidgetDestination?) {
        guard let destination, !isHandlingWidgetDestination else { return }

        deepLinkManager.clearPendingWidgetDestination()
        isHandlingWidgetDestination = true

        _Concurrency.Task { @MainActor in
            defer { isHandlingWidgetDestination = false }

            switch destination {
            case .memo:
                if isMemoTextHidden, requiresMemoOpenAuthentication {
                    let isAuthorized = await appLockService.authenticateForSensitiveAction(reason: "メモを開くには認証が必要です")
                    guard isAuthorized else { return }
                }

                selection = 0
                showMemoEditorFromWidget = true
            }
        }
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
