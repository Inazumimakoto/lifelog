//
//  EmotionTag.swift
//  lifelog
//
//  Created by Codex on 2025/12/05.
//

import Foundation
import SwiftUI
import Combine

/// 感情タグを表すモデル
struct EmotionTag: Identifiable, Codable, Hashable {
    let id: UUID
    var emoji: String
    var name: String
    var moodRange: ClosedRange<Int> // 1-2: ネガティブ, 3: 中立, 4-5: ポジティブ
    
    init(id: UUID = UUID(), emoji: String, name: String, moodRange: ClosedRange<Int>) {
        self.id = id
        self.emoji = emoji
        self.name = name
        self.moodRange = moodRange
    }
    
    var displayText: String {
        "\(emoji)\(localizedName)"
    }

    var localizedName: String {
        BuiltInDisplayName.emotionTag(name)
    }
    
    var hashTag: String {
        "#\(name)"
    }
    
    // Codable conformance for ClosedRange
    enum CodingKeys: String, CodingKey {
        case id, emoji, name, moodLower, moodUpper
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        emoji = try container.decode(String.self, forKey: .emoji)
        name = try container.decode(String.self, forKey: .name)
        let lower = try container.decode(Int.self, forKey: .moodLower)
        let upper = try container.decode(Int.self, forKey: .moodUpper)
        moodRange = lower...upper
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(emoji, forKey: .emoji)
        try container.encode(name, forKey: .name)
        try container.encode(moodRange.lowerBound, forKey: .moodLower)
        try container.encode(moodRange.upperBound, forKey: .moodUpper)
    }
}

/// 感情タグを管理するマネージャー
@MainActor
final class EmotionTagManager: ObservableObject {
    static let shared = EmotionTagManager()
    
    @Published var customTags: [EmotionTag] = []
    
    private let userDefaultsKey = "customEmotionTags"
    
    /// デフォルトのタグ一覧
    static let defaultTags: [EmotionTag] = [
        // ネガティブ (気分 1-2)
        EmotionTag(emoji: "😢", name: "悲しい", moodRange: 1...2),
        EmotionTag(emoji: "😠", name: "イライラ", moodRange: 1...2),
        EmotionTag(emoji: "😰", name: "不安", moodRange: 1...2),
        EmotionTag(emoji: "😴", name: "疲れた", moodRange: 1...2),
        EmotionTag(emoji: "😔", name: "落ち込み", moodRange: 1...2),
        
        // 中立 (気分 3)
        EmotionTag(emoji: "😐", name: "普通", moodRange: 3...3),
        EmotionTag(emoji: "🤔", name: "モヤモヤ", moodRange: 3...3),
        EmotionTag(emoji: "😌", name: "まあまあ", moodRange: 3...3),
        
        // ポジティブ (気分 4-5)
        EmotionTag(emoji: "😊", name: "楽しい", moodRange: 4...5),
        EmotionTag(emoji: "🥳", name: "嬉しい", moodRange: 4...5),
        EmotionTag(emoji: "😌", name: "穏やか", moodRange: 4...5),
        EmotionTag(emoji: "💪", name: "やる気", moodRange: 4...5),
        EmotionTag(emoji: "✨", name: "充実", moodRange: 4...5)
    ]
    
    private init() {
        loadCustomTags()
    }
    
    /// 全タグ（デフォルト + カスタム）
    var allTags: [EmotionTag] {
        Self.defaultTags + customTags
    }
    
    /// 指定した気分に対応するタグを取得
    func tags(for moodValue: Int) -> [EmotionTag] {
        allTags.filter { $0.moodRange.contains(moodValue) }
    }
    
    /// カスタムタグを追加
    func addCustomTag(_ tag: EmotionTag) {
        customTags.append(tag)
        saveCustomTags()
    }
    
    /// カスタムタグを削除
    func removeCustomTag(_ tag: EmotionTag) {
        customTags.removeAll { $0.id == tag.id }
        saveCustomTags()
    }
    
    /// デフォルトタグかどうか
    func isDefaultTag(_ tag: EmotionTag) -> Bool {
        Self.defaultTags.contains { $0.name == tag.name && $0.emoji == tag.emoji }
    }
    
    private func saveCustomTags() {
        if let data = try? JSONEncoder().encode(customTags) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
    
    private func loadCustomTags() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let tags = try? JSONDecoder().decode([EmotionTag].self, from: data) {
            customTags = tags
        }
    }
}
