# lifelify 1.18.3 アップデート文

- 作成日　2026-11-28
- 対象　1.18.3（ビルド62）
- 比較タグ　`v1.18.2`（`45854c8`）
- 文体の参考　日本の App Store バージョン履歴（[lifelify](https://apps.apple.com/jp/app/lifelify/id6755782099)）および保存済みのリリースノート草案（[docs/release-notes-v1.18.2.md](release-notes-v1.18.2.md)）。

## ja

```text
【ver 1.18.3 改善】

【改善】
・アプリ起動の高速化と起動画面の見直し
　- 起動時はホーム画面の表示に必要な直近の記録から優先して読み込み、過去の履歴や買い物リスト、ヘルスケア・外部カレンダー同期はホーム表示後に分けて読み込むように改善しました。
　- アプリ独自の起動ロゴアニメーションを廃止し、起動画面からホーム画面（アプリロック有効時はロック解除画面）へ直接切り替わるようにしました。起動から操作できるようになるまでの待ち時間を大幅に短縮しています。
　- 起動時のテーマ適用処理を見直し、初回の不要な再描画を抑えることで表示をより滑らかにしました。
```

## en

```text
[Version 1.18.3 — Improvements]

[Improvements]
• Faster app launch and streamlined startup transition
  - At launch, lifelify now loads the recent records needed for Home first, while loading older history, the shopping list, and Health / external calendar refreshes after Home appears.
  - Removed the in-app launch logo animation so the app transitions directly from the system launch screen into Home (or the lock screen when App Lock is enabled), significantly reducing the time until you can interact.
  - Refined initial theme application at launch to avoid redundant first-frame redraws for a smoother startup.
```

## ko

```text
【버전 1.18.3 개선 사항】

【개선 사항】
・앱 실행 속도 개선 및 시작 화면 간소화
　- 앱을 실행할 때 홈 화면에 필요한 최근 기록을 먼저 불러오고, 과거 기록과 장보기 목록, 건강 및 외부 캘린더 동기화는 홈 화면이 표시된 뒤 나누어 불러오도록 개선했습니다.
　- 앱 자체 시작 로고 애니메이션을 없애고 시스템 시작 화면에서 홈 화면(앱 잠금 사용 시 잠금 해제 화면)으로 바로 전환되도록 변경해 실행 후 조작하기까지의 대기 시간을 크게 줄였습니다.
　- 실행 시 테마 적용 처리를 개선해 첫 화면의 불필요한 다시 그리기를 줄였습니다.
```

## zh-Hans

```text
【1.18.3 版改进】

【改进】
・加快应用启动速度并精简启动过渡
　- 启动时会优先读取首页所需的近期记录，历史记录、购物清单以及健康和外部日历同步将在首页显示后分步加载。
　- 移除了应用内的启动标志动画，从系统启动页直接进入首页（开启应用锁时直接进入解锁界面），大幅缩短启动后可操作前的等待时间。
　- 优化了启动时的主题应用流程，减少首次渲染时的多余重绘，让画面显示更顺畅。
```

## zh-Hant

```text
【1.18.3 版改進】

【改進】
・加快 App 啟動速度並精簡啟動過場
　- 啟動時會優先讀取首頁所需的近期記錄，歷史記錄、購物清單以及健康與外部行事曆同步則會在首頁顯示後分步載入。
　- 移除了 App 內的啟動標誌動畫，從系統啟動畫面直接切換至首頁（開啟 App 鎖定時直接進入解鎖畫面），大幅縮短啟動後可操作前的等待時間。
　- 優化了啟動時的主題套用流程，減少首次繪製時的多餘重繪，讓畫面顯示更流暢。
```
