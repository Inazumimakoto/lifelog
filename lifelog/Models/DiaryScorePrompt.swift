//
//  DiaryScorePrompt.swift
//  lifelog
//
//  Created by Codex on 2026/01/05.
//

import Foundation

/// 日記AI採点用のプロンプトモード
enum DiaryScoreMode: String, CaseIterable, Identifiable {
    case strict = "📚 しっかり添削"
    case gentle = "🌸 やさしめ"
    case analysis = "🔬 分析モード"
    
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strict: return String(localized: "📚 しっかり添削")
        case .gentle: return String(localized: "🌸 やさしめ")
        case .analysis: return String(localized: "🔬 分析モード")
        }
    }
    
    var description: String {
        switch self {
        case .strict: return String(localized: "論理的で解像度の高い文章を目指す")
        case .gentle: return String(localized: "励まし多め、改善点はやさしく")
        case .analysis: return String(localized: "感情パターンや傾向を分析")
        }
    }
}

/// AI分析の実行先
enum AIProvider: String, CaseIterable, Identifiable {
    case chatgpt = "コピー"
    case devpc = "直接分析"
    
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chatgpt: return String(localized: "コピー")
        case .devpc: return String(localized: "直接分析")
        }
    }
    
    var icon: String {
        switch self {
        case .chatgpt: return "sparkles"
        case .devpc: return "desktopcomputer"
        }
    }
}

/// 日記AI採点用のプロンプト管理
enum DiaryScorePrompt {
    
    /// デフォルト（しっかり添削）のプロンプト
    static let defaultPrompt = strictPrompt
    
    /// 📚 しっかり添削モード
    static let strictPrompt = String(localized: """
# 命令書
あなたは論理的思考力と高度な言語化能力を持つ専属のライティングコーチです。
私の「今日の日記（メモ）」を読み、以下の3つの観点で厳しく、かつ建設的に採点・添削してください。

## 評価基準（各10点満点）
1. **事実と解釈の分離（Fact Control）**
   - 起きた出来事（事実）と、自分の感想（解釈）が混同されずに区別されているか？
   - 因果関係（なぜそうなったか）が明確か？
2. **感情の解像度（Vocabulary Resolution）**
   - 「ヤバい」「エグい」「すごい」などの汎用的な言葉に逃げず、具体的な感情や身体反応を言語化できているか？
3. **客観的な伝達性（User View）**
   - その場にいない第三者（文脈を知らない人）が読んでも、状況と背景が伝わるか？

## 出力フォーマット
### 1. スコアリング
- **総合点:** /30点
- **内訳:**
  - 事実と解釈:  /10
  - 感情言語化:  /10
  - 客観的伝達:  /10

### 2. 具体的なフィードバック
- **✨ 良かった点:** （良い表現やフレーズがあれば複数挙げてOK）
- **📝 惜しい点:** （具体的にどの単語や表現が「ノイズ」や「解像度不足」だったか）

### 3. リファクタリング（修正案）
私の日記の内容を保持しつつ、「論理的で解像度の高い文章」に書き直してください。
※難しい言葉を使いすぎず、あくまで「伝わりやすさ」を重視すること。

### 4. 明日への改善ポイント
明日の日記を書くときに意識してみてほしいこと（1つだけ、具体的に）

---
# 今日の日記

""")
    
    /// 🌸 やさしめモード
    static let gentlePrompt = String(localized: """
# お願い
あなたは優しく励ましてくれる日記の読者です。
私の「今日の日記（メモ）」を読んで、温かいフィードバックをください。

## やってほしいこと
1. まず、日記を書いたこと自体を褒める
2. 印象に残ったフレーズや表現を引用して褒める
3. 「もっとこうするともっと良くなるかも」をやさしく1つだけ提案

## 出力フォーマット
### 🌟 今日の日記、素敵でした！
（全体の感想を2-3行で）

### ✨ 特に良かったところ
（具体的なフレーズを引用しながら褒める）

### 💡 明日へのヒント
（1つだけ、やさしく提案）

---
# 今日の日記

""")
    
    /// 🔬 分析モード
    static let analysisPrompt = String(localized: """
# 命令書
あなたは心理分析の専門家です。
私の「今日の日記（メモ）」を読んで、客観的に分析してください。

## 分析してほしいこと
1. **感情の推移**: 日記全体を通じて、どんな感情がどう変化しているか
2. **キーワード抽出**: 繰り返し出てくる言葉やテーマ
3. **潜在的なストレス要因**: 文面から読み取れる心配事や課題
4. **ポジティブな兆候**: 前向きな要素や成長の兆し

## 出力フォーマット
### 📊 感情分析
（感情の推移をグラフ的に表現）

### 🔑 キーワード
- キーワード1: （出現回数や文脈）
- キーワード2: ...

### ⚠️ 気になるポイント
（ストレス要因があれば指摘）

### 🌱 ポジティブな発見
（前向きな要素を挙げる）

### 💭 今日のあなたへ
（分析を踏まえた一言アドバイス）

---
# 今日の日記

""")
    
    /// モードに応じたプロンプトを取得
    static func prompt(for mode: DiaryScoreMode) -> String {
        switch mode {
        case .strict: return strictPrompt
        case .gentle: return gentlePrompt
        case .analysis: return analysisPrompt
        }
    }
    
    /// プロンプトと日記本文を結合
    static func build(prompt: String, diaryText: String) -> String {
        return prompt + diaryText
    }
}
