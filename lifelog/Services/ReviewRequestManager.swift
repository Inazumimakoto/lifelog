//
//  ReviewRequestManager.swift
//  lifelog
//
//  Created by Codex on 2025/12/06.
//

import Foundation
import StoreKit
import SwiftUI
import UIKit
import os

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
    private let minimumDaysBetweenRequests: Double = 120 // 約4ヶ月（Appleの上限である年3回に対して余裕を持つ）
    private let minimumInitialDays: Double = 3 // 初回起動から最低3日は依頼しない
    private let minimumActionsBeforeRequest: Int = 5 // 最低5回のポジティブアクションが必要

    private let defaults: UserDefaults
    private var hasRecordedLaunchThisSession = false
    private var isRequestScheduled = false

    // Match AppDataStore's workaround for Swift's implicit isolated-deinit
    // back-deployment crash on iOS 26.1.
    nonisolated deinit {}

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// アプリ起動時に呼び出し、初回起動日と起動回数を正確に記録する
    func recordAppLaunch(now: Date = Date()) {
        guard !hasRecordedLaunchThisSession else { return }
        hasRecordedLaunchThisSession = true
        if defaults.object(forKey: kInitialLaunchDate) == nil {
            defaults.set(now, forKey: kInitialLaunchDate)
        }
        let current = defaults.integer(forKey: kAppLaunchCount)
        defaults.set(current + 1, forKey: kAppLaunchCount)
    }

    /// ポジティブなアクション（日記保存、タスク完了、習慣達成、手紙開封など）を記録し、
    /// 条件を満たせばレビューを依頼する
    func registerPositiveAction(now: Date = Date()) {
        guard !PersistenceController.isRunningTests, !PersistenceController.isSimulatorDemoMode else { return }
        if defaults.object(forKey: kInitialLaunchDate) == nil {
            defaults.set(now, forKey: kInitialLaunchDate)
        }
        let currentCount = defaults.integer(forKey: kActionCount)
        let newCount = currentCount + 1
        defaults.set(newCount, forKey: kActionCount)

        AppLogger.general.debug("ReviewRequestManager: Positive action registered. Total: \(newCount)")

        if shouldRequestReview(now: now) {
            requestReview(now: now)
        }
    }

    /// 手動でレビュー依頼を表示（設定画面などから）
    /// App Store のレビューページを直接開く
    func requestReviewManually() {
        let appID = "6755782099"
        if let url = URL(string: "https://apps.apple.com/app/id\(appID)?action=write-review") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Internal for Testing

    func shouldRequestReview(now: Date = Date()) -> Bool {
        // 1. 初回起動からの期間チェック
        guard let initialDate = defaults.object(forKey: kInitialLaunchDate) as? Date else { return false }
        let daysSinceInstall = now.timeIntervalSince(initialDate) / 86_400
        if daysSinceInstall < minimumInitialDays {
            return false
        }

        // 2. アクション回数チェック
        let actionCount = defaults.integer(forKey: kActionCount)
        if actionCount < minimumActionsBeforeRequest {
            return false
        }

        // 3. 前回依頼からの期間チェック
        if let lastRequest = defaults.object(forKey: kLastRequestDate) as? Date {
            let daysSinceLastRequest = now.timeIntervalSince(lastRequest) / 86_400
            if daysSinceLastRequest < minimumDaysBetweenRequests {
                return false
            }
        }

        return true
    }

    // MARK: - Private

    private func requestReview(now: Date) {
        guard !isRequestScheduled else { return }
        isRequestScheduled = true

        // 完了アニメーションなどを阻害しないよう少し遅延させてから、
        // フォアグラウンドアクティブなシーンでのみ依頼する
        _Concurrency.Task { @MainActor [weak self] in
            defer { self?.isRequestScheduled = false }
            try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
            guard let self,
                  let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
                return
            }
            AppStore.requestReview(in: scene)
            self.defaults.set(Date(), forKey: self.kLastRequestDate)
            self.defaults.set(0, forKey: self.kActionCount)
            AppLogger.general.info("ReviewRequestManager: Review requested")
        }
    }
}
