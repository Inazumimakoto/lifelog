//
//  LLMConfig.swift
//  lifelog
//
//  開発者PCのLLM設定
//  Cloudflare TunnelのURLはGit管理外のLLMConfig.plistから読み込む
//

import Foundation

/// 開発者PCのLLM設定
enum LLMConfig {
    /// Cloudflare TunnelのURL
    /// バンドル内のLLMConfig.plist（Git管理外）の "TunnelURL" キーから読み込む
    /// plistが無い場合は空文字となり、DevPCLLMService.isAvailableがfalseになる
    static let tunnelURL: String = {
        guard let url = Bundle.main.url(forResource: "LLMConfig", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any],
              let tunnelURL = dict["TunnelURL"] as? String else {
            return ""
        }
        return tunnelURL
    }()

    /// 使用するモデル名
    static let modelName = "deepseek-r1:8b"

    /// タイムアウト時間（秒）
    static let timeoutSeconds: TimeInterval = 120

    /// 週あたりの使用制限回数
    static let weeklyLimit = 20
}
