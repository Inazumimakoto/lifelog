//
//  ContentView.swift
//  lifelog
//
//  Created by inazumimakoto on 2025/11/13.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppDataStore

    var body: some View {
        TabView {
            NavigationStack {
                TodayView(store: store)
            }
            .tabItem {
                Label("今日", systemImage: "sun.max.fill")
            }

            NavigationStack {
                JournalView(store: store)
            }
            .tabItem {
                Label("ジャーナル", systemImage: "calendar")
            }

            NavigationStack {
                HabitsCountdownView(store: store)
            }
            .tabItem {
                Label("習慣", systemImage: "checkmark.circle")
            }

            NavigationStack {
                HealthDashboardView(store: store)
            }
            .tabItem {
                Label("ヘルス", systemImage: "heart.fill")
            }
        }
    }
}
