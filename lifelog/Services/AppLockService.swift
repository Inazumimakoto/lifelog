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
        _Concurrency.Task {
            let success = await authenticateForSensitiveAction(reason: "アプリのロックを解除します")
            // 失敗時（キャンセルなど）はロック画面のまま
            self.isUnlocked = success
        }
    }

    /// Face ID / Touch ID / パスコードで保護操作の認証を行う
    func authenticateForSensitiveAction(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // 認証手段未設定時は閉じ込め防止のため通す
            return true
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
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
