//
//  HintManager.swift
//  lifelog
//
//  Created by Codex on 2025/12/07.
//

import SwiftUI
import Combine

/// 初回表示ヒントを管理するマネージャー
class HintManager: ObservableObject {
    static let shared = HintManager()
    
    private let defaults = UserDefaults.standard
    
    // ヒントキー
    enum HintKey: String, CaseIterable {
        case healthChartTap = "hint_health_chart_tap"
        case habitLongPress = "hint_habit_long_press"
        case photoFavorite = "hint_photo_favorite"
        case tagManagerPlus = "hint_tag_manager_plus"
        case calendarSwitch = "hint_calendar_switch"
        case diarySwipe = "hint_diary_swipe"
    }
    
    /// ヒントが表示済みかどうか
    func hasShownHint(_ key: HintKey) -> Bool {
        defaults.bool(forKey: key.rawValue)
    }
    
    /// ヒントを表示済みにする
    func markHintShown(_ key: HintKey) {
        defaults.set(true, forKey: key.rawValue)
        objectWillChange.send()
    }
    
    /// 全ヒントをリセット（デバッグ用）
    func resetAllHints() {
        HintKey.allCases.forEach { key in
            defaults.removeObject(forKey: key.rawValue)
        }
        objectWillChange.send()
    }
    
    /// ヒントを初回のみ表示するかどうか
    func shouldShowHint(_ key: HintKey) -> Bool {
        !hasShownHint(key)
    }
}

// MARK: - Hint Overlay View
struct HintOverlay: View {
    let message: String
    let icon: String
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.yellow)
            Text(message)
                .font(.subheadline)
            Spacer()
            Button {
                HapticManager.light()
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .padding(.horizontal)
    }
}

// MARK: - View Modifier for Hints
struct HintModifier: ViewModifier {
    let hintKey: HintManager.HintKey
    let message: String
    let icon: String
    @ObservedObject private var hintManager = HintManager.shared
    @State private var showHint = false
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if showHint {
                    HintOverlay(message: message, icon: icon) {
                        withAnimation {
                            showHint = false
                            hintManager.markHintShown(hintKey)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
                }
            }
            .onAppear {
                // 少し遅延して表示
                if hintManager.shouldShowHint(hintKey) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation {
                            showHint = true
                        }
                    }
                }
            }
    }
}

extension View {
    func showHint(_ key: HintManager.HintKey, message: String, icon: String = "lightbulb.fill") -> some View {
        modifier(HintModifier(hintKey: key, message: message, icon: icon))
    }
}
