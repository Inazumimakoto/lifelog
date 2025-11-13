# 統合ライフログアプリ要件定義書

最終更新: 2025-11-13  
作成者: Codex (ユーザー要望をもとに作成)

---

## 1. アプリ概要

バレットジャーナル (Bullet Journal) の思想をベースに、予定・タスク・日記・習慣・ヘルスデータなど日々の記録を 1 つの iOS アプリで統合管理する。参考イメージは COMO Bujo。  
主要タブ: Today / Journal / Habits & Countdown / Health。

## 2. ターゲットユーザー
- iPhone ユーザー (iOS 17 以上を推奨)
- 日記・タスク管理・ヘルスケア・生活管理を 1 アプリで完結したい人
- バレットジャーナルやメンタル/感情トラッキングを好むユーザー

## 3. 利用シナリオ
- 朝: 今日の予定/習慣/体調指標を確認
- 夜: 日記を書き、写真・気分・体調・位置情報を残す
- ヘルスケア (睡眠・歩数・Apple フィットネス) データは自動取得
- 記念日カウントダウンを随時確認
- 習慣や目標進捗をタイムライン・グラフで可視化

## 4. 機能要件

### 4.1 Today (ホーム)
- 日付表示
- カレンダー予定 (EventKit 読み取り) を文字 + タイムライン表示で可視化
- 今日が期限の ToDo、今日対象の習慣
- ヘルスサマリ (歩数 / 睡眠 / エネルギー)
- 前日の睡眠時間、今日の歩数、歩数/睡眠タイムラインの関係グラフ
- 日記の記入状況とショートカット
- 予定カードをタップで編集、ダブルタップ手順の案内
- 「今日」という見出しは表示しない

### 4.2 カレンダー
- 月表示 (標準 or カスタム)・日付タップで詳細へ
- EventKit で予定を読み取り (タイトル / 時間 / カレンダー名)
- アプリ内から予定作成・編集を可能にする (カレンダー名の代わりにカテゴリ表記)
- Today / Journal どちらからでも予定追加・編集できる

### 4.3 ToDo
- CRUD + 完了チェック
- タイトル必須、詳細/期限/優先度(低~高) 任意
- DB 永続化 (現状: AppDataStore を模擬、将来: Core Data/Realm)
- Today では今日締切のみ、その他の日付タスクはタスクリストから追加する導線説明

### 4.4 日記 (Diary)
- 1 日に 1 件 or 複数エントリ
- 入力: テキスト (初期値は空)、写真(最大 50 枚、PhotosPicker から取得し Documents 保存)、気分スコア(1~5)、体調(5段階・絵文字)、位置情報 (MapKit 検索 + 訪れた場所説明文)
- 体調/気分/睡眠/歩数の相関を Health 画面にグラフとして表示

### 4.5 ジャーナル (Bujo)
- 週 / 月切替 (週は週次カレンダー + タイムライン、月は従来表示)
- 週タイムライン: 時間軸整列、重なり解消、下部に日詳細 (月表示と同じ内容)
- 週移動は 7 日単位、月ヘッダーは数字表記 (例: 2025年11月)
- 今日以外の日選択時のみ「今日へ」ボタン表示
- 日付ダブルタップで予定/タスク追加できる旨を明示
- 予定/タスクをジャーナル上からも追加・編集可能
- 他日へ移動後に戻るボタン

### 4.6 習慣 (Habit Tracker)
- 登録: タイトル / アイコン (SF Symbols を候補グリッド表示) / カラー (パレット) / 繰り返し設定 (毎日・平日・カスタム)
- HabitRecord: 日付・習慣 ID・完了フラグ
- UI: 週間グリッド (横:日付 × 縦:習慣)・Today に本日分を表示
- 既存習慣の編集導線・説明

### 4.7 記念日 (Anniversary / Countdown)
- 登録: タイトル / 日付 / 種別 (countdown/since) / 毎年繰り返し
- 表示: D-xxx / D-0 / +xxx

### 4.8 ヘルスケア
- データ: 歩数 / 睡眠 / Apple フィットネス (ムーブ・エクササイズ・スタンド) / 活動量
- 動作: 初回権限取得 → 許可済みのみ読み込み。Today: 当日データ、Health タブ: 週・月・半年・年グラフ
- 歩数グラフ (棒、値ラベル付)・睡眠タイムライン (途切れない棒 + 時間表示)・相関チャート
- 履歴ビュー: 範囲 (週/1か月/6か月/1年) 切替 + 横スワイプ

## 5. データモデル

| エンティティ | 主なフィールド |
| --- | --- |
| Task | id(UUID), title, detail, dueDate, priority(Int 1~3), isCompleted |
| DiaryEntry | id, date, text, mood(Int 1~5), conditionScore, photoPaths([String]), locationName, latitude, longitude |
| Habit | id, title, iconName, colorHex, schedule(HabitSchedule) |
| HabitRecord | id, habitID, date, isCompleted |
| Anniversary | id, title, targetDate, type(countdown/since), repeatsYearly |
| HealthSummary | date, steps, sleepHours, sleepStart/End, activeEnergy, fitnessリング相当値 |
| CalendarEvent | id, title, startDate, endDate, calendarName/カテゴリ |

## 6. 非機能要件
- iOS 17+ 推奨 (SwiftUI 最新機能)
- 永続化: Core Data + CloudKit を視野／暫定的に AppDataStore (インメモリ)
- パフォーマンス: Today 画面 1 秒以内ロード。HealthKit フェッチはバックグラウンドで UI ブロック禁止
- セキュリティ: ローカル保存、個人データを外部送信しない、写真はアプリ専用フォルダ
- プライバシー: HealthKit / Photos アクセス文言整備 (選択写真推奨)

## 7. 画面遷移

```
TabView
 ├─ Today (ホーム)
 │    ├─ 日記編集
 │    ├─ タスク編集 (TasksView)
 │    └─ 予定編集 (CalendarEventEditorView)
 ├─ Journal
 │    ├─ 日付詳細
 │    ├─ タスク/予定編集
 │    └─ 戻る(今日へ)ボタン
 ├─ Habits & Countdown
 │    ├─ 習慣編集
 │    └─ 記念日編集
 └─ Health
      └─ 履歴/詳細グラフ
```

## 8. 開発ロードマップ (初期案)
1. プロジェクト構成 (SwiftUI + MVVM)
2. TabView + 空画面
3. 日記 (テキスト + 位置 + 写真添付)
4. ToDo 管理
5. 習慣トラッカー
6. 記念日
7. カレンダー (EventKit 読み込み + 追加/編集 UI)
8. HealthKit + Apple フィットネス
9. Today 統合 + タイムライン
10. UI 仕上げ (COMO Bujo 風)

## 9. 追加検討事項
- 感情トラッキング統計 / ヒートマップ
- カスタムテーマ
- 月次 PDF エクスポート
- ホーム/ロック画面ウィジェット
- Apple Watch 連携 (習慣チェック)

## 10. 実装メモ & 参照
- 実装は SwiftUI + MVVM。`AppDataStore` で状態共有、各画面 ViewModel でロジック分離。
- Today/Journal のタイムライン仕様: `ViewModels/TodayViewModel.swift`, `ViewModels/JournalViewModel.swift`。
- ヘルス系グラフ: `Views/Health/*`。
- 本ドキュメントは `/docs/requirements.md`。必要に応じて README、コードコメントから参照すること。
