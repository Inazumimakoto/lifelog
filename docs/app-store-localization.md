# App Store Localization & ASO Metadata

Updated: 2026-11-27

Target locales: `ja`, `en-US`, `ko`, `zh-Hans`, `zh-Hant`. Taiwan is handled as `zh-Hant`.

> ASO Design Notes:
> - App Name (max 30 chars) keeps high-volume core keywords alongside the brand name `lifelify`.
> - Subtitle (max 30 chars) targets high-value keywords omitted from the title (zero duplication with App Name).
> - Keywords field (max 100 chars) avoids duplicating words already present in App Name or Subtitle, and omits free-app noise (`無料`).
> - Cross-Locale Indexing: Japan indexes both `ja` and `en-US` metadata, so `ja` focuses purely on high-volume Japanese terms (`買い物リスト`, `壁紙`, `日記帳`, `習慣化`, `やること`, etc.) while `en-US` captures English/romaji queries (`shopping`, `widget`, `lock screen`, `wallpaper`, `planner`, `bujo`, `countdown`, etc.).
> - Promotional Text (max 170 chars) can be updated without an app release.

---

## ja

- **App name (30/30)**: `lifelify - 日記・予定・ToDo・習慣・健康・メモ`
- **Subtitle (27/30)**: `カレンダー・買い物リスト・ウィジェット・ロック画面壁紙`
- **Promotional text (90/170)**:
  `写真と気分が並ぶ振り返りカレンダー、ロック画面カレンダー壁紙、ホーム画面ウィジェット、習慣の草ヒートマップ、買い物リスト、未来への手紙まで。複数のアプリをこれ1つにまとめられます。`
- **Keywords (99/100)**:
  `手帳,スケジュール,タスク,カウントダウン,記念日,草,ヒートマップ,写真,地図,手紙,タイムカプセル,体調,睡眠,歩数,振り返り,ライフログ,日記帳,習慣化,やること,アルバム,バレットジャーナル`
- **Description**:

```text
lifelify は、日記・予定・タスク・習慣・買い物リスト・ヘルス記録・メモ・記念日カウントダウンを、1つのアプリにまとめられるオールインワンのライフログアプリです。

【振り返りカレンダー＆思い出マップ】
・日記に添えた写真と気分アイコンが月間カレンダーに並び、1ヶ月をアルバムのように振り返り
・行った場所をタグと写真つきで記録し、世界地図の上から振り返れる「思い出マップ」

【ホーム（Today）＆ウィジェット】
・天気、今日の予定・タスク、メモ、習慣チェック、ヘルスサマリー、日記を1画面に集約
・ホーム画面 / ロック画面ウィジェットで、アプリを開かなくても予定・習慣・メモ・カウントダウンを確認

【ロック画面カレンダー壁紙】
・今月の予定とタスクを iPhone のロック画面壁紙に自動生成
・お気に入りの写真を背景にして、時間を見るついでに1ヶ月の予定をチェック

【カレンダー＆タスク】
・月ビュー・週ビュー・タイムラインで、予定とタスクをわかりやすく整理
・iCloud カレンダーの予定を取り込み、lifelify 内の予定と一緒に表示
・色分けカテゴリで仕事・プライベート・旅行などをひと目で区別

【買い物リスト】
・スーパー、ドラッグストアなどお店ごとにタブ分けして買い忘れを防止
・メモ欄つきで容量や個数も一緒に整理

【習慣トラッカー＆カウントダウン】
・毎日 / 平日だけ / 曜日カスタムなど柔軟なスケジュール設定
・年間の「草」ヒートマップと連続達成日数（ストリーク）で継続を可視化
・旅行や試験、誕生日などのイベントまでの残り日数をカウントダウン

【ヘルスケア＆体調ログ】
・歩数・睡眠ステージ・消費カロリー・体調スコアをグラフで振り返り
・Apple ヘルスケアと連携して日々の調子の傾向を把握

【未来への手紙・共有レター】
・指定した未来の日に届く自分へのタイムカプセルレター
・エンドツーエンド暗号化で安心して送り合える共有レター

複雑な設定やアカウント登録は不要。保存済みの日記・カテゴリ名・タグ名などの記録はユーザーのデータとしてそのまま保持されます。
```

- **Support URL**: `https://inazumimakoto.github.io/lifelog-support/`
- **Privacy URL**: `https://inazumimakoto.github.io/lifelog-support/`

IAP:
- Monthly: `lifelify Premium 月額` / `プレミアム機能を1か月利用できます。`
- Yearly: `lifelify Premium 年額` / `プレミアム機能を1年間利用できます。`
- Lifetime: `lifelify Premium 買い切り` / `プレミアム機能を買い切りで利用できます。`

---

## en-US

- **App name (30/30)**: `lifelify - Diary, Habits, ToDo`
- **Subtitle (29/30)**: `Calendar, Journal, Health Log`
- **Promotional text (143/170)**:
  `Photo review calendar, lock screen calendar wallpaper, habit heatmap, widgets, shopping list, health trends, and future letters—all in one app.`
- **Keywords (99/100)**:
  `schedule,planner,memo,widget,lock screen,wallpaper,shopping,streak,heatmap,photo,map,countdown,bujo`
- **Description**:

```text
lifelify is an all-in-one life log that brings your photo diary, calendar, tasks, habits, shopping list, memos, health summaries, and countdowns together in one app.

Photo Review Calendar & Memory Map
- See your daily photos and mood icons arranged across a visual monthly calendar
- Save places with tags and photos, then explore everywhere you have been on the world Memory Map

Today Home & Widgets
- Check weather, schedules, tasks, memos, habit check-ins, health stats, and your diary on a single screen
- Stay organized from your Home Screen and Lock Screen with dedicated schedule, habit, memo, and countdown widgets

Lock Screen Calendar Wallpaper
- Automatically render your monthly schedule onto your iPhone Lock Screen wallpaper
- Pair your favorite background photo with color-coded events so your month is visible without opening the app

Calendar & Tasks
- View events and tasks in Month, Week, and Timeline layouts
- Sync external iCloud calendars alongside your lifelify schedule and organize everything with custom color categories

Shopping List by Store
- Group items by store (grocery, pharmacy, stationery) with notes for quantities and reminders

Habit Tracker & Countdowns
- Track daily, weekday, or custom schedules with a GitHub-style annual contribution heatmap
- Build momentum with streaks, completion rates, and countdowns to trips, exams, or birthdays

Health & Sleep Trends
- Review steps, sleep stages, active energy, and daily condition scores in clean charts powered by Apple Health

Letters to the Future & Shared Letters
- Seal time-capsule letters to your future self for any date
- Send end-to-end encrypted shared letters to friends or family

No account required to get started. Your saved diary text, category names, tags, and personal records are never translated or overwritten by the app.
```

- **Support URL**: `https://inazumimakoto.github.io/lifelog-support/`
- **Privacy URL**: `https://inazumimakoto.github.io/lifelog-support/`

IAP:
- Monthly: `lifelify Premium Monthly` / `Unlock premium features for one month.`
- Yearly: `lifelify Premium Yearly` / `Unlock premium features for one year.`
- Lifetime: `lifelify Premium Lifetime` / `Unlock premium features with a one-time purchase.`

---

## ko

- **App name (28/30)**: `lifelify - 일기・일정・할일・습관・건강・메모`
- **Subtitle (24/30)**: `캘린더・장보기 목록・위젯・잠금화면 달력 배경`
- **Promotional text (90/170)**:
  `사진 회고 캘린더, 잠금 화면 달력 배경, 습관 잔디 히트맵, 장보기 목록, 위젯, 건강 요약, 미래로의 편지까지. 여러 앱을 lifelify 하나로 정리하세요.`
- **Keywords (87/100)**:
  `다이어리,플래너,투두,체크리스트,라이프로그,잔디,히트맵,사진,지도,추억,기념일,카운트다운,수면,걸음수,편지,타임캡슐,불릿저널,쇼핑리스트,회고,루틴,기록,심플`
- **Description**:

```text
lifelify는 일기, 일정, 할 일, 습관, 장보기 목록, 메모, 건강 기록, 기념일 카운트다운을 한곳에 모으는 올인원 라이프로그 앱입니다.

사진 회고 캘린더 & 추억 지도
- 매일의 대표 사진과 기분 아이콘이 월간 캘린더에 한눈에 펼쳐집니다
- 방문한 장소를 사진·태그와 함께 기록하고 세계 지도 위에서 추억을 되돌아볼 수 있습니다

홈(Today) & 위젯
- 날씨, 오늘의 일정과 할 일, 메모, 습관 체크, 건강 요약, 일기를 한 화면에서 확인
- 홈 화면과 잠금 화면 위젯으로 앱을 열지 않고도 핵심 정보를 바로 확인

잠금 화면 캘린더 배경화면
- 한 달 일정이 담긴 달력을 iPhone 잠금 화면 배경으로 자동 생성
- 좋아하는 사진 위에 색상별 일정 캘린더를 올려 한눈에 일정을 파악

캘린더 & 할 일
- 월간, 주간, 타임라인 보기로 일정과 할 일을 체계적으로 정리
- iCloud 캘린더 연동 및 색상별 카테고리로 깔끔하게 구분

매장별 장보기 목록
- 마트, 드럭스토어 등 매장별로 탭을 나누어 필요한 물건과 메모를 깔끔하게 관리

습관 트래커 & 디데이 카운트다운
- 매일, 평일, 원하는 요일 설정과 연간 잔디 히트맵으로 꾸준함을 시각화
- 연속 달성 기록(스트릭)과 여행·시험·생일까지 남은 일수 관리

건강 요약 & 미래로의 편지
- 걸음 수, 수면 단계, 활동 에너지, 컨디션 추이를 그래프로 간편하게 확인
- 미래의 나에게 보내는 타임캡슐 편지와 종단간 암호화 공유 편지 지원

복잡한 가입 없이 바로 시작할 수 있으며, 저장된 본문·카테고리명·태그명 등 개인 기록은 앱이 번역하거나 덮어쓰지 않습니다.
```

- **Support URL**: `https://inazumimakoto.github.io/lifelog-support/`
- **Privacy URL**: `https://inazumimakoto.github.io/lifelog-support/`

IAP:
- Monthly: `lifelify Premium 월간` / `프리미엄 기능을 1개월 동안 사용할 수 있습니다.`
- Yearly: `lifelify Premium 연간` / `프리미엄 기능을 1년 동안 사용할 수 있습니다.`
- Lifetime: `lifelify Premium 평생` / `한 번의 구매로 프리미엄 기능을 사용할 수 있습니다.`

---

## zh-Hans

- **App name (25/30)**: `lifelify - 日记・日程・待办・习惯・健康`
- **Subtitle (23/30)**: `日历・购物清单・小组件・锁屏壁纸日历・照片地图`
- **Promotional text (59/170)**:
  `照片回顾日历、锁屏壁纸日历、主屏小组件、习惯打卡热力图、购物清单、健康睡眠趋势与写给未来的信，把多个常用应用合而为一。`
- **Keywords (92/100)**:
  `手账,计划,清单,备忘录,打卡,热力图,纪念日,倒数日,睡眠,步数,心情,回顾,时间胶囊,写信,生活记录,效率,极简,日程表,目标,买菜,超市,照片墙,回忆,健康管理,日记本,习惯养成`
- **Description**:

```text
lifelify 是一款将照片日记、日程、待办、习惯打卡、购物清单、备忘录、健康摘要与倒数日整合在一起的一站式生活记录应用。

照片回顾日历与回忆地图
- 每日精选照片与心情图标自动排布在月历视图中，整月回忆一目了然
- 为日记添加地点、标签与照片，在世界地图上重温去过的每一处地方

今日首页与桌面小组件
- 在同一页面轻松查看天气、今日日程、待办、备忘、习惯打卡、健康数据与日记
- 支持主屏幕与锁屏小组件，无需打开应用即可随时查看安排

锁屏壁纸日历
- 自动将整月日程渲染到 iPhone 锁屏壁纸上
- 搭配喜爱的背景照片与彩色分类标签，点亮屏幕即可掌握全月安排

日程日历与待办管理
- 支持月视图、周视图与时间轴视图，并可同步 iCloud 日历
- 自定义彩色分类，清晰区分工作、生活、旅行与学习安排

按店铺分组的购物清单
- 按超市、药妆店、文具店等分组管理购物项与备注，买东西不再遗漏

习惯追踪与倒数日
- 灵活设置每日、工作日或自定义周期，用年度打卡热力图直观呈现坚持成果
- 记录连续达成天数、完成率以及旅行、考试、生日的倒数日

健康趋势与写给未来的信
- 结合 Apple 健康展示步数、睡眠阶段与活动能量图表
- 支持写给未来自己的时间胶囊信件，以及端到端加密的亲友共享信件

无需繁琐注册即可开始使用。已保存的日记正文、分类名、标签名和个人数据均由你掌控，不会被应用翻译或覆盖。
```

- **Support URL**: `https://inazumimakoto.github.io/lifelog-support/`
- **Privacy URL**: `https://inazumimakoto.github.io/lifelog-support/`

IAP:
- Monthly: `lifelify Premium 月度` / `解锁 1 个月高级功能。`
- Yearly: `lifelify Premium 年度` / `解锁 1 年高级功能。`
- Lifetime: `lifelify Premium 终身` / `一次购买即可解锁高级功能。`

---

## zh-Hant

- **App name (25/30)**: `lifelify - 日記・行程・待辦・習慣・健康`
- **Subtitle (24/30)**: `行事曆・購物清單・小工具・鎖定畫面桌布日曆・地圖`
- **Promotional text (65/170)**:
  `照片回顧日曆、鎖定畫面桌布日曆、主畫面小工具、習慣打卡熱力圖、購物清單、健康睡眠趨勢與寫給未來的信，將多個常用 App 合而為一。`
- **Keywords (92/100)**:
  `手帳,計畫,清單,備忘錄,打卡,熱力圖,紀念日,倒數日,睡眠,步數,心情,回顧,時間膠囊,寫信,生活紀錄,效率,極簡,行程表,目標,買菜,超市,照片牆,回憶,健康管理,日記本,習慣養成`
- **Description**:

```text
lifelify 是一款結合照片日記、行程、待辦、習慣打卡、購物清單、備忘錄、健康摘要與倒數日的一站式生活紀錄 App。

照片回顧日曆與回憶地圖
- 每日精選照片與心情圖示自動排布在月曆中，整個月的回憶一目了然
- 為日記加上地點、標籤與照片，在世界地圖上重溫去過的每個地方

今日首頁與桌面小工具
- 在單一畫面快速掌握天氣、今日行程、待辦、備忘、習慣打卡、健康數據與日記
- 支援主畫面與鎖定畫面小工具，不必開啟 App 也能即時查看重點

鎖定畫面桌布日曆
- 自動將整月行程繪製到 iPhone 鎖定畫面桌布上
- 搭配喜歡的照片與彩色分類，點亮螢幕就能掌握整個月份的安排

行事曆與待辦管理
- 支援月檢視、週檢視與時間軸，並可同步 iCloud 行事曆
- 透過自訂彩色分類清楚區分工作、生活、旅行與學習

依店家分類的購物清單
- 依超市、藥妝店、文具雜貨等店家分組管理待買項目與備註，採買不遺漏

習慣追蹤與倒數日
- 彈性設定每日、平日或自訂週期，以年度打卡熱力圖呈現累積成果
- 追蹤連續達成天數、完成率與旅行、考試、生日的倒數計時

健康趨勢與寫給未來的信
- 整合 Apple 健康呈現步數、睡眠階段與活動能量圖表
- 支援寄給未來自己的時間膠囊信件，以及端對端加密的親友共享信件

無需繁瑣註冊即可立刻開始。已儲存的日記內容、分類名稱、標籤名稱與個人資料皆完整保留，不會被 App 翻譯或覆寫。
```

- **Support URL**: `https://inazumimakoto.github.io/lifelog-support/`
- **Privacy URL**: `https://inazumimakoto.github.io/lifelog-support/`

IAP:
- Monthly: `lifelify Premium 月訂閱` / `解鎖 1 個月進階功能。`
- Yearly: `lifelify Premium 年訂閱` / `解鎖 1 年進階功能。`
- Lifetime: `lifelify Premium 終身` / `一次購買即可解鎖進階功能。`
