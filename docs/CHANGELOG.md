# Changelog

All notable changes to this project will be documented in this file.

## [1.15.0] - Unreleased

### Added
- **予定ウィジェットの月間カレンダー**: 中サイズの左に今日の予定・タスク、右に当月のカレンダーを表示。今日の丸表示、予定のある日の点表示、日付タップでその日の詳細を開く操作に対応。
- **多言語対応**: 日本語に加え、英語・韓国語・中国語（簡体字／繁体字）に対応。アプリ、ウィジェット、通知などの表記を iOS の言語・地域設定に合わせる。

### Improved
- 中サイズの横幅を活かした2列構成に変更。重複する月名を省き、4〜6週の月と一覧の省略件数表示が枠内に収まるよう調整。
- 日をまたぐ予定、月末、週の開始曜日、夏時間を考慮して予定の点と日付を表示。

### Development
- シミュレーターのデモデータを専用ストアへ分離。実機・Release ビルドにはデモ投入処理を含めない。
- アプリ本体・ウィジェットのバージョンを 1.15.0、ビルド番号を 50 に更新。
- App Store 更新文の5言語草案: `docs/release-notes-v1.15.0.md`。

## [1.7.2] - 2026-01-05

### Added
- **AI日記採点機能**: 日記をAIに採点してもらう新機能。3つのモード（しっかり添削/やさしめ/分析モード）を搭載。
- **アプリの日本語化**: システムUI（コピー、選択など）が日本語で表示されるように変更。

### Fixed
- **睡眠データの正確性向上**: 深夜0時を跨ぐ睡眠の就寝時刻が正しく表示されるように修正。AI分析用データ書き出しにも反映。
- **日記入力のパフォーマンス改善**: キー入力時のラグを解消。保存処理にデバウンスを追加し、スムーズな入力体験を実現。

### Changed
- **未来への手紙の配信設定UI改善**: 日付・時刻の固定/ランダムを独立して設定可能に。より柔軟な配信設定が可能に。

### Technical
- 睡眠データ集計ロジックを改善（日付境界処理の最適化）
- DiaryViewModelにデバウンス機構を追加（0.5秒遅延保存）
- developmentRegionをjaに変更

## [1.7] - 2025-12-13

### Added
- **大切な人への手紙 🆕**: 友達と手紙を送り合える新機能。エンドツーエンド暗号化（E2EE）で内容を完全保護。
  - 招待リンクで友達追加
  - 配信日時を指定して手紙を送信
  - 美しい開封アニメーション
  - 写真添付対応（5枚まで）
  - プッシュ通知で手紙到着をお知らせ
- **通報・ブロック機能**: 不適切なユーザーを通報・ブロック可能。
- **プライバシーポリシーリンク**: 設定画面からプライバシーポリシーを直接確認可能。

### Changed
- **通知設定**: 「未来への手紙」の設定を「手紙」に統合し、友達からの手紙通知も含むように変更。
- **プライバシーポリシー更新**: Firebase利用と暗号化についての説明を追加。

### Technical
- Firebase Authentication（Apple ID Sign-In）
- Firebase Cloud Firestore（手紙データ保存）
- Firebase Cloud Functions（配信スケジューリング、ブロック処理）
- Firebase Cloud Messaging（プッシュ通知）
- エンドツーエンド暗号化（X25519 + ChaCha20-Poly1305）

## [1.6] - 2025-12-10

### Added
- **AI書き出し改善**: コピー完了後にAIアプリ選択シートを表示。ChatGPT、Gemini、Claude、Grok、Poeへ直接遷移可能。
- **一時チャット推奨**: AI書き出し時に「一時チャット」での利用を推奨するヒントを表示。
- **Apple Weather クレジット**: WeatherKit利用に伴うApple Weather表記を追加（App Store要件対応）。

### Changed
- **未来への手紙 ハプティクス強化**: 開封時の振動を最大級に強化。連続振動パターンで達成感を演出。

### Fixed
- **App Store審査対応**: Apple Weatherのクレジット表記を天気表示画面に追加。

## [1.4] - 2025-12-06

### Added
- **App Lock**: Face ID / Passcode authentication for enhanced privacy.
- **Settings Screen**: Centralized settings for Calendar, Health, and Privacy.
- **Smart Review**: Automatic review requests based on user engagement (journaling, habits, tasks).
- **FAB (Floating Action Button)**: Standardized "Add" button in Today and Calendar tabs.
- **Haptic Feedback**: Added tactile feedback for key actions (completion, navigation).
- **Notification Settings**: Category-based event reminders and priority-based task reminders with customizable defaults.
- **Reminder Indicator**: Bell icon displayed on events and tasks with reminders enabled.

### Changed
- **Toolbar**: Unified top-right toolbar buttons (Memo, List, Settings) across home and calendar.
- **Header**: Redesigned Today view header for better date and weather visibility.
- **Calendar Settings**: Moved external calendar mapping to the main Settings screen for better accessibility.
- **Priority Order**: Task priority picker now shows High → Medium → Low order.

### Fixed
- **Sleep Timeline**: Merged fragmented sleep intervals into continuous blocks for better readability.
- **Weather Display**: Adjusted font sizes and alignment.

## [1.0.0] - 2025-11-13
- Initial Release
