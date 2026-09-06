# App Store release notes — v1.15.0

Drafted: 2026-09-06

Version: `1.15.0` / Build: `50`

各言語のテキストブロックを App Store Connect の「このバージョンの新機能」に貼り付けるための草案です。アーカイブ作成・アップロード・審査提出は行っていません。

## 文体と対象範囲

- [日本の App Store バージョン履歴](https://apps.apple.com/jp/app/id6755782099)を 2026-09-06 に確認。公開中の最新版は `1.14.1`。直近の履歴で使われている「新機能／改善」の区分と、機能名に短い説明を添える形式に合わせています。
- `v1.14.1` 以降の実装差分には今回の中サイズウィジェット改善に加え、英語・韓国語・中国語（簡体字／繁体字）のローカライズが含まれるため、文章にも含めています。
- シミュレーター専用デモデータと開発用設定は公開機能ではないため含めていません。
- 課金関連の準備コードは含まれていますが、現行の `MonetizationService` は `isBillingTemporarilyDisabled = true` です。料金プランの開始や新たな有料制限は、この草案では案内していません。

## ja

```text
【ver 1.15.0 新機能と改善】

【新機能】
・中サイズの予定ウィジェットに月間カレンダーを追加
　- 今日の予定・タスクと、今月のカレンダーを並べて確認できるようにしました
　- 今日の日付を丸で、予定のある日を点で表示します
　- 日付をタップすると、アプリでその日の予定を開けます
・多言語に対応
　- 日本語に加え、英語・韓国語・中国語（簡体字／繁体字）に対応しました

【改善】
・中サイズウィジェットの見やすさを改善
　- 横幅を活かしたレイアウトにし、土日の日付を色分けしました
　- 6週ある月も、月末まで見渡せるように表示を調整しました
```

## en

```text
[Version 1.15.0 — New Features and Improvements]

[New Features]
・Monthly calendar in the medium schedule widget
  - See today's events and tasks alongside a calendar of the current month
  - A circle highlights today, and dots mark days with events
  - Tap a date to open that day's schedule in the app
・More languages
  - Added English, Korean, Simplified Chinese, and Traditional Chinese alongside Japanese

[Improvements]
・A clearer medium widget layout
  - Made better use of the width and added distinct colors for weekend dates
  - Adjusted the layout to show the entire month, including months that span six weeks
```

## ko

```text
[버전 1.15.0 새로운 기능 및 개선]

[새로운 기능]
・중간 크기 일정 위젯에 월간 캘린더 추가
  - 오늘의 일정과 할 일을 이번 달 캘린더와 나란히 확인할 수 있습니다
  - 오늘 날짜는 원으로, 일정이 있는 날은 점으로 표시합니다
  - 날짜를 탭하면 앱에서 해당 날짜의 일정을 열 수 있습니다
・다국어 지원
  - 일본어에 더해 영어, 한국어, 중국어 간체 및 번체를 지원합니다

[개선]
・중간 크기 위젯의 가독성 개선
  - 가로 공간을 활용하도록 배치를 조정하고 주말 날짜를 색으로 구분했습니다
  - 6주에 걸치는 달도 월말까지 한눈에 볼 수 있도록 표시를 조정했습니다
```

## zh-Hans

```text
【版本 1.15.0 新功能与改进】

【新功能】
・中号日程小组件新增月历
  - 今天的日程和待办可与本月日历并排查看
  - 用圆圈突出显示今天，用圆点标记有日程的日期
  - 轻点日期，即可在应用中打开当天的日程
・支持更多语言
  - 在日语基础上，新增英语、韩语、简体中文和繁体中文

【改进】
・优化中号小组件的显示
  - 更充分地利用横向空间，并用颜色区分周末日期
  - 调整布局，跨六周的月份也能完整显示到月末
```

## zh-Hant

```text
【版本 1.15.0 新功能與改善】

【新功能】
・中型行程小工具新增月曆
  - 今天的行程與待辦事項可與本月月曆並排查看
  - 以圓圈標示今天，以圓點標記有行程的日期
  - 點一下日期，即可在 App 中開啟當天的行程
・支援更多語言
  - 在日文之外，新增英文、韓文、簡體中文與繁體中文

【改善】
・改善中型小工具的顯示
  - 更充分運用橫向空間，並以顏色區分週末日期
  - 調整版面，跨六週的月份也能完整顯示到月底
```
