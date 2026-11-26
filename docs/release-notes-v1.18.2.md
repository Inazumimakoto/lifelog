# lifelify 1.18.2 アップデート文

- 作成日　2026-11-26
- 対象　1.18.2（ビルド56）
- 比較タグ　`v1.18.0`（`fdbf23a`）
- 文体の参考　App Store Connect上の直近バージョン（1.18.0）および保存済みのリリースノート草案（[docs/release-notes-v1.18.0.md](release-notes-v1.18.0.md)・[docs/release-notes-v1.18.1.md](release-notes-v1.18.1.md)）。日本のApp Store Webページ本文は自動取得できなかったため、上記を参照しています。

## ja

```text
【ver 1.18.2 新機能と改善】

【新機能】
・以前の記録の復元
　- 端末に以前の記録のコピーが残っている場合、設定の「ストレージ」→「以前の記録を復元」から、読み出せた件数を確認して復元できるようになりました。復元後も、現在の記録は保持されます。

【改善】
・ロック画面カレンダー
　- 日付が変わったあとに予定やタスクを変更していなくても、ショートカットの実行時に当日の色塗りがその日の日付へ更新されるように修正しました。設定画面のプレビューも日付の切り替わりに合わせて更新されます。
　- ロック画面カレンダーの設定ガイドを分かりやすく見直し、大きな文字設定でも案内画面が読みやすくなるよう調整しました。
・起動時の動作とデータ読み込み
　- 保存データを一時的に開けないときに、以前の記録が表示されなくなる問題を修正しました。元の記録を保ったまま、読み込みを再試行できるようになりました。
　- 起動時の写真チェックやホーム画面の読み込み処理を見直し、起動演出が滑らかに進むように改善しました。
・権限の設定
　- 初回案内や通知・カレンダー・ヘルスケア・位置情報の設定を見直し、必要な画面から分かりやすく許可や設定を行えるようにしました。
```

## en

```text
[Version 1.18.2 — New Features and Improvements]

[New Features]
• Recover previous records
  - If a copy of your previous records is still on your device, open “Recover previous records” under Storage in the app’s settings. You can check how many records were found and recover them while keeping your current records.

[Improvements]
• Lock Screen calendar
  - Fixed an issue where today’s highlight could stay on an earlier day after midnight when no events or tasks were edited. Running the shortcut now moves the highlight to the current day, and the settings preview updates when the date changes.
  - Clarified the Lock Screen calendar setup guide and improved the announcement layout for larger text sizes.
• App launch and data loading
  - Fixed an issue that could cause previous records to disappear from view when the app temporarily could not open its saved data. You can now retry while keeping your original records.
  - Refined photo sync checks and Home screen loading at launch so the startup transition runs more smoothly.
• Permissions setup
  - Refined the first-run guide and in-context prompts for notifications, Calendar, Health, and Location so you can review and adjust access right where each feature is used.
```

## ko

```text
【버전 1.18.2 새 기능 및 개선 사항】

【새 기능】
・이전 기록 복구
　- 기기에 이전 기록의 복사본이 남아 있다면 설정의 ‘스토리지’에서 ‘이전 기록 복구’를 열어 찾은 기록의 개수를 확인하고 복구할 수 있습니다. 복구 후에도 현재 기록은 그대로 유지됩니다.

【개선 사항】
・잠금 화면 캘린더
　- 날짜가 바뀐 뒤 일정이나 할 일을 수정하지 않아도 단축어를 실행하면 오늘 날짜 강조 표시가 당일로 갱신되도록 수정했습니다. 설정 화면의 미리보기도 날짜 변경에 맞춰 함께 갱신됩니다.
　- 잠금 화면 캘린더 설정 가이드를 더 알기 쉽게 다듬고, 큰 글자 크기 설정에서도 안내 화면을 읽기 쉽게 조정했습니다.
・앱 실행 및 데이터 불러오기
　- 앱을 시작할 때 저장된 데이터를 일시적으로 열 수 없으면 이전 기록이 보이지 않던 문제를 수정했습니다. 이제 원래 기록을 유지한 채 다시 불러올 수 있습니다.
　- 실행 시 사진 확인과 홈 화면 불러오기 처리를 개선해 시작 화면 전환이 더 부드럽게 이어지도록 했습니다.
・권한 설정
　- 처음 실행 안내와 알림·캘린더·건강·위치 권한 설정을 정비해, 각 기능이 필요한 화면에서 알기 쉽게 허용하고 설정할 수 있도록 개선했습니다.
```

## zh-Hans

```text
【1.18.2 版新功能与改进】

【新功能】
・恢复以前的记录
　- 如果设备上仍保留着以前的记录副本，可在应用设置的“贮存”中打开“恢复以前的记录”，查看能读取的记录数量并进行恢复。恢复后也会保留现有记录。

【改进】
・锁定屏幕日历
　- 修复了跨天后若未修改日程或任务，运行快捷指令时当天高亮不会更新到当天日期的问题。设置页的预览也会随日期变化同步更新。
　- 优化了锁定屏幕日历的设置指南，并调整了提示弹窗在较大字体设置下的显示效果，使其更易阅读。
・应用启动与数据读取
　- 修复了应用启动时因暂时无法打开已保存的数据而不显示以前记录的问题。现在可以保留原有记录并重新尝试读取。
　- 优化了启动时的照片同步检查与首页加载流程，使启动过渡更流畅。
・权限设置
　- 优化了首次引导以及通知、日历、健康和定位权限的设置方式，方便在对应功能页面中清晰地完成授权与调整。
```

## zh-Hant

```text
【1.18.2 版新功能與改進】

【新功能】
・復原先前的記錄
　- 如果裝置上仍保留著先前的記錄副本，可在 App 設定的「貯存」中開啟「復原先前的記錄」，查看可讀取的記錄筆數並進行復原。復原後也會保留現有記錄。

【改進】
・鎖定畫面行事曆
　- 修正了換日後若未修改行程或任務，執行捷徑時當日標示不會更新到當天日期的問題。設定頁的預覽也會隨日期切換同步更新。
　- 優化了鎖定畫面行事曆的設定指南，並調整了提示畫面在較大字體設定下的版面，讓內容更容易閱讀。
・App 啟動與資料讀取
　- 修正了 App 啟動時因暫時無法開啟儲存的資料而無法顯示先前記錄的問題。現在可以保留原有記錄並重新嘗試讀取。
　- 優化了啟動時的照片同步檢查與首頁載入流程，讓啟動過場更流暢。
・權限設定
　- 優化了初次引導以及通知、行事曆、健康與定位權限的設定方式，方便在對應功能畫面中清楚完成授權與調整。
```
