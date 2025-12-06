//
//  HapticManager.swift
//  lifelog
//
//  Created by Codex on 2025/12/06.
//

import UIKit

/// アプリ全体で統一したハプティックフィードバックを提供するマネージャー
enum HapticManager {
    
    // MARK: - Impact Feedback
    
    /// 軽いインパクト（タブ切り替え、軽いアクション）
    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    /// 中程度のインパクト（ボタンタップ、確定アクション）
    static func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    /// 重いインパクト（重要なアクション）
    static func heavy() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }
    
    /// ソフト（iOS 13+、繊細な操作）
    static func soft() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred()
    }
    
    /// リジッド（iOS 13+、しっかりした操作）
    static func rigid() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
    }
    
    // MARK: - Notification Feedback
    
    /// 成功（タスク完了、保存成功など）
    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    /// 警告（削除確認など）
    static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
    
    /// エラー（操作失敗など）
    static func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
    
    // MARK: - Selection Feedback
    
    /// 選択変更（ピッカー、セグメント切り替え）
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
    
    // MARK: - Custom Patterns
    
    /// 連続達成（ストリーク更新時）
    static func streak() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // 少し遅れて2回目
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let second = UIImpactFeedbackGenerator(style: .light)
            second.impactOccurred()
        }
    }
    
    /// 全習慣達成
    static func allHabitsComplete() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // 3回の軽いインパクトでお祝い感
        for i in 1...2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
            }
        }
    }
}
