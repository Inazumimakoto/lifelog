//
//  HelpView.swift
//  lifelog
//
//  Created by Codex on 2025/12/07.
//

import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                // 概要
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("lifelifyへようこそ！")
                            .font(.headline)
                        Text("毎日の生活を記録し、振り返るためのアプリです。日記、習慣、予定、健康データを一元管理できます。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                
                // 今日タブ
                Section("📅 今日タブ") {
                    HelpRow(icon: "sun.max.fill", title: "今日の概要", description: "天気、予定、習慣、タスクを一覧で確認できます")
                    HelpRow(icon: "hand.tap.fill", title: "習慣を完了", description: "習慣カードをタップして完了にできます")
                    HelpRow(icon: "hand.tap.fill", title: "完了を取り消し", description: "完了した習慣をもう一度タップで取り消せます")
                }
                
                // カレンダータブ
                Section("📆 カレンダータブ") {
                    HelpRow(icon: "calendar", title: "予定/振り返り切替", description: "上部の「予定カレンダー」「振り返りカレンダー」で切り替え")
                    HelpRow(icon: "photo.fill", title: "振り返りカレンダー", description: "日記の写真やムードが表示されます")
                    HelpRow(icon: "hand.tap.fill", title: "日付をタップ", description: "日記や予定の詳細画面に移動します")
                }
                
                // 日記機能
                Section("📝 日記機能") {
                    HelpRow(icon: "face.smiling", title: "感情タグ", description: "ムードに合わせた絵文字タグを追加できます")
                    HelpRow(icon: "plus.circle.fill", title: "カスタムタグ", description: "「タグを管理」→「+」で好きな絵文字を追加")
                    HelpRow(icon: "star.fill", title: "お気に入り写真", description: "写真の星マークをタップでお気に入りに")
                    HelpRow(icon: "hand.draw.fill", title: "スワイプ", description: "左右スワイプで前後の日記に移動")
                }
                
                // 未来への手紙
                Section("✉️ 未来への手紙") {
                    HelpRow(icon: "envelope.fill", title: "手紙を書く", description: "未来の自分にメッセージを送れます")
                    HelpRow(icon: "calendar.badge.clock", title: "配達日設定", description: "届く日を指定、またはランダムに設定")
                    HelpRow(icon: "envelope.open.fill", title: "開封", description: "届いた手紙をスワイプで開封できます")
                }
                
                // 大切な人への手紙
                Section("💌 大切な人への手紙") {
                    HelpRow(icon: "person.2.fill", title: "友達を追加", description: "招待リンクを共有して友達を追加", highlight: true)
                    HelpRow(icon: "envelope.fill", title: "手紙を送る", description: "配信日時を指定して友達に手紙を送信", highlight: true)
                    HelpRow(icon: "lock.shield.fill", title: "暗号化", description: "内容はE2EE暗号化で開発者にも読めません", highlight: true)
                    HelpRow(icon: "bell.fill", title: "プッシュ通知", description: "手紙が届いたら通知でお知らせ", highlight: true)
                }
                
                // 習慣機能
                Section("✅ 習慣機能") {
                    HelpRow(icon: "plus", title: "習慣を追加", description: "「追加」ボタンから新しい習慣を作成")
                    HelpRow(icon: "flame.fill", title: "ストリーク", description: "連続達成日数が表示されます")
                    HelpRow(icon: "chart.bar.fill", title: "達成率", description: "習慣をタップして詳細と統計を確認")
                }
                
                // カウントダウン機能
                Section("⏳ カウントダウン") {
                    HelpRow(icon: "calendar.badge.clock", title: "記念日を追加", description: "「追加」ボタンから大切な日を登録")
                    HelpRow(icon: "arrow.clockwise", title: "毎年繰り返し", description: "記念日を毎年カウントダウンできます")
                    HelpRow(icon: "bell.fill", title: "通知設定", description: "当日や前日に通知を受け取れます")
                }
                
                // ヘルス機能
                Section("❤️ ヘルスケア") {
                    HelpRow(icon: "figure.walk", title: "歩数グラフ", description: "棒をタップで週平均・先週比を表示")
                    HelpRow(icon: "bed.double.fill", title: "睡眠グラフ", description: "棒をタップで週平均・先週比を表示")
                    HelpRow(icon: "heart.fill", title: "連携設定", description: "設定→外部リンク→ヘルスケアアプリを開く")
                }
                
                // Tips
                Section("💡 Tips") {
                    HelpRow(icon: "bell.fill", title: "通知設定", description: "カテゴリごとに通知のON/OFFができます")
                    HelpRow(icon: "lock.fill", title: "アプリロック", description: "Face ID/Touch IDでアプリを保護できます")
                    HelpRow(icon: "arrow.triangle.2.circlepath", title: "カレンダー連携", description: "iOSカレンダーと自動で同期します")
                }
                
                // リセット
                Section {
                    Button {
                        HintManager.shared.resetAllHints()
                        HapticManager.success()
                    } label: {
                        Label("ヒントを再表示する", systemImage: "arrow.counterclockwise")
                    }
                } footer: {
                    Text("各画面で表示される「💡ヒント」を再度表示します")
                }
            }
            .appThemeBackground()
            .navigationTitle("使い方")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Help Row
private struct HelpRow: View {
    let icon: String
    let title: String
    let description: String
    var highlight: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(highlight ? .yellow : .accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.subheadline.bold())
                    if highlight {
                        Text("NEW")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange, in: Capsule())
                    }
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    HelpView()
}
