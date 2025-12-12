# Changelog

All notable changes to this project will be documented in this file.

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
