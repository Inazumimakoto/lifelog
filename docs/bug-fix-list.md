# `Task` 型名衝突（Swift Concurrency）バグ

## 問題

このアプリにはドメインモデルの `Task` が存在するため、`Task { ... }` と書くと Swift Concurrency の `Task` と衝突し、`Task` 初期化エラーや型解決エラーが断続的に発生する。

## 原因

`Task` という同名シンボルが2種類ある。

- アプリ独自モデル: `Models.Task`
- 非同期処理: `Swift Concurrency Task`

文脈によってコンパイラが誤ってモデル側を解決してしまう。

## 恒久対策

非同期タスクの生成・待機は **常に完全修飾** する。

```swift
// ✅ 常にこちらを使う
_Concurrency.Task {
    try? await _Concurrency.Task.sleep(for: .milliseconds(300))
}

// ❌ 禁止（衝突することがある）
Task {
    ...
}
```

## 運用ルール

- `AGENTS.md` に同ルールを明記済み。
- 新規実装・修正時は `Task {` を使わず `_Concurrency.Task {` を使う。
- 既存コードで衝突エラーが出た箇所は優先的に `_Concurrency.Task` に置換する。

---

# fullScreenCover と Optional State の同時設定バグ

## 問題

SwiftUIで `fullScreenCover(isPresented:)` を使用する際、表示するコンテンツが Optional な State 変数に依存している場合、**画面が真っ暗または背景のみ表示される**問題が発生する。

## 原因

以下のようなコードで問題が起きる：

```swift
// ❌ 問題のあるパターン
Button(action: {
    selectedLetter = letter       // ① State変数を設定
    showingLetterDetail = true    // ② 即座にfullScreenCoverを表示
}) {
    Text("開封")
}

.fullScreenCover(isPresented: $showingLetterDetail) {
    if let letter = selectedLetter {  // ③ この時点でselectedLetterがまだnilの可能性
        LetterOpeningView(letter: letter)
    }
}
```

SwiftUIの State 更新は非同期で行われるため、`showingLetterDetail = true` が実行された時点で `selectedLetter` がまだ `nil` のままになっている可能性がある。

その結果、`if let` の条件が満たされず、何も表示されない（または `else` のフォールバックが表示される）。

## 解決策

**`.onChange(of:)` を使用して、State変数が確実に設定されてから表示フラグを変更する。**

```swift
// ✅ 正しいパターン
Button(action: {
    selectedLetter = letter       // ① State変数を設定するだけ
}) {
    Text("開封")
}

// List や VStack の後に追加
.onChange(of: selectedLetter) { _, newLetter in
    if newLetter != nil {
        showingLetterDetail = true  // ② selectedLetterが設定された後に表示
    }
}

.fullScreenCover(isPresented: $showingLetterDetail, onDismiss: {
    selectedLetter = nil  // ③ 閉じる時にリセット
}) {
    Group {
        if let letter = selectedLetter {
            LetterOpeningView(letter: letter)
        } else {
            // フォールバック（通常は表示されない）
            Color(uiColor: UIColor(red: 0.1, green: 0.1, blue: 0.18, alpha: 1))
                .ignoresSafeArea()
        }
    }
}
```

## ポイント

1. **ボタンタップ時は State 変数の設定のみ**行う
2. **`.onChange(of:)` で State 変数の変更を監視**し、設定されてから表示フラグを `true` にする
3. `fullScreenCover` の中は **`Group` でラップ**し、`else` でフォールバックを用意する
4. `onDismiss` で **State 変数を `nil` にリセット**する

## 影響を受けた機能

- **未来への手紙** (`TodayView` → `LetterOpeningView`)
- **大切な人への手紙** (`ReceivedLettersView` → `SharedLetterOpeningView`)

## 参考

この問題は SwiftUI の State 更新タイミングに関連する一般的な問題であり、`sheet` や `fullScreenCover` で Optional なデータを表示する際には常にこのパターンを使用することを推奨する。

---

# 睡眠データ書き出し時に就寝/起床時刻が 0:00 になるバグ

## 問題

AI分析用データ書き出し機能で、睡眠データの就寝時刻・起床時刻が「0:00」と表示される問題。

特に：
- **日付を跨ぐ前に寝た場合**（例：23:00就寝）→ 就寝時刻が 0:00 になる
- **起床時刻が 0:00 になる**ケースもある

## 原因

`HealthKitManager.swift` の `fetchSleepData` 関数で、睡眠データを**日付の境界で分割**していた。

```swift
// ❌ 問題のあるコード
let dayStart = calendar.startOfDay(for: segmentStart)
let clippedStart = max(segmentStart, dayStart)  // 日付境界で切られる

var aggregate = sleepDataByDay[dayStart] ?? SleepAggregate(
    start: clippedStart,  // ← 0:00 になってしまう
    ...
)
aggregate.start = min(aggregate.start, clippedStart)  // clippedStartを使用
```

例：23:00に就寝 → 翌7:00に起床の場合
- 睡眠データは「起床日」に紐づけられる
- しかし `clippedStart = max(23:00, 0:00)` で**日付境界の0:00**が使われてしまう

## 解決策

**起床日を基準に集計**しつつ、**実際の就寝時刻を保持**するように修正。

```swift
// ✅ 修正後のコード
let sampleStart = sample.startDate
let sampleEnd = sample.endDate

// 起床日（endDateの日付）を基準にする
let wakeUpDay = calendar.startOfDay(for: sampleEnd)

var aggregate = sleepDataByDay[wakeUpDay] ?? SleepAggregate(
    start: sampleStart,  // 実際の就寝時刻を保持（日付を跨いでも）
    end: sampleEnd,
    ...
)

// 就寝時刻は最も早い時刻を保持（日付を跨いでも）
aggregate.start = min(aggregate.start, sampleStart)
// 起床時刻は最も遅い時刻を保持
aggregate.end = max(aggregate.end, sampleEnd)
```

### 追加修正（2026-01-05 2回目）

上記の修正後も、異なる夜の睡眠データが混ざる問題が発生。

**原因:** ループで日付境界ごとにセグメントを処理していたため、翌日の睡眠の「日付境界前の部分」が誤って処理されていた。

**追加修正:**
- ループを削除し、各サンプルを1回だけ処理
- 睡眠セッションの連続性をチェック（2時間以内のギャップ = 同一セッション）
- 別のセッション（昼寝など）は既存データを維持

```swift
// ✅ 最終修正版
let hours = sampleEnd.timeIntervalSince(sampleStart) / 3600

if var existing = sleepDataByDay[wakeUpDay] {
    // 同じ睡眠セッションかチェック（2時間以内のギャップ）
    let gap = abs(existing.end.timeIntervalSince(sampleStart))
    let isSameSession = gap < 7200
    
    if isSameSession {
        existing.start = min(existing.start, sampleStart)
        existing.end = max(existing.end, sampleEnd)
        existing.duration += hours
    }
} else {
    // 新規作成
    sleepDataByDay[wakeUpDay] = SleepAggregate(start: sampleStart, end: sampleEnd, duration: hours, ...)
}
```

## 修正後の動作

| ケース | 修正前 | 修正後 |
|--------|--------|--------|
| 23:00就寝 → 翌7:00起床 | 就寝: 0:00 | 就寝: 23:00 |
| 0:30就寝 → 7:00起床 | 就寝: 0:30 | 就寝: 0:30 |
| 翌日の睡眠との混合 | 起床時刻が誤表示 | 正しく分離 |

## 影響を受けた機能

- **AI分析用データ書き出し** (`AnalysisExportView` → `PromptGenerator`)
- **Today画面の睡眠表示**
- **カレンダー詳細の睡眠表示**

## 修正日

2026-01-05（2回修正）

---

# 日記入力時のパフォーマンス低下

## 問題

日記を書く際にキー入力が重い・ラグがある。

## 原因

**毎キーストロークで重い保存処理が実行されていた：**

```swift
func update(text: String) {
    entry.text = text
    persist()  // ← 毎回実行される
}

private func persist() {
    store.upsert(entry: entry)  // UserDefaults + SwiftData 書き込み
}
```

1文字入力するたびに：
1. 全日記をJSONエンコード
2. UserDefaultsに書き込み
3. SwiftDataでフェッチ → 更新 → 保存

## 解決策

**デバウンス（遅延保存）を追加**

```swift
// テキスト入力時は遅延保存
func update(text: String) {
    entry.text = text  // UIは即座に更新
    debouncedPersistText()  // 保存は0.5秒後
}

private func debouncedPersistText() {
    textPersistTask?.cancel()  // 既存のタスクをキャンセル
    textPersistTask = _Concurrency.Task {
        try await _Concurrency.Task.sleep(for: .milliseconds(500))
        persist()  // 0.5秒後に保存
    }
}
```

- **入力表示は遅れない**（UIは即座に更新）
- **保存は最後の入力から0.5秒後**にまとめて実行
- **画面を閉じる時**は `flushPendingTextSave()` で即座に保存

## 影響を受けた機能

- **日記編集画面** (`DiaryEditorView` → `DiaryViewModel`)

## 修正日

2026-01-05

---

# DevPCシートが表示されない（または一瞬で閉じる）バグ

## 問題

「開発者のPCに聞く」ボタンを押しても、シートが一瞬表示されてすぐ消える、または全く表示されない。

## 原因

`sheet(isPresented:)` のトリガーとなる State 変数と、そのシート内で使用するデータのための State 変数を同時に更新していた。

```swift
// ❌ 問題のあるコード
func askDevPC() {
    devPCPrompt = generatedText  // ① データを設定
    showDevPCSheet = true        // ② 表示フラグをON
}

// ...

.sheet(isPresented: $showDevPCSheet) {
    DevPCResponseView(prompt: devPCPrompt)
}
```

SwiftUIのState更新は非同期であり、`showDevPCSheet = true` が処理される時点で、`devPCPrompt` の更新がまだ反映されていない（または空として扱われる）場合があった。
特に `DevPCResponseView` 側で `prompt` が空の場合の挙動や、Viewの再描画タイミングと重なってシートが正しく維持されなかった。

## 解決策

**`.onChange(of:)` を使用して、データが確実に設定されてから表示フラグをONにするパターン（fullScreenCoverのバグと同様）を適用。**

```swift
// ✅ 修正後のコード
func askDevPC() {
    devPCPrompt = generatedText
    // showDevPCSheet = true はここでは設定しない！
}

// ...

.sheet(isPresented: $showDevPCSheet, onDismiss: {
    devPCPrompt = ""  // 閉じる時にリセット
}) {
    Group {
        if !devPCPrompt.isEmpty {
            DevPCResponseView(prompt: devPCPrompt)
        } else {
            Color.clear // フォールバック
        }
    }
}
.onChange(of: devPCPrompt) { _, newValue in
    if !newValue.isEmpty {
        showDevPCSheet = true  // データ設定を検知して表示
    }
}
```

## 影響を受けた機能

- **日記編集画面** (`DiaryEditorView` → `DevPCResponseView`)
- **分析データ書き出し画面** (`AnalysisExportView` → `DevPCResponseView`)

## 修正日

2026-01-14
