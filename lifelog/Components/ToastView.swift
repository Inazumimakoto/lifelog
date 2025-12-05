//
//  ToastView.swift
//  lifelog
//
//  Created by Codex on 2025/12/05.
//

import SwiftUI
import Combine

/// トースト通知を表示するためのビュー
struct ToastView: View {
    let message: String
    let emoji: String
    
    var body: some View {
        HStack(spacing: 8) {
            Text(emoji)
                .font(.title2)
            Text(message)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
    }
}

/// トースト表示を管理するマネージャー
@MainActor
final class ToastManager: ObservableObject {
    static let shared = ToastManager()
    
    @Published var currentToast: ToastData?
    
    struct ToastData: Identifiable, Equatable {
        let id = UUID()
        let emoji: String
        let message: String
    }
    
    private init() {}
    
    func show(emoji: String, message: String, duration: TimeInterval = 2.5) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentToast = ToastData(emoji: emoji, message: message)
        }
        
        _Concurrency.Task {
            try? await _Concurrency.Task.sleep(for: .seconds(duration))
            withAnimation(.easeOut(duration: 0.3)) {
                if self.currentToast?.message == message {
                    self.currentToast = nil
                }
            }
        }
    }
}

/// トーストを画面に表示するビューモディファイア
struct ToastModifier: ViewModifier {
    @ObservedObject var toastManager = ToastManager.shared
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = toastManager.currentToast {
                    ToastView(message: toast.message, emoji: toast.emoji)
                        .padding(.top, 60)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .zIndex(999)
                }
            }
    }
}

extension View {
    func toast() -> some View {
        modifier(ToastModifier())
    }
}
