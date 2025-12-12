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
    
    /// 開封待ちの手紙ID（通知タップ時にセット）- 未来への手紙用
    @Published var pendingLetterID: UUID? = nil
    
    /// 開封待ちの共有手紙ID（通知タップ時にセット）- 大切な人への手紙用
    @Published var pendingSharedLetterID: String? = nil
    
    private init() {}
    
    /// 未来への手紙の通知から遷移する
    func handleLetterNotification(letterID: UUID) {
        pendingLetterID = letterID
    }
    
    /// 共有手紙の通知から遷移する
    func handleSharedLetterNotification(letterID: String) {
        pendingSharedLetterID = letterID
    }
    
    /// ディープリンク処理完了
    func clearPendingLetter() {
        pendingLetterID = nil
    }
    
    /// 共有手紙のディープリンク処理完了
    func clearPendingSharedLetter() {
        pendingSharedLetterID = nil
    }
}
