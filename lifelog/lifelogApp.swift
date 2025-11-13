//
//  lifelogApp.swift
//  lifelog
//
//  Created by inazumimakoto on 2025/11/13.
//

import SwiftUI

@main
struct lifelogApp: App {
    @StateObject private var store = AppDataStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environment(\.locale, Locale(identifier: "ja_JP"))
        }
    }
}
