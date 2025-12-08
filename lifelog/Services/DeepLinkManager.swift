//
//  DeepLinkManager.swift
//  lifelog
//
//  Created by AI for deep link support
//

import Foundation
import Combine
import SwiftUI

/// ディープリンク（通知タップなど）の状態管理
@MainActor
final class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()
    
    /// 開封待ちの手紙ID（通知タップ時にセット）
    @Published var pendingLetterID: UUID? = nil
    
    private init() {}
    
    /// 手紙通知から遷移する
    func handleLetterNotification(letterID: UUID) {
        pendingLetterID = letterID
    }
    
    /// ディープリンク処理完了
    func clearPendingLetter() {
        pendingLetterID = nil
    }
}
