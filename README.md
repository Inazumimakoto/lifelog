# 🧪 AI-Only Development Project
This entire iOS app was built end-to-end using AI — including requirements, architecture, SwiftUI code, refactors, bug fixes, and documentation.  
No hand-written code. No manual UI building. Fully AI-driven.

# lifelog

統合ライフログ (Bullet Journal 風) iOS アプリ。Today / カレンダー / Habits & Countdown / Health の 4 タブで予定・タスク・日記・習慣・ヘルスデータをまとめて管理します。

## ドキュメント

| 内容 | ファイル |
| --- | --- |
| 要件定義・機能一覧 | `docs/requirements.md` |
| 画面ごとの UI / 操作ガイドライン | `docs/ui-guidelines.md` |
| コントリビューターガイド | [AGENTS.md](AGENTS.md) |

実装では上記ドキュメントをソースのコメントから参照しています。仕様変更の際は **必ず docs 配下を更新し、変更に関連する View / ViewModel のコメントにある参照を確認・追記** してください。

## 運用ルール

1. 新しい要求や変更が届いたら `docs/requirements.md` と `docs/ui-guidelines.md` を更新する。変更履歴は PR/コミット本文にも記載。
2. 仕様に紐づく View / ViewModel (例: TodayView, JournalView(カレンダー), HealthDashboardView など) のコメントにドキュメント参照を残す。要件更新時はそのコメントのリンクが最新になるよう保守する。
3. 実装側で迷いが出た場合は、該当ドキュメントを参照しつつコメント/README にメモを追加する。これにより設計意図を後続タスクで辿りやすくする。

## ビルド

```
xcodebuild -project lifelog.xcodeproj -scheme lifelog -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

シミュレータが利用できない環境では CoreSimulatorService 絡みで失敗することがあります。実機/ローカルの Xcode で改めて実行してください。
