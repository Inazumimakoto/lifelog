# App Store Connect 公開手順チェックリスト

更新日: 2026-02-06

## 1. 進める順番（推奨）
1. App Store Connect で IAP 商品と地域公開設定を作る。
2. TestFlight で購入・復元・機能制限の動作を検証する。
3. 課金まわりだけ最低限の英語対応を入れる。
4. グローバル公開する（日本は無料、海外は有料）。

補足:
- 英語対応は「リリース後に最後でよい」ではない。
- App Store Connect 設定を先に進めるのは問題ないが、本番グローバル公開前に最低限の英語対応は完了させる。

## 2. App Store Connect 設定チェックリスト
- Business セクションで Paid Apps Agreement が承認済みか確認する。
- サブスクリプショングループを作成する（例: `Lifelog Premium`）。
- 商品を作成する:
  - `com.inazumimakoto.lifelog.premium.monthly`（自動更新、1か月）
  - `com.inazumimakoto.lifelog.premium.yearly`（自動更新、1年）
  - `com.inazumimakoto.lifelog.premium.lifetime`（買い切り、非消耗型）
- 各商品の必須メタデータ（表示名、説明、ローカライズ）を入力する。
- 販売地域を設定する:
  - JP ストアフロント: 有料商品はすべて販売不可。
  - JP 以外のストアフロント: 販売可。
- 初期価格を設定する（本書 3 章）。
- アプリ本体の審査提出時に IAP も一緒に提出する。
- Sandbox Tester を作成し、課金テストを実行できる状態にする。

## 3. 初期価格案（JPY 基準）
- リリース初期の推奨価格:
  - 月額: `¥200`
  - 年額: `¥1,800`
  - 買い切り: `¥5,000`

この価格を推奨する理由:
- `¥200 -> ¥1,800` で年額への移行メリットが分かりやすい。
- 買い切り `¥3,000` は安すぎて、サブスク売上を食いやすい。
  - 年額比較だと約 `16.7` か月で元が取れるため、買い切り偏重になりやすい。
  - 安全な目安は「年額の `2.5`〜`3.0` 年分」。
- `¥5,000` は買い切りとして魅力を残しつつ、サブスクを潰しにくい（年額の約 `2.8` 年分）。

リリース後の調整ルール:
- 買い切り比率が高すぎる場合は、先に買い切り価格を上げる（例: `¥6,000` 以上）。
- 有料転換が弱い場合は、買い切りを下げる前に月額のテストを行う。
- 確認タイミング:
  - リリース 14 日目: 無料->有料転換率、月額/年額比率。
  - リリース 30 日目: 買い切り比率、解約傾向。

## 4. QA チェックリスト（日本在住での検証）
- Debug ビルドで確認:
  - `Settings > Developer` からストアフロントを `US` に変更。
  - 非プレミアム状態で無料上限・ロック表示が期待通りか確認。
  - 強制プレミアム ON を切り替えて、解放挙動を確認。
- Sandbox 購入テスト:
  - Sandbox Tester で実際に購入・復元フローを通す。
  - 購入後/復元後に entitlement が正しく更新されるか確認。
- 回帰確認:
  - ストアフロントを `AUTO` に戻す。
  - JP では無料フル解放のままか確認。

## 5. グローバル公開前の最低限英語対応
- Paywall 画面のタイトル、機能リスト、ボタン文言。
- ロックメッセージ（習慣、カウントダウン、地図、手紙、日記写真、日記位置情報）。
- 購入エラー、復元エラーメッセージ。
- App Store 商品メタデータ（商品名、説明、プロモ文）。

## 6. Apple 公式参考リンク
- アプリの国/地域公開設定:
  - https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store
- IAP の国/地域公開設定:
  - https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-availability-for-in-app-purchases/
- サブスクの国/地域公開設定:
  - https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-availability-for-an-auto-renewable-subscription
- サブスク価格管理:
  - https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions
