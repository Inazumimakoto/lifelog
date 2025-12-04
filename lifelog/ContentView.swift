//
//  ContentView.swift
//  lifelog
//
//  Created by inazumimakoto on 2025/11/13.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var selection: Int = 0
    @State private var lastSelection: Int = 0
    @State private var calendarResetTrigger: Int = 0

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
                HabitsCountdownView(store: store)
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
            if newSelection == lastSelection {
                // Scroll to top
            }
            lastSelection = newSelection
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
