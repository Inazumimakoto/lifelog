# コード重複の整理（2026-10-12）

アプリとウィジェットの手書きSwiftソースを横断して、同じ処理のコピーを共通化した。開始時点の未コミット変更と、先行する性能改善を維持している。

## 共通化した処理

| 領域 | 共通の実装 | 維持した違い・条件 |
| --- | --- | --- |
| カレンダーと壁紙の複数日予定 | `CalendarPreviewLayout`、共通の週・日・予定段モデル | 終了日時の排他扱い、レーン再利用、隠れた件数、安定ID、各画面の色・プライバシー表示 |
| 外部予定の同期 | `ExternalCalendarSyncPolicy`、`ExternalCalendarEventMapper` | 過去6か月・未来18か月、同日抑制、範囲端の先読み、強制同期、非表示カテゴリと未設定カテゴリの違い |
| タスクの表示 | `TaskPresentation`、`TaskPresentationSource` | 開始日優先／期限優先、優先度・日付・タイトルの順、日付なし、アプリとSwiftDataを使うウィジェット |
| 今日のタイムライン | `TimelineHourBounds` | 2時間の余白、最小12時間、夜をまたぐ睡眠、端の補正。描画で一度計算して共有 |
| 習慣の保存 | 共通の完了記録保存・作成日の繰り上げ | トグルと明示設定の違い、最初の記録ID、連続日数・触覚フィードバック |
| タスク削除 | 共通のID指定永続化 | 画面のインデックス指定とID指定のメモリ更新、通知のキャンセル・再予約 |
| 習慣スケジュール | `HabitSchedule`の保存表現、`displayDescription` | カスタム曜日の順序・重複、未知の保存形式に対するアプリとウィジェットの既存の異なる扱い |
| 通知 | `NotificationService`の要求作成・日時指定処理 | 識別子・本文・サウンド、未来日時の判定、年次通知、キャンセル順、手紙IDのメタデータ |
| 日記・場所の写真取り込み | `DiaryPhotoImporter`と日付指定の追加処理 | 日記の枚数制限と写真再利用、場所写真の独立した原本保存、読み込み／保存失敗の別集計 |
| 写真の保存・照合 | `PhotoIdentityIndex`、共通の作業キュー、キャッシュ挿入、原子的ファイル書き込み | アセットID・見た目・バイト列の優先順、原本とサムネイルの上限・検証、ファイル保護 |
| 日記の訪問タグ | `DiaryVisitTagNormalizer` | 最初の表記、大小文字・ダイアクリティカルマークの比較規則、8件上限、ユーザー作成の名称 |
| 写真ビューアー | `FullscreenPhotoGallery`、`LetterPhotoCarousel`、`DismissiblePhotoViewer` | 欠損写真のページ、件数・色、日記の削除・お気に入り、ページID、ズーム中の動き、ドラッグのしきい値とアニメーション |
| 手紙の写真・日付 | `LetterPhotoFiles`と既存のキャッシュ済み日付書式 | 古い絶対パスと新しい相対パス、既存のローカライズ書式 |
| サインインと招待 | `LetterSignInContent`と招待の事前確認・リクエスト変換 | 同意保存キー、Apple nonce、招待後のプロフィール設定、送信経路ごとの確認条件 |
| 入力と色 | `DetailMemoEditor`、`AppColorPalette`、`HabitContributionPalette` | 入力中のドラフト、既存の文言と見た目、明暗色、ウィジェットとの一致 |

## 調査範囲と残した構造

Views、ViewModels、Models、Services、Components、およびLifelogWidgetsを調査した。空行とコメントを除いた連続行の重複検索に加え、似た処理の引数・副作用・日付境界を開始時点のソースと比較した。

残っている類似コードは、SwiftDataモデルとドメインモデルの別々の初期化、画面ごとに異なる予定行の表示、異なる配信条件を扱う手紙編集フォームなど。画面固有のライフサイクルや権限・削除・クラウド同期の判定は各呼び出し元に残している。開発APIとFirebase Functionsの手書きソースも重複検索を行った。生成された型定義・コンパイル済み出力は編集対象にしていない。

今回の整理では保存スキーマ・権限・エンタイトルメント・表示文言を追加変更していない。`Localizable.xcstrings`は整理開始時点と一致している。

整理開始時点のスナップショットとの差分では、実装側のSwiftソース58ファイルを変更し、追加1,436行・削除2,219行、差し引き783行減となった。コメントと空行を含む。別途、テスト12ファイルに791行を追加した。

## 検証

共通化の境界を確認するXCTestを48件追加した。対象はカレンダーのDST・重なり・省略件数、同期範囲・カテゴリ変換、タスクとウィジェットの並び順、通知の時刻・キャンセル順・メタデータ、写真の制限・再利用・失敗、タグと習慣の保存形式、永続化、タイムラインの余白。

初回の全体テストでは通知サービス破棄時にSwift 6.2のMainActorバックデプロイ処理でクラッシュした。クラッシュログの`swift_task_deinitOnExecutorMainActorBackDeploy`と`NotificationService.__deallocating_deinit`を確認し、アクターに依存する後処理を持たないサービスへ既存コードと同じ`nonisolated deinit {}`を適用した。参照: [Swiftの既知の問題](https://github.com/swiftlang/swift/issues/88036)。

修正後、iPhone 17 Pro / iOS 26.1の署名付きシミュレーターテストは全310件成功（失敗0、スキップ0、78.5秒）。既存の性能・Keychain・暗号化・写真・クラウド同期テストも含む。実機向けReleaseビルドも成功し、共通モデルを参照するウィジェットを含めてコンパイルを確認した。

シミュレーターのデモ専用ストアで、タスクの詳細メモへの入力とキャンセル、ホームからカレンダーへの切り替え、翌月／今日への移動、月／週の切り替えとタイムラインのスクロールを確認した。写真ビューアーのページング・ドラッグ・ズームの境界は開始時点の実装との比較と既存のズームテストで検証し、今回の手動確認では写真付きデータを使った一連の操作までは行っていない。

`git diff --check`は成功。アプリとウィジェットのローカライズカタログはいずれも整理開始時点とバイト単位で一致する。

検証コマンド:

```sh
xcodebuild test -project lifelog.xcodeproj -scheme lifelog -destination 'platform=iOS Simulator,id=D1D5F84C-C30A-4BD4-B26F-E1E872FB1AF8' -parallel-testing-enabled NO
xcodebuild -project lifelog.xcodeproj -scheme lifelog -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
git diff --check
```
