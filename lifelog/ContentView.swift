//
//  ContentView.swift
//  lifelog
//
//  Created by inazumimakoto on 2025/11/13.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppDataStore
    @EnvironmentObject private var deepLinkManager: DeepLinkManager
    @State private var selection: Int = 0
    @State private var lastSelection: Int = 0
    @State private var calendarResetTrigger: Int = 0
    @State private var habitsResetTrigger: Int = 0
    
    /// ディープリンクで開く手紙
    @State private var letterToOpen: Letter? = nil

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
        // ディープリンク: 通知タップで手紙開封画面を表示
        .onChange(of: deepLinkManager.pendingLetterID) { _, letterID in
            guard let letterID = letterID else { return }
            // 開封可能な手紙を検索
            if let letter = store.letters.first(where: { $0.id == letterID && $0.isDeliverable }) {
                letterToOpen = letter
            } else {
                // 見つからない場合（すでに開封済みなど）はクリア
                deepLinkManager.clearPendingLetter()
            }
        }
        .fullScreenCover(item: $letterToOpen) { letter in
            LetterOpeningView(letter: letter) {
                store.openLetter(letter.id)
                deepLinkManager.clearPendingLetter()
            }
        }
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
