# lifelifyアプリでChatGPT接続を承認し、買い物を同期する（開発版）

目標の導線は「lifelifyでAppleログイン → ChatGPTのプラグイン詳細 → 接続 → lifelifyで権限を確認・許可 → 元のChatGPT接続画面へ戻る」。
アカウント作成は初回だけで、以後は端末のKeychainに保存したlifelifyセッションを使用する。
ChatGPTのアカウントとは別。Firebaseの手紙用ログインもそのまま独立している。

**この実装はDEBUGビルド専用。買い物の同期は、利用者が明示的に開始した場合だけ有効になる。**
AppleログインやChatGPTへの許可だけでは、iPhone内の商品をアップロードしない。
初回同期の操作で商品・購入先・メモをCloudflareへ送り、以後は同じlifelifyアカウントのクラウド変更も端末へ取り込む。
同期を始める前は、クラウドと現在のiPhone内の買い物データは別々。
Cloudflareのリモート設定・SQL実行・デプロイ・Apple設定はユーザーが行う。

## 1. D1に認証・承認用のテーブルを追加

既存の `users`、`shopping_places`、`shopping_items` は削除しない。
次のSQLは追加だけで、既存の買い物データを変更しない。
このプロジェクトの初期3表はコンソールで作成済みなので、ここではmigrationファイルを直接実行する。

```sh
cd /Users/inazumimakoto/Desktop/lifelog/lifelify-api-dev
npx wrangler d1 execute lifelify-dev --remote --file migrations/0002_native_auth.sql
npx wrangler d1 execute lifelify-dev --remote --file migrations/0003_app_consent.sql
```

新しい表は `native_auth_challenges`、`native_sessions`、`shopping_oauth_requests`。
認証用の時刻はUnix秒。既存の買い物・usersの時刻はUnixミリ秒のまま。
Native access/refresh tokenはD1にSHA-256ハッシュだけを保存する。

## 2. アプリを開く専用Workerをデプロイ

```sh
npm run deploy:links
```

別名のWorker `lifelify-connect-dev` を作成する。
新しいD1やKV、秘密鍵は不要。既存の `lifelify-api-dev` は上書きしない。
次のURLで、リダイレクトなしのJSONが表示されることを確認する。

https://lifelify-connect-dev.inazumimakoto.workers.dev/.well-known/apple-app-site-association

JSONの `appIDs` は `V7XG8HDQL4.com.inazumimakoto.lifelog`、許可するパスは `/connect/*`。
実際のアプリは `/connect/` の後に43文字のopaque IDがあるHTTPS URLだけを受け付ける。
リンクにアクセストークン、Appleトークン、OAuthコードは含めない。
リンク先をGETするだけでは許可されない。

認可Webとリンク先を別ホストにしているのは、Safariが同じドメイン内のリンクをWebのまま開く場合があるため。
このWorkerのURLで「lifelifyを開く」を押しても、そのインストール済みアプリがUniversal Linkを認識するまではWebの案内ページになる。

## 3. メインWorkerを更新

```sh
npm run deploy
```

`APPLE_PRIVATE_KEY` は登録済みのものを使用する。再アップロード不要。
追加設定は `APPLE_APP_ID = "com.inazumimakoto.lifelog"`。
Web用のServices ID `com.inazumimakoto.lifelog.web.dev` とは用途が違う。
ネイティブApple JWTではApp ID、Web Apple JWTではServices IDをaudienceとして検証する。
Apple公開鍵による検証なので、ネイティブログインのための新しい秘密鍵は不要。

初回導入では `APP_APPROVAL_ENABLED = "false"` のまま `/auth/native/*` によるアプリログインを先に確認した。
2026-10-11、ユーザーのネイティブAppleログイン成功を確認後、ローカル設定を `"true"` に変更した。現在の設定でデプロイすると、ChatGPTで新しく「接続」を開始した際にアプリ承認の中継画面が出る。
D1の追加テーブルを先に作成すること。WebのAppleログインも中継画面の代替手段として残る。

## 4. Xcodeで開発版をiPhoneに入れる

アプリには次のAssociated Domainを追加済み。既存の手紙招待ドメインは保持している。

```
applinks:lifelify-connect-dev.inazumimakoto.workers.dev
```

Xcodeで `lifelog` target → Signing & CapabilitiesのTeamが `V7XG8HDQL4`、Bundle Identifierが `com.inazumimakoto.lifelog` であることを確認する。
App IDのAssociated Domains capabilityが有効であることも確認する。
自動署名の場合はXcodeにprofile更新を任せ、手動署名の場合は新しいentitlementを含むprofileを再発行する。
**新しいentitlementを含むDEBUGビルドを実機にインストールする。**
AASAはAppleのCDN経由で取得され、公開直後の反映に時間がかかる場合がある。

買い物画面のメニュー → ChatGPT連携を開く。
試作のデータ扱いの説明を確認し、Appleでlifelifyアカウントを作成／ログインする。
Appleのメール・氏名は要求せず、DBにも保存しない。
Web Services IDを同じPrimary App IDに関連付けていることをApple Developerで確認する。
先にWebで作った本人のアカウントがある場合、同じApple Accountでアプリにログインし、D1 `users.id` と開発画面のアカウントIDが一致することを実機で確認する。
異なる場合はApple側のグループ設定を確認し、メールアドレスを使った自動統合はしない。

## 5. ChatGPTアプリへのリンクを確認

現在の開発用リンクは次のもの。

https://chatgpt.com/plugins/plugin_asdk_app_6aca4c016e688191ae17c3440cb97dc1

「lifelifyのプラグインを開く」は `universalLinksOnly` を使い、OSがChatGPTアプリで処理できる場合だけ開く。
2026-10-11の実機報告では、この個別URLはChatGPTアプリが一度起動した後にWebへ移り、ブラウザはChatGPTに未ログインだった。HTTPS URLをアプリに渡せたことと、個別ページをアプリ内で表示できたことは別。

同日に次のURLスキーム候補も実機で試したが、ChatGPTのホーム画面しか開かず、lifelifyの個別詳細画面へは進めなかった。

`chatgpt://plugins/plugin_asdk_app_6aca4c016e688191ae17c3440cb97dc1`

この形式はHTTPS URLから推測したもので、OpenAIが公開したiOSの対応仕様ではない。結果を受けて検証ボタン・定数・5言語の検証用文言を撤去し、HTTPS導線を採用した。プラグイン画面へ入るためにブラウザでChatGPTにログインすることをユーザーが了承済み。
公開時は公開版プラグインのリンクに差し替える。
ChatGPTアプリがログイン済みなら、lifelify側にChatGPTのログインIDを入力する欄はない。
ChatGPT側のログイン・アカウント選択はChatGPTで行う。

## 6. アプリ承認を有効にして接続し直す

`wrangler.jsonc` の `vars.APP_APPROVAL_ENABLED` は文字列 `"true"` に変更済み。導入時はこの設定のデプロイ前に `app_approval_not_configured` が返っていたが、反映後はユーザーが実機でアプリへの移動と許可まで確認済み。
Dashboardだけで変更すると次のWrangler deployで上書きされるため、設定ファイルを変更する。

承認用テーブルが未作成でも進められるよう、先に追加SQLを実行する。`CREATE TABLE/INDEX IF NOT EXISTS` なので、既に同じテーブルがある場合も既存のデータは変更しない。

```sh
npx wrangler d1 execute lifelify-dev --remote --file migrations/0003_app_consent.sql
npm run cf-typegen
npm run deploy
```

ChatGPTの開発用プラグインで接続し直す。既存の有効な接続では認可画面が開かないので、新しい接続要求から確認する。

1. ChatGPTで「接続」を押す。
2. lifelifyのWeb接続画面で「Open lifelify to review access」を押す。
3. lifelifyアプリでクライアント、権限、使用するlifelifyアカウントを確認する。
4. アプリがロック中なら先に解除する。明示的に「許可する」か「拒否する」を押す。
5. 最新の開発版では、決定後にブラウザの接続完了ページを自動で開く。元のブラウザCookieが一致すると、ChatGPTの登録済みコールバックへ進む。
6. 「買い物リストを見せて」で本人のクラウドデータを確認する。

自動復帰に使うのは固定ホストの `https://lifelify-api-dev.inazumimakoto.workers.dev/auth/app/resume?id=…`。
アプリが持つのは承認要求のopaque IDだけで、OAuthコードやChatGPTのログイン情報は渡さない。
このページのGETは承認やOAuth grantの発行を行わず、元のCookie・要求ID・期限を照合して、既存の `/authorize` へのフォームPOSTを行う。

通常のHTTPSを開くため、iOSの既定ブラウザに移動する。ChatGPTのネイティブアプリへ戻ることや、元のブラウザタブを選択することは保証しない。
lifelifyのWebボタンも埋め込みSafariを使わず通常のHTTPSで開く。プラグインURLはUniversal Linkの対象なので、最初にChatGPTアプリが開くかどうかはOSとChatGPT側が決める。認可を始めたブラウザと復帰先が同じであることが、自動完了の条件。
別のブラウザ、プライベートブラウズ、アプリ内の `SFSafariViewController` などで始めた接続は、移動先のCookieと一致しない場合がある。
一致しなければ自動完了せず、元の接続画面へ戻るよう案内する。lifelifyで行った許可／拒否は保持するので、再承認や再ログインは行わず、元の画面へ戻って「Check approval」を押す。
10分で期限切れ。期限切れ・別ブラウザ・アカウント削除・失効セッションからの承認は拒否する。
ネイティブの承認要求はD1でpending→approved/deniedを原子的に処理する。
元のブラウザCookieとOAuth consent handleも確認してから、一度だけOAuth grantを発行する。
承認リンクは転送できるため、自分がChatGPTで開始した接続であることも画面で確認する。
サーバーが確認できるのは要求元クライアントとlifelifyの本人で、ChatGPTアカウントの所有者IDではない。
開けない端末／PCには、同じWeb画面のAppleログインという代替経路がある。
Cookie・アプリ認証・OAuthトークンを共有する仕組みではない。

## 7. 買い物の同期を開始する

認証・承認の設定が済んでいる場合、今回の追加分は次のSQLとメインWorkerの更新。
Cloudflareの操作はユーザーが行う。リンク専用Workerに変更はない。

```sh
cd /Users/inazumimakoto/Desktop/lifelog/lifelify-api-dev
npx wrangler d1 execute lifelify-dev --remote --file migrations/0004_shopping_sync.sql
npm run deploy
```

このmigrationは `shopping_changes` と `shopping_mutation_receipts` を追加し、商品・購入先の変更を記録するtriggerとindexを作る。
既存のクラウド商品・購入先・削除記録も変更ログへ取り込む。既存の商品や購入先を消すSQLではない。
SQLを実行してから、新しい同期APIを含むWorkerをデプロイする。

Xcodeから最新のDEBUGビルドをiPhoneへ入れ、買い物メニュー → ChatGPT連携を開く。
本人のApple Accountでログインし、同期するlifelifyアカウントを確認する。
表示される説明を読んで**「買い物データの同期を開始」を押す**。商品名・購入先名・メモがCloudflareへ保存され、許可したChatGPT連携から読み書きできる。
買い物データは手紙機能のE2EE対象ではなく、バックエンドで処理できるデータとして扱う。手紙用のFirebase認証・暗号化は変更しない。

初回は購入先と商品をIDごとに送り、端末のデータでクラウド全体を置き換えない。
既にクラウドにある商品は残し、商品名が同じでもIDが異なるものは別商品として保持する。
同じIDのデータに別々の変更がある場合は、後述の競合確認に進む。
同期は最初に選んだlifelifyアカウントに紐付ける。別アカウントへログインし直しても、その端末データや未送信の変更を自動でアップロードしない。

開始後はアプリの起動・復帰時、手動同期、ローカルの買い物変更をきっかけに同期する。
ChatGPTで追加しても、バックグラウンドのiPhoneへ即時反映する仕組みではない。**FCM／APNsによる同期通知は未実装。**
まずChatGPTで商品を追加し、lifelifyを開き直すか手動同期して、商品名・購入先・メモが取り込まれることを確認する。
逆方向はアプリで商品を追加・編集し、同期完了後にChatGPTで買い物リストを確認する。

### オフラインと競合

端末の変更は永続outboxへ保存してから送信する。アプリ終了や通信失敗で未送信の変更を失わず、再送には同じoperation IDを使用する。
クラウド変更の取得は `updated_at` ではなく、ユーザーごとの変更を絞った連番 `seq` とcursorで進める。
cursorと取り込み済みの状態は端末へ保存する。削除もversionを持つtombstoneとしてクラウドに記録し、他端末への伝達に使う。購入履歴を表示する機能ではない。

送信時の `base_version` が現在のクラウド版と一致しなければ409を返す。
端末版とクラウド版を確認して、どちらを使うか利用者が明示的に選ぶ。時刻だけで片方を上書きしない。
購入先の削除では、その購入先を使っていた商品を未指定へ変更する。商品自体は保持する。

開発版では変更ログ・削除記録・再送用レシートを自動削除せず保持している。変更ログには過去のメモも含まれるため、一般公開前に保持期間・アカウント削除・古いcursorの再取得を組み合わせた整理処理が必要。ログだけを先に削除すると、長期間オフラインだった端末が削除を取り逃す。

## 動作確認と未実装の範囲

- 同じApple Accountで再ログインして同じlifelify user IDになること。
- 許可／拒否／期限切れ／アプリロック／自動復帰とCookie不一致時の手動復帰。
- 初回同期が明示的な操作まで始まらず、クラウドの既存商品を残すこと。
- 商品・購入先・メモの双方向同期、購入チェック・取り消し、購入先の削除と並べ替え。
- オフライン編集と再起動後のoutbox再送、重複送信、409競合の明示的な解決。
- 別アカウントでのログイン時に、既存端末データの送信を拒否すること。
- Native accessは1時間、refreshは更新ごとに30日。KeychainにはThisDeviceOnlyで保存する。
- refreshは一度だけ使える。応答が失われて新しいtokenを取得できなかった場合は再ログインする。
- アプリのログアウトは当該端末のnative sessionを失効する。**既に許可したChatGPT OAuth接続の解除ではない。** ChatGPT側で連携解除する。
- この開発用プラグインのリンクや設定画面をそのまま一般ユーザーへ告知しない。公開版と配布条件の確認が必要。

後続は、同期通知、同期ログの保持・圧縮、アカウント削除と連携管理、複数端末での実機検証。
native同期の再送にはoperation IDを使うが、ChatGPTの追加ツールは呼び出すたびに新しい商品を作成する。結果不明のMCP書き込みを自動で再試行しない。
一般公開前に認証チャレンジ発行や認証交換のレート制限、失効したApple認証の反映、期限切れデータの定期削除、Web認可画面の5言語対応を行う。
期限切れOAuth requestを先に削除し、native sessionは参照されていない期限切れ／失効済み行だけを削除する。
APIの検証ログにはリクエスト本文、Apple JWT、native/OAuth token、URL queryを出力しない。

```sh
npm run typecheck
npm test
npx wrangler deploy --dry-run --minify
npx wrangler deploy --config wrangler.link.jsonc --dry-run --minify
```

上記はローカル検証。D1の統合テストは隔離Miniflareを使用し、実Apple／ChatGPTの通信と本物のCloudflare DBの更新は行わない。

2026-10-11の認証導入時には、バックエンド78テスト、署名ありiPhone 17 Pro SimulatorのXCTest154テスト、generic iOSのDebug/Releaseビルド、両Workerのminified dry runが成功。
ユーザーが実機でAppleログイン、HTTPSでのプラグイン画面への移動、接続要求からUniversal Linkでlifelifyへ戻る操作、アプリでの許可まで確認済み。
今回追加した自動復帰と買い物同期は新しい開発版の機能。クラウドへのmigration／デプロイと最新iOSビルドの導入後に、上記の双方向同期・オフライン・競合・別アカウントの動作を実機で確認する必要がある。ローカルテスト・ビルドの成功と、実Apple／ChatGPTを使った確認を区別する。

## 公式資料

- [ChatGPTのプラグイン（Web・desktop・mobile）](https://help.openai.com/en/articles/20001256-plugins-in-chatgpt)
- [ChatGPT MCP OAuth](https://developers.openai.com/plugins/build/auth)
- [Apple Universal Linksのデバッグ](https://developer.apple.com/documentation/technotes/tn3155-debugging-universal-links)
- [ChatGPTの公式AASA（HTTPS `/plugins` と `/plugins/*` の関連付け）](https://chatgpt.com/.well-known/apple-app-site-association)
- [Associated Domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains)
- [iOSの既定ブラウザ](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser)
- [SFSafariViewController](https://developer.apple.com/documentation/safariservices/sfsafariviewcontroller)
- [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
- [Sign in with Appleのグループ設定](https://developer.apple.com/help/account/capabilities/group-apps-for-sign-in-with-apple/)
