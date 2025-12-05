//
//  EmotionTagManagerView.swift
//  lifelog
//
//  Created by Codex on 2025/12/05.
//

import SwiftUI

/// 感情タグを管理するビュー（追加・削除）
struct EmotionTagManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var tagManager = EmotionTagManager.shared
    
    @State private var newTagEmoji = ""
    @State private var newTagName = ""
    @State private var newTagMoodRange = 3 // 1=ネガティブ, 3=中立, 5=ポジティブ
    
    private let emojiOptions = [
        // 気分1-2（ネガティブ）
        "😭", "😢", "😰", "😱", "😔", "😩", "😣", "😖", "😓",
        // 気分3（中立）
        "😐", "🤔", "😌", "🥺", "😴",
        // 気分4-5（ポジティブ）
        "😊", "🙂", "😄", "🥳", "💪", "✨", "🔥", "❤️", "🎉", "⭐️", "🌟", "💫"
    ]
    
    var body: some View {
        NavigationStack {
            List {
                // 新規タグ追加セクション
                Section("タグを追加") {
                    // 絵文字選択
                    VStack(alignment: .leading, spacing: 8) {
                        Text("絵文字を選択")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(emojiOptions, id: \.self) { emoji in
                                    Button {
                                        newTagEmoji = emoji
                                    } label: {
                                        Text(emoji)
                                            .font(.title2)
                                            .padding(8)
                                            .background(newTagEmoji == emoji ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground),
                                                       in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    
                    // タグ名入力
                    HStack(spacing: 12) {
                        Text(newTagEmoji.isEmpty ? "📝" : newTagEmoji)
                            .font(.title2)
                            .frame(width: 44)
                        TextField("タグ名を入力", text: $newTagName)
                        Button {
                            addNewTag()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.green)
                                .font(.title2)
                        }
                        .disabled(newTagName.isEmpty)
                    }
                    
                    Picker("表示する気分", selection: $newTagMoodRange) {
                        Text("😢 気分1-2").tag(1)
                        Text("😐 気分3").tag(3)
                        Text("😊 気分4-5").tag(5)
                    }
                    .pickerStyle(.segmented)
                }
                
                // カスタムタグ一覧
                if !tagManager.customTags.isEmpty {
                    Section("追加したタグ") {
                        ForEach(tagManager.customTags) { tag in
                            HStack {
                                Text(tag.displayText)
                                Spacer()
                                Text(moodRangeLabel(tag.moodRange))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                tagManager.removeCustomTag(tagManager.customTags[index])
                            }
                        }
                    }
                }
                
                // デフォルトタグ一覧
                Section("デフォルトタグ") {
                    ForEach(EmotionTagManager.defaultTags) { tag in
                        HStack {
                            Text(tag.displayText)
                            Spacer()
                            Text(moodRangeLabel(tag.moodRange))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("感情タグを管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func addNewTag() {
        guard !newTagName.isEmpty else { return }
        
        let moodRange: ClosedRange<Int> = switch newTagMoodRange {
        case 1: 1...2
        case 5: 4...5
        default: 3...3
        }
        
        let tag = EmotionTag(
            emoji: newTagEmoji.isEmpty ? "📝" : newTagEmoji,
            name: newTagName,
            moodRange: moodRange
        )
        
        tagManager.addCustomTag(tag)
        newTagEmoji = ""
        newTagName = ""
    }
    
    private func moodRangeLabel(_ range: ClosedRange<Int>) -> String {
        switch range {
        case 1...2: return "気分1-2"
        case 3...3: return "気分3"
        case 4...5: return "気分4-5"
        default: return "気分\(range.lowerBound)-\(range.upperBound)"
        }
    }
}
