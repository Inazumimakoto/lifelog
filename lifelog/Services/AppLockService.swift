//
//  AppLockService.swift
//  lifelog
//
//  Created by Codex on 2025/12/06.
//

import Foundation
import Combine
import SwiftUI
import LocalAuthentication

@MainActor
class AppLockService: ObservableObject {
    static let shared = AppLockService()
    
    @AppStorage("isAppLockEnabled") var isAppLockEnabled: Bool = false
    @Published var isUnlocked: Bool = false
    
    private init() {}
    
    func authenticate() {
        let context = LAContext()
        var error: NSError?
        
        // パスコードまたは生体認証が利用可能か確認
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            let reason = "アプリのロックを解除します"
            
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, authenticationError in
                DispatchQueue.main.async {
                    if success {
                        self.isUnlocked = true
                    } else {
                        // 失敗時（キャンセルなど）は何もしない、ロック画面のまま
                        self.isUnlocked = false
                    }
                }
            }
        } else {
            // 生体認証などが設定されていない場合は、ロック機能自体を無効にするか、パスコードフォールバック
            // ここでは簡易的にロック解除とする（閉じ込め防止）
            self.isUnlocked = true
        }
    }
    
    func lock() {
        if isAppLockEnabled {
            isUnlocked = false
        } else {
            isUnlocked = true
        }
    }
}
