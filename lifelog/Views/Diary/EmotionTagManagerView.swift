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
    @State private var showEmojiPicker = false
    
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
                        HStack {
                            Text("絵文字を選択")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("← スクロール →")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
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
                                // もっと選ぶボタン
                                Button {
                                    showEmojiPicker = true
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.title2)
                                        .foregroundStyle(Color.accentColor)
                                        .padding(8)
                                        .background(Color(.secondarySystemBackground), in: Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // タグ名入力
                    HStack(spacing: 12) {
                        Text(newTagEmoji.isEmpty ? "📝" : newTagEmoji)
                            .font(.title2)
                            .frame(width: 44)
                        TextField("タグ名を入力", text: $newTagName)
                    }
                    
                    // 表示する気分
                    Picker("表示する気分", selection: $newTagMoodRange) {
                        Text("😢 気分1-2").tag(1)
                        Text("😐 気分3").tag(3)
                        Text("😊 気分4-5").tag(5)
                    }
                    .pickerStyle(.segmented)
                    
                    // 追加ボタン
                    Button {
                        addNewTag()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("タグを追加")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newTagName.isEmpty)
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
                        // 入力中のタグがあれば保存
                        if !newTagName.isEmpty {
                            addNewTag()
                        }
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showEmojiPicker) {
                EmojiGridPickerSheet { emoji in
                    newTagEmoji = emoji
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
        case 1...2: return String(localized: "気分1-2")
        case 3...3: return String(localized: "気分3")
        case 4...5: return String(localized: "気分4-5")
        default: return String(localized: "気分\(range.lowerBound)-\(range.upperBound)")
        }
    }
}

// MARK: - Emoji Grid Picker Sheet
private struct EmojiGridPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String) -> Void
    
    // 絵文字カテゴリ
    private let categories: [(name: String, emojis: [String])] = [
        ("顔", ["😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "🙂", "😊", "😇", "🥰", "😍", "🤩", "😘", "😗", "😚", "😋", "😛", "😜", "🤪", "😝", "🤑", "🤗", "🤭", "🤫", "🤔", "🤐", "🤨", "😐", "😑", "😶", "😏", "😒", "🙄", "😬", "😮‍💨", "🤥", "😌", "😔", "😪", "🤤", "😴", "😷", "🤒", "🤕", "🤢", "🤮", "🤧", "🥵", "🥶", "🥴", "😵", "🤯", "🤠", "🥳", "🥸", "😎", "🤓", "🧐", "😭", "😢", "😰", "😱", "😔", "😩", "😣", "😖", "😓"]),
        ("感情", ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔", "❤️‍🔥", "❤️‍🩹", "💕", "💞", "💓", "💗", "💖", "💝", "💘", "✨", "⭐", "🌟", "💫", "🔥", "💯", "💢", "💥", "💦", "💨", "💣", "💬", "💭", "💤"]),
        ("ジェスチャー", ["👍", "👎", "👊", "✊", "🤛", "🤜", "👏", "🙌", "👐", "🤲", "🤝", "🙏", "✍️", "💅", "🤳", "💪", "👀", "👁️", "👅", "👄"]),
        ("自然", ["🌸", "💮", "🌹", "🥀", "🌺", "🌻", "🌼", "🌷", "🌱", "🪴", "🌲", "🌳", "🌴", "🌵", "🌿", "☘️", "🍀", "🍁", "🍂", "🍃", "🌙", "☀️", "⭐", "🌟", "🌈", "☔", "❄️", "🔥", "💧", "🌊"]),
        ("食べ物", ["🍎", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🍈", "🍒", "🍑", "🥭", "🍍", "🥝", "🍅", "🥑", "🥦", "🌽", "🥕", "🍕", "🍔", "🍟", "🍰", "🍩", "🍪", "☕", "🍵", "🍺", "🍷"]),
        ("活動", ["⚽", "🏀", "🎾", "🎮", "🎨", "🎬", "🎤", "🎧", "🎼", "🎹", "🎸", "🏆", "🥇", "🥈", "🥉", "🏅", "🎯", "🎳"]),
        ("記号", ["❤️", "💔", "❣️", "💕", "💞", "💓", "💗", "💖", "💝", "💘", "✅", "❌", "⭕", "💯", "💢", "❗", "❓", "‼️", "⁉️", "✔️", "☑️", "🔴", "🟠", "🟡", "🟢", "🔵", "🟣", "⚫", "⚪", "🟤"])
    ]
    
    @State private var selectedCategory = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // カテゴリタブ
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(categories.enumerated()), id: \.offset) { index, category in
                            Button {
                                selectedCategory = index
                            } label: {
                                Text(localizedCategoryName(category.name))
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedCategory == index ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                                    .foregroundStyle(selectedCategory == index ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 12)
                
                Divider()
                
                // 絵文字グリッド
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .center), count: 8), alignment: .leading, spacing: 8) {
                        ForEach(categories[selectedCategory].emojis, id: \.self) { emoji in
                            Button {
                                onSelect(emoji)
                                HapticManager.light()
                                dismiss()
                            } label: {
                                Text(emoji)
                                    .font(.title)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("絵文字を選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func localizedCategoryName(_ name: String) -> String {
        switch name {
        case "顔": return String(localized: "顔")
        case "感情": return String(localized: "感情")
        case "ジェスチャー": return String(localized: "ジェスチャー")
        case "自然": return String(localized: "自然")
        case "食べ物": return String(localized: "食べ物")
        case "活動": return String(localized: "活動")
        case "記号": return String(localized: "記号")
        default: return name
        }
    }
}
