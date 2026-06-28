# lifelify-support

## lifelify プライバシーポリシー
最終更新日：2026年6月12日

このプライバシーポリシーは、個人開発アプリ「lifelify」（以下、「本アプリ」）におけるユーザー情報の取り扱いについて説明するものです。本アプリをご利用いただく前に、本ポリシーをよくお読みください。

## 1. 開発者情報
開発者：MAKOTO INAZUMI（個人開発）
お問い合わせ：inazumimakoto@gmail.com

## 2. 収集する情報と利用目的

本アプリは、ユーザーがアプリ内で入力・操作した情報を、以下の目的で端末内に保存します。

### (1) ライフログデータ
・予定、タスク
・習慣（ハビット）の設定と達成状況
・日記の本文、気分アイコン、タグ、場所など
・メモ
・記念日、カウントダウンの対象日

**利用目的：**
・ユーザーの予定管理、タスク管理、日々の記録のため
・習慣の達成状況や連続日数（ストリーク）の表示のため
・記念日の残り日数表示のため

これらのデータはすべて端末内に保存され、開発者のサーバー等には送信されません。

### (2) ヘルスケアデータ（HealthKit）

本アプリは、ユーザーが許可した場合に限り、Apple の HealthKit を通じて以下の情報を読み取ります。
・歩数
・睡眠時間
・消費カロリー　など

**利用目的：**
・今日タブおよびヘルスタブにおけるヘルスサマリーの表示
・最近の体調の傾向を簡単に振り返るための統計表示

本アプリは HealthKit のデータを外部サーバーへ送信したり、第三者に提供したりしません。また、広告配信やユーザーのプロファイリングの目的で利用することもありません。

### (3) カレンダーデータ（EventKit）

本アプリは、ユーザーが許可した場合に限り、iOS のカレンダー（iCloud カレンダー等）から予定情報を読み取ります。

**利用目的：**
・「ホーム」タブおよび「カレンダー」タブにおいて、外部カレンダーの予定を lifelify 内の予定と合わせて表示するため
・lifelify 内でカテゴリや色を付けて見やすくするため

カレンダーのデータは読み取り専用であり、本アプリから外部カレンダーに予定を書き込むことはありません。また、カレンダーデータを開発者のサーバー等に送信することもありません。

### (4) 位置情報

本アプリは、ユーザーが許可した場合に限り、日記への位置情報の記録に利用します。

**利用目的：**
・日記に現在地の地名を記録し、思い出を振り返りやすくするため

位置情報はユーザーが日記に記録する際にのみ取得され、端末内に保存されます。開発者のサーバー等に送信されることはありません。

### (5) 生体認証（Face ID / Touch ID）

本アプリは、ユーザーが設定で有効にした場合に限り、アプリロック機能で Face ID または Touch ID を利用します。

**利用目的：**
・アプリ起動時の本人確認（プライバシー保護のため）

生体認証データは Apple の Secure Enclave で処理され、本アプリが生体情報そのものにアクセスすることはありません。認証の成功・失敗の結果のみを受け取ります。

## 3. データの保存場所と保存期間

### 基本機能（日記、タスク、習慣、メモなど）

**本アプリの基本機能で扱うすべてのデータは、ユーザーの端末内にのみ保存されます。**

・日記の内容、気分、写真
・タスクや予定
・習慣の記録
・メモ
・カウントダウン/記念日

**これらのデータは開発者のサーバーに送信されることは一切ありません。** したがって、開発者がユーザーの日記やタスクの内容を閲覧することは技術的に不可能です。

ユーザーがアプリを削除した場合、端末内に保存されている本アプリのデータは原則として削除されます（ただし、iCloud バックアップなどに残る場合があります）。

## 4. 第三者への提供

本アプリは、ユーザー情報を第三者に販売、貸与、共有することはありません。
法令に基づく開示要請があった場合を除き、開発者から第三者に個人情報を提供することはありません。

## 5. 外部サービス・解析ツールについて

本アプリは、現時点で開発者独自のサーバーや外部の解析ツール（アクセス解析、広告SDK等）を利用していません。
Apple が提供する TestFlight や App Store を通じて収集されるクラッシュログや統計情報については、Apple のプライバシーポリシーに従って取り扱われます。

### 「大切な人への手紙」機能（Firebase利用）

本アプリの「大切な人への手紙」機能では、Firebase（Google提供のクラウドサービス）を利用して友達同士で手紙を送り合います。

**収集・保存されるデータ：**
- Apple IDを使用したサインイン情報（Firebase Authentication）
- ユーザーが設定した表示名と絵文字アイコン
- 手紙の本文および添付写真（**暗号化済み**）
- 友達関係（ペアリング）の情報

> ⚠️ **重要：手紙の内容は開発者にも読めません**
>
> 手紙の本文と写真は「エンドツーエンド暗号化（E2EE）」により保護されています。暗号化に必要な秘密鍵はユーザーの端末内にのみ保存され、サーバーには送信されません。そのため、**開発者やGoogle（Firebase）を含む第三者がサーバー上の手紙の内容を復号して閲覧することは技術的に不可能**です。

**その他の安全対策：**
- 手紙は受信者が開封しローカルに保存された後、サーバーから自動削除されます
- 友達関係は双方の同意がなければ成立しません

**利用目的：**
- 友達同士で手紙を送受信するため
- 指定した日時に手紙を配信するため
- 手紙到着のプッシュ通知を送信するため

Firebase のプライバシーポリシーについては、Google のプライバシーポリシー（https://policies.google.com/privacy）をご確認ください。

### 「直接分析」機能

本アプリの「直接分析」機能では、ユーザーの日記データやライフログデータをAIで分析します。

**データの取り扱い：**
- 分析に使用するデータは開発者が管理するサーバーで処理されます
- 分析完了後、データはサーバーに保存されません（使い捨て処理）
- AIの学習データとして利用されることはありません
- 本機能のソースコードはGitHub（https://github.com/Inazumimakoto/lifelog）で公開されています

**利用目的：**
- 日記の添削・フィードバック
- 長期データの傾向分析

## 6. 権限の変更・データの管理

・HealthKit、カレンダー、位置情報、Face ID のアクセス権限は、iOS の「設定」アプリからいつでも変更・取り消しができます。
・本アプリ内のデータを削除したい場合は、アプリ内の削除機能をご利用いただくか、アプリ自体を端末から削除してください。

## 7. プライバシーポリシーの変更

本ポリシーの内容は、必要に応じて変更される場合があります。重要な変更がある場合は、App Store 上の説明文や本アプリ内のお知らせ等を通じてお知らせします。最新版のプライバシーポリシーは、開発者が指定する Web ページ上で確認できます。

## 8. お問い合わせ先

本ポリシーに関するご質問やお問い合わせがある場合は、以下の連絡先までご連絡ください。

メールアドレス：inazumimakoto@gmail.com

---

# Multilingual Support / Privacy Summary

Last updated: June 28, 2026

This document is the support and privacy reference for lifelify in Japanese, English, Korean, Simplified Chinese, and Traditional Chinese. The full Japanese policy above remains the source document. The sections below provide overseas users with the same practical support, data handling, and contact information.

Supported app languages: Japanese (`ja`), English (`en`), Korean (`ko`), Simplified Chinese (`zh-Hans`), Traditional Chinese (`zh-Hant`). Taiwan is handled as Traditional Chinese in v1.

Contact: inazumimakoto@gmail.com

## English

lifelify is a personal life log app for diary entries, schedules, tasks, habits, health summaries, anniversaries, widgets, lock screen calendar images, and letters.

Most app data is stored locally on your device. Diary text, tasks, schedules, habits, memos, anniversaries, location records saved in diaries, categories, and tags are not translated or overwritten by the app. If you delete the app, local app data is generally removed from the device, except for backups managed by iOS or iCloud.

With your permission, lifelify can read HealthKit data such as steps, sleep, and calories to display summaries. It does not write health data, sell health data, use health data for advertising, or send HealthKit data to third parties.

With your permission, lifelify can read iOS Calendar events to display them inside the app. It does not write to your external calendars.

Location access is used to show weather and, when you choose to save it, to attach place information to diary entries.

Face ID / Touch ID is used only for app lock. Biometric data is handled by Apple and is not accessible to lifelify.

The shared letter feature uses Firebase Authentication, Firestore, Storage, and Cloud Functions. Letter content and attached photos are end-to-end encrypted before upload. The private keys stay on user devices, so the developer and Firebase cannot read letter contents. Firebase also stores account metadata such as display name, emoji, friend pairings, FCM token, and preferred language code for notifications.

The direct AI analysis feature sends the selected diary/life log data to a developer-managed server for one-time processing. Analysis payloads are not stored after processing and are not used for AI training.

To manage permissions, open the iOS Settings app and change Health, Calendar, Location, Notifications, or Face ID access. For account or support requests, email inazumimakoto@gmail.com.

## 한국어

lifelify는 일기, 일정, 할 일, 습관, 건강 요약, 기념일, 위젯, 잠금 화면 캘린더, 편지를 관리하는 개인 라이프로그 앱입니다.

대부분의 데이터는 기기 안에 저장됩니다. 일기 본문, 작업, 일정, 습관, 메모, 기념일, 일기에 저장한 위치, 카테고리, 태그는 앱이 번역하거나 덮어쓰지 않습니다.

사용자가 허용한 경우에만 HealthKit의 걸음 수, 수면, 칼로리 등을 읽어 요약을 표시합니다. 건강 데이터를 쓰거나 광고, 판매, 제3자 제공 목적으로 사용하지 않습니다.

사용자가 허용한 경우에만 iOS 캘린더 일정을 읽어 앱 안에 표시합니다. 외부 캘린더에는 일정을 쓰지 않습니다.

위치 정보는 날씨 표시와 사용자가 선택한 일기 위치 저장에 사용됩니다. Face ID / Touch ID는 앱 잠금에만 사용되며, 생체 정보 자체에는 접근하지 않습니다.

공유 편지 기능은 Firebase를 사용합니다. 편지 본문과 사진은 업로드 전에 종단 간 암호화되며, 개인 키는 사용자 기기에만 저장됩니다. 개발자와 Firebase는 편지 내용을 읽을 수 없습니다. 알림을 위해 표시 이름, 이모지, 친구 관계, FCM 토큰, 선호 언어 코드가 저장될 수 있습니다.

직접 AI 분석 기능은 선택한 일기/라이프로그 데이터를 일회성 처리를 위해 개발자 관리 서버로 전송합니다. 분석 데이터는 처리 후 저장되지 않으며 AI 학습에 사용되지 않습니다.

권한 변경은 iOS 설정 앱에서 할 수 있습니다. 문의: inazumimakoto@gmail.com

## 简体中文

lifelify 是一款个人生活记录应用，可管理日记、日程、待办、习惯、健康摘要、纪念日、Widget、锁屏日历和信件。

大多数数据仅保存在你的设备上。日记正文、任务、日程、习惯、备忘录、纪念日、日记地点、分类和标签不会被应用翻译或覆盖。

在你授权后，lifelify 会读取 HealthKit 中的步数、睡眠、卡路里等数据用于摘要展示。应用不会写入健康数据，也不会将健康数据用于广告、出售或提供给第三方。

在你授权后，lifelify 会读取 iOS 日历事件并显示在应用中。应用不会写入外部日历。

位置信息用于显示天气，以及在你选择时保存到日记地点。Face ID / Touch ID 仅用于应用锁，生物识别数据由 Apple 处理，lifelify 无法访问。

共享信件功能使用 Firebase。信件正文和照片会在上传前进行端到端加密，私钥仅保存在用户设备上，因此开发者和 Firebase 都无法读取信件内容。为了通知和配对，Firebase 可能保存显示名、表情、好友关系、FCM token 和首选语言代码。

直接 AI 分析功能会将你选择的日记/生活记录数据发送到开发者管理的服务器进行一次性处理。分析完成后不会保存，也不会用于 AI 训练。

你可以在 iOS 设置中管理健康、日历、位置、通知和 Face ID 权限。联系邮箱：inazumimakoto@gmail.com

## 繁體中文

lifelify 是一款個人生活紀錄 App，可管理日記、行程、待辦、習慣、健康摘要、紀念日、Widget、鎖定畫面日曆與信件。

大多數資料只會儲存在你的裝置上。日記正文、任務、行程、習慣、備忘錄、紀念日、日記地點、分類與標籤不會被 App 翻譯或覆寫。

在你授權後，lifelify 會讀取 HealthKit 中的步數、睡眠、卡路里等資料用於摘要顯示。App 不會寫入健康資料，也不會將健康資料用於廣告、出售或提供給第三方。

在你授權後，lifelify 會讀取 iOS 行事曆事件並顯示在 App 中。App 不會寫入外部行事曆。

位置資訊用於顯示天氣，以及在你選擇時儲存到日記地點。Face ID / Touch ID 僅用於 App 鎖定，生物辨識資料由 Apple 處理，lifelify 無法存取。

共享信件功能使用 Firebase。信件正文與照片會在上傳前進行端對端加密，私鑰只保存在使用者裝置上，因此開發者與 Firebase 都無法讀取信件內容。為了通知與配對，Firebase 可能保存顯示名稱、表情符號、好友關係、FCM token 與偏好語言代碼。

直接 AI 分析功能會將你選擇的日記/生活紀錄資料傳送到開發者管理的伺服器進行一次性處理。分析完成後不會保存，也不會用於 AI 訓練。

你可以在 iOS 設定中管理健康、行事曆、位置、通知與 Face ID 權限。聯絡信箱：inazumimakoto@gmail.com
