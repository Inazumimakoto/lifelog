//
//  ToastView.swift
//  lifelog
//
//  Created by Codex on 2025/12/05.
//

import SwiftUI
import Combine
import UIKit

/// トースト通知を表示するためのビュー
struct ToastView: View {
    let message: String
    let emoji: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(emoji)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(message.components(separatedBy: "\n"), id: \.self) { line in
                    Text(line)
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
    }
}

/// トースト表示を管理するマネージャー（UIWindowレベルで表示）
@MainActor
final class ToastManager: ObservableObject {
    static let shared = ToastManager()
    
    @Published var currentToast: ToastData?
    
    private var toastWindow: UIWindow?
    private var hostingController: UIHostingController<AnyView>?
    
    struct ToastData: Identifiable, Equatable {
        let id = UUID()
        let emoji: String
        let message: String
    }
    
    private init() {}
    
    func show(emoji: String, message: String, duration: TimeInterval = 2.5) {
        // 既存のトーストがあれば即座に削除
        dismissToastWindow()
        
        currentToast = ToastData(emoji: emoji, message: message)
        showToastWindow(emoji: emoji, message: message)
        
        _Concurrency.Task {
            try? await _Concurrency.Task.sleep(for: .seconds(duration))
            await MainActor.run {
                if self.currentToast?.message == message {
                    self.dismissToastWindow()
                    self.currentToast = nil
                }
            }
        }
    }
    
    private func showToastWindow(emoji: String, message: String) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return
        }
        
        let toastView = ToastView(message: message, emoji: emoji)
            .padding(.top, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .opacity
            ))
        
        let hostingController = UIHostingController(rootView: AnyView(toastView))
        hostingController.view.backgroundColor = .clear
        
        let window = PassthroughWindow(windowScene: windowScene)
        window.rootViewController = hostingController
        window.windowLevel = .alert + 1  // シートより上に表示
        window.isHidden = false
        
        self.toastWindow = window
        self.hostingController = hostingController
        
        // アニメーション
        hostingController.view.alpha = 0
        hostingController.view.transform = CGAffineTransform(translationX: 0, y: -50)
        
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            hostingController.view.alpha = 1
            hostingController.view.transform = .identity
        }
    }
    
    private func dismissToastWindow() {
        guard let window = toastWindow, let hosting = hostingController else { return }
        
        UIView.animate(withDuration: 0.3, animations: {
            hosting.view.alpha = 0
        }, completion: { _ in
            window.isHidden = true
            self.toastWindow = nil
            self.hostingController = nil
        })
    }
}

/// タッチイベントを透過するWindow（トースト以外のタップを下に流す）
private class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hitView = super.hitTest(point, with: event) else { return nil }
        // rootViewControllerのviewか、その子ビューでなければnilを返す（タップを透過）
        if hitView == rootViewController?.view {
            return nil
        }
        return hitView
    }
}

/// トーストを画面に表示するビューモディファイア（後方互換性のため残す）
struct ToastModifier: ViewModifier {
    @ObservedObject var toastManager = ToastManager.shared
    
    func body(content: Content) -> some View {
        // UIWindowで表示するため、ここでは何もしない
        content
    }
}

extension View {
    func toast() -> some View {
        modifier(ToastModifier())
    }
}
