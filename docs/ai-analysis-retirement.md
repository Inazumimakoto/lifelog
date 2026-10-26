# 日記AI分析機能の撤去

更新日: 2026-10-12。次回リリース版に向けた変更で、公開済みのアプリやサーバーの停止はまだ行っていない。

## アプリ側の変更

- 日記のAI採点、期間AI分析、AI分析用データ書き出し、外部AIアプリの選択、開発者PCへの直接分析を撤去する。
- 通常の日記、健康記録、保存済み本文・写真などの利用を維持する。日記DBにAI結果の保存項目はないため、DB移行は行わない。旧AI使用回数のUserDefaultsだけを起動時に削除する。
- AI用の設定・文言・Firestoreカウンター参照を整理する。ローカルの `firestore.rules` からAI用統計ルールを外すが、本番へはまだデプロイしていない。
- Firebaseを使う手紙、日記写真のiCloud保存は別機能として維持する。買い物を含むChatGPT・Cloudflare連携は、その後の方針変更で撤去した（`docs/chatgpt-cloudflare-retirement.md`）。

## 未実施の運用作業

- 本番Firestoreに更新済みルールをデプロイし、AI用の `stats/llm_usage` ドキュメントを削除する。ローカルのルール変更だけでは本番のアクセス権やカウンターは変わらない。
- 開発者PCの推論サーバー、Cloudflare Tunnel、起動設定などの所在と稼働状態を確認し、停止する。これらの運用設定は本リポジトリ内には見つかっていない。推論サーバーのログや送信データの保存実態も未確認であり、削除済み・保存なしとは断定しない。
- 公開済みの旧版からは、撤去後も既存エンドポイントへのアクセスが続く可能性がある。旧版の利用状況を確認し、アプリの配布とサーバー停止の時期を決める。
- 更新した5言語のサポート／プライバシー説明を公開し、App StoreのPrivacy情報・審査メモを実際の配布版と運用状態に合わせて更新する。今回の作業はリポジトリ内の文書更新までで、公開先やApp Storeの更新は行っていない。

過去のCHANGELOGや不具合記録にあるAI機能への言及は、当時の履歴として保持する。

## 検証

- `xcodebuild -project lifelog.xcodeproj -scheme lifelog -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` 相当を新規DerivedDataで実行し、成功。
- XcodeBuildMCPの `test_sim` でDebug・iPhone 17 Pro（iOS 26.1）の署名付きXCTestを実行し、310件成功、失敗・スキップ0件。テストには `CODE_SIGNING_ALLOWED=NO` を指定していない。
- アプリ・WidgetのSwiftに撤去対象の型・画面・サービス参照が残っていないことを確認。ローカライズ133キーを除去し、残る翻訳内容は変更していない。
- Releaseアプリに `LLMConfig.plist` が含まれず、生成済み5言語の翻訳テーブルにも除去したキーが残っていないことを確認。
- シミュレータの独立したデモ用ストアで、TodayのAI書き出しボタンと日記編集のAIセクションが消えていることを確認。日記本文の追記・保存、Todayへの反映、アプリ再起動後の保持も確認。
- 起動後に旧UserDefaultsの `devpc_llm_usage` が存在しないことを確認。確認用のデモ本文の追記は元に戻し、通常モードへ復帰してアプリを停止した。
