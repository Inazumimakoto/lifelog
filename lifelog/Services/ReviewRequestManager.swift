//
//  ReviewRequestManager.swift
//  lifelog
//
//  Created by Codex on 2025/12/06.
//

import Foundation
import StoreKit
import SwiftUI

/// スマートなレビュー依頼を管理するクラス
/// ユーザーが良い体験をした直後（ポジティブなアクション時）にのみレビューを依頼する
@MainActor
final class ReviewRequestManager {
    static let shared = ReviewRequestManager()
    
    // UserDefaults Keys
    private let kLastRequestDate = "ReviewRequestManager.lastRequestDate"
    private let kActionCount = "ReviewRequestManager.actionCount"
    private let kAppLaunchCount = "ReviewRequestManager.appLaunchCount"
    private let kInitialLaunchDate = "ReviewRequestManager.initialLaunchDate"
    
    // Configuration
    private let minimumDaysBetweenRequests: Double = 120 // 4ヶ月（Appleの制限は年3回程度なので余裕を持つ）
    private let minimumInitialDays: Double = 3 // 初回起動から最低3日は依頼しない
    private let minimumActionsBeforeRequest: Int = 5 // 最低5回のポジティブアクションが必要
    
    private init() {
        incrementLaunchCount()
        if UserDefaults.standard.object(forKey: kInitialLaunchDate) == nil {
            UserDefaults.standard.set(Date(), forKey: kInitialLaunchDate)
        }
    }
    
    /// ポジティブなアクション（日記保存、習慣達成など）が行われたことを記録し、
    /// 条件を満たせばレビューを依頼する
    func registerPositiveAction() {
        let currentCount = UserDefaults.standard.integer(forKey: kActionCount)
        let newCount = currentCount + 1
        UserDefaults.standard.set(newCount, forKey: kActionCount)
        
        print("ReviewRequestManager: Positive action registered. Total: \(newCount)")
        
        // 条件チェック
        if shouldRequestReview() {
            requestReview()
        }
    }
    
    /// 手動でレビュー依頼を表示（設定画面などから）
    func requestReviewManually() {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        SKStoreReviewController.requestReview(in: scene)
    }
    
    // MARK: - Private
    
    private func incrementLaunchCount() {
        let current = UserDefaults.standard.integer(forKey: kAppLaunchCount)
        UserDefaults.standard.set(current + 1, forKey: kAppLaunchCount)
    }
    
    private func shouldRequestReview() -> Bool {
        // 1. 初回起動からの期間チェック
        guard let initialDate = UserDefaults.standard.object(forKey: kInitialLaunchDate) as? Date else { return false }
        let daysSinceInstall = Date().timeIntervalSince(initialDate) / 86400
        if daysSinceInstall < minimumInitialDays {
            return false
        }
        
        // 2. アクション回数チェック
        let actionCount = UserDefaults.standard.integer(forKey: kActionCount)
        if actionCount < minimumActionsBeforeRequest {
            return false
        }
        
        // 3. 前回依頼からの期間チェック
        if let lastRequest = UserDefaults.standard.object(forKey: kLastRequestDate) as? Date {
            let daysSinceLastRequest = Date().timeIntervalSince(lastRequest) / 86400
            if daysSinceLastRequest < minimumDaysBetweenRequests {
                return false
            }
        }
        
        return true
    }
    
    private func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        
        // メインスレッドで少し遅延させて表示（完了アニメーションなどを阻害しないため）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            SKStoreReviewController.requestReview(in: scene)
            UserDefaults.standard.set(Date(), forKey: self.kLastRequestDate)
            UserDefaults.standard.set(0, forKey: self.kActionCount) // カウンタをリセット
            print("ReviewRequestManager: Review requested")
        }
    }
}
