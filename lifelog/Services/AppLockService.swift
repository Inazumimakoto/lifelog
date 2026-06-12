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

    /// 端末に生体認証またはパスコードが設定されているか。
    /// false のままロックを有効化すると authenticateForSensitiveAction の
    /// fail-open(閉じ込め防止)により素通しになるため、設定画面は
    /// これを見てオン操作を拒否し、既にオンの場合は警告を表示する。
    var isDeviceAuthAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

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
