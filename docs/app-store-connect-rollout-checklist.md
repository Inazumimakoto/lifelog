# App Store Connect 海外公開チェックリスト

更新日: 2026-06-28

対象ロケール: `ja`, `en`, `ko`, `zh-Hans`, `zh-Hant`。台湾向けは v1 では `zh-Hant` として扱う。

## 1. リリース前提

- アプリ内の独自言語切替 UI は作らず、iOS のアプリ言語設定に従う。
- 既存ユーザーの本文、カテゴリ名、タグ名、場所名、手紙本文は翻訳・上書きしない。
- JP storefront は無料フル解放、JP 以外は freemium / premium の制限を有効にする。
- IAP は JP では販売不可、JP 以外では販売可にする。
- push / PR はこの作業では行わない。

## 2. App Store Connect 設定

- Paid Apps Agreement、税務、銀行情報が有効か確認する。
- アプリのローカライズを追加する:
  - Japanese
  - English
  - Korean
  - Simplified Chinese
  - Traditional Chinese
- `docs/app-store-localization.md` の App metadata を各ロケールに転記する。
- スクリーンショットを各ロケールで用意する。スクショ文言はアプリ言語に合わせ、ユーザー保存データ由来の日本語を混ぜない。
- Support URL / Privacy URL は `docs/lifelog-support.md` の公開先にする。
- Privacy Nutrition Label を更新する:
  - HealthKit: 読み取りのみ、第三者提供なし。
  - Calendar: 読み取りのみ。
  - Location: 天気表示と日記保存。
  - Firebase: 共有手紙、認証、通知、暗号化済み添付。
  - AI直接分析: 選択データの一時処理。

## 3. IAP 設定

- サブスクリプショングループ: `Lifelify Premium`
- 商品:
  - `com.inazumimakoto.lifelify.premium.monthly`
  - `com.inazumimakoto.lifelify.premium.yearly`
  - `com.inazumimakoto.lifelify.premium.lifetime`
- 各商品の表示名・説明を `docs/app-store-localization.md` から5言語分入力する。
- Availability:
  - Japan: すべて販売不可。
  - Japan 以外: 販売可。
- 初期価格:
  - Monthly: `US$1.99`
  - Yearly: `US$14.99`
  - Lifetime: `US$29.99`
- アプリ本体の審査提出時に IAP も一緒に提出する。

## 4. Build / Test

- Release build:
  - `xcodebuild -project lifelog.xcodeproj -scheme lifelog -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`
- Unit/UI tests:
  - `xcodebuild test -project lifelog.xcodeproj -scheme lifelog -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
  - 指定 Simulator がない場合は、利用可能な iPhone Simulator に置き換える。
  - Keychain / E2EE テストのため、test では `CODE_SIGNING_ALLOWED=NO` を付けない。
- Firebase Functions:
  - `cd functions && npm run build`
- ローカライズ検査:
  - `xcodebuild -exportLocalizations -project lifelog.xcodeproj -localizationPath /tmp/lifelog-loc-export -exportLanguage ja`
  - `rg "ja_JP|ja-JP" lifelog LifelogWidgets functions docs README.md`
  - `.xcstrings` の5言語欠落と `%@` / `%lld` などのプレースホルダ差分を検査する。

## 5. Simulator QA

各言語で `-AppleLanguages` / `-AppleLocale` または iOS の App Language を使って確認する。

- `ja`: 日本語、日本 storefront 無料解放。
- `en`: English、US storefront、premium lock / paywall / restore。
- `ko`: 한국어、KR storefront、主要タブと通知文言。
- `zh-Hans`: 简体中文、CN/US storefront、Widget と壁紙カレンダー導線。
- `zh-Hant`: 繁體中文、TW storefront 想定、手紙導線と App Intent。

確認画面:

- Today
- Calendar / event editor / category settings
- Tasks
- Diary editor / emotion tags / location tags
- Habits / countdown / premium lock
- Journal / review map
- Settings / permission setup / premium paywall
- Letter to Future
- Shared Letters
- Widgets: schedule, habits, memo, anniversary
- App Intent: `UpdateWallpaperCalendarIntent`
- Local notifications and Firebase letter notifications

## 6. TestFlight / Sandbox QA

- Sandbox Tester を作成する。
- JP storefront:
  - 課金商品が販売不可でも全機能が利用できる。
  - Paywall が日本ストア無料案内になる。
- 非JP storefront:
  - 無料上限が有効。
  - 月額 / 年額 / 買い切り購入が通る。
  - 復元後に entitlement が復旧する。
  - Widget / Letter / Review Map / Wallpaper Calendar の lock が解除される。
- FCM:
  - `users.preferredLanguageCode` が保存される。
  - Functions が `ja/en/ko/zh-Hans/zh-Hant` の通知文言を出し分ける。

## 7. 提出直前

- App Store screenshots と metadata が5言語で揃っている。
- IAP 商品が5言語でローカライズ済み。
- Support / Privacy URL が公開 URL でアクセスできる。
- Firebase Functions を本番へ deploy するタイミングを決める。
- Push notification capability、Associated Domains、App Groups、Keychain / Sign in with Apple entitlement を確認する。
- 審査メモに以下を明記する:
  - JP storefront は無料、非JP storefront は premium。
  - Shared letters are end-to-end encrypted.
  - AI direct analysis performs one-time processing and does not store payloads.

## 8. リリース後モニタリング

- 1日目: crash、purchase failure、restore failure、FCM notification failure。
- 7日目: locale 別 retention、paywall conversion、review sentiment。
- 14日目: 月額 / 年額 / 買い切り比率、無料上限到達率。
- 30日目: 解約傾向、地域別CVR、スクショ/metadataの改善候補。

## 9. Apple 公式参考リンク

- App availability: https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store
- IAP availability: https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-availability-for-in-app-purchases/
- Subscription availability: https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-availability-for-an-auto-renewable-subscription
- Subscription pricing: https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions
