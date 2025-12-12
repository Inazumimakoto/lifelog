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
