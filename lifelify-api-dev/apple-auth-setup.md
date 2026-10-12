# CloudflareでAppleログインを有効にする

買い物用の本人確認とChatGPTへのOAuth認可をCloudflareで処理する。
Firebaseの手紙用ログインとは別の仕組みで、Firebase UIDを買い物の所有者IDに流用しない。

現在の `wrangler.jsonc` は `AUTH_MODE = "apple"` に設定済み。
Apple Developerの設定とWorkerのSecretを揃えてからデプロイする。
Apple側の実設定・ログインの疎通はユーザーが行う。

## 1. Apple DeveloperにWeb用のServices IDを登録する

[Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list)
を開き、既存のWeb用Services IDがあるか確認する。
新しく作る場合は、Identifiersの「+」→「Services IDs」を選ぶ。
説明は `lifelify shopping development`、識別子の候補は
`com.inazumimakoto.lifelog.web.dev`。実際に登録した識別子を `APPLE_SERVICE_ID` に使用する。

登録したServices IDの「Sign in with Apple」→「Configure」で、
既存アプリ `com.inazumimakoto.lifelog` に対応するPrimary App IDを選ぶ。
既存のSign in with Appleのグループ設定を確認して関連付ける。
iOSのApp Groups `group.lifelog.share` とは別の設定。

Website URLsには次を登録する。ドメイン欄にはスキームやパスを含めない。

| 設定 | 値 |
| --- | --- |
| Domains and Subdomains | `lifelify-api-dev.inazumimakoto.workers.dev` |
| Return URLs | `https://lifelify-api-dev.inazumimakoto.workers.dev/auth/apple/callback` |

Return URLは末尾のパスまでコードと一致させる。ChatGPTのコールバックURLとは別。
Appleの現在のWeb設定手順ではドメイン確認用ファイルのアップロードは不要。
設定後にContinue / Saveまで進める。

## 2. Sign in with Apple用の鍵を用意する

KeysでSign in with Appleに対応し、同じPrimary App IDに関連付けた鍵を用意する。
APNs用の鍵とは用途が異なる。既存の適切な鍵を使う場合はKey IDと秘密鍵の両方が必要。
新しく登録する場合は「+」→Sign in with Appleを有効化→Primary App IDを指定して登録し、
`.p8` ファイルをダウンロードする。

プロジェクトで確認したTeam IDは `V7XG8HDQL4`。
実際にApple Developerで選択したTeamと一致することを確認する。
このTeam ID、Services ID、Key IDは設定値として使う。秘密鍵の内容は会話へ貼り付けない。

## 3. Workerの設定を揃える

`wrangler.jsonc` の `vars` には、確認したServices ID・Team ID・Key IDを設定済み。

```jsonc
"vars": {
  "AUTH_MODE": "apple",
  "APPLE_SERVICE_ID": "com.inazumimakoto.lifelog.web.dev",
  "APPLE_TEAM_ID": "V7XG8HDQL4",
  "APPLE_KEY_ID": "89TL78B5D3"
}
```

秘密鍵は `vars` に書かず、ユーザーがターミナルからWorkerのSecretへ登録する。
確認済みのダウンロード先を使い、次を実行する。

```sh
cd /Users/inazumimakoto/Desktop/lifelog/lifelify-api-dev
npx wrangler secret put APPLE_PRIVATE_KEY < "/Users/inazumimakoto/Downloads/AuthKey_89TL78B5D3.p8"
npm run deploy
```

秘密鍵ファイルはこのリポジトリに追加しない。`.dev.vars` の開発用トークンは従来のREST確認用。
AppleモードのMCP認可画面はこの開発用トークンを受け付けない。
モード・必要なApple設定が不正な場合は認証を停止し、開発用ログインへ自動で戻らない。

## 4. ChatGPTから接続し直す

購入先対応だけの更新は、developmentモードのままデプロイして試せる。
プラグイン詳細でツール定義・サーバーの指示を更新してから新しいチャットで確認する。

Appleモードへ切り替えた後は、以前の開発用OAuth接続は利用できない。
ChatGPT側で接続し直し、lifelifyのページでAppleログインを選ぶ。

1. Appleでログインする。
2. lifelifyのページへ戻って、ChatGPTに許可する権限を確認する。
3. 許可するとChatGPTへ戻る。
4. 「買い物リストを見せて」→新規アカウントなら空の一覧。
5. 「リンゴを3つ追加して」→購入先の質問→「未指定で」→本人のリストへ追加。

Appleの検証済み `sub` ごとにD1の `users.id` をUUIDで作成する。
再接続時は同じ `users.id` を使用する。論理削除済みアカウントは自動復活させない。
`dev-user` の卵・牛乳・リンゴは新しいAppleアカウントに自動移動しない。
新規アカウントには購入先もまだなく、登録機能やiPhoneからの取り込みは後続で実装する。

## 実装した範囲と後続の作業

Appleの認可コードをサーバー間で交換し、JWTの署名・issuer・audience・期限・nonceを検証する。
ログイン試行はブラウザCookieとstateに紐づき、有効期限は10分。
Appleの戻り先はcross-site POSTなので、専用のSecure / HttpOnly / SameSite=None Cookieを使う。
戻ったあと同一サイトのGETを経由して、既存MCP認可Cookieで最終同意を検証する。
Appleのメール・氏名・トークンは買い物用DBへ保存しない。

KVでの一回使用には同時実行・伝播遅延の制限がある。同じブラウザのApple認可は一度に1件。
この段階は開発用で、実Appleの設定・実機のブラウザでの確認は別途必要。
Appleでの連携解除を通知で即時反映する仕組み、アカウント削除、連携解除UI、
既存SwiftDataとの同期は後続の作業。
本人確認済みのiOS向けセッションとアプリ承認の開発版は
[ネイティブ接続の手順](./native-app-connection-setup.md) に追加している。
`APP_APPROVAL_ENABLED = "false"` の間はこの文書のWeb認可を維持する。
Appleでログインできても、iPhoneの買い物データが同期される段階ではない。

## 公式資料

- [Web向けSign in with Appleの設定](https://developer.apple.com/help/account/capabilities/configure-sign-in-with-apple-for-the-web/)
- [Sign in with Apple用の秘密鍵](https://developer.apple.com/help/account/capabilities/create-a-sign-in-with-apple-private-key)
- [Appleのユーザー認証](https://developer.apple.com/documentation/signinwithapple/authenticating-users-with-sign-in-with-apple)
- [本人確認トークンの検証](https://developer.apple.com/documentation/signinwithapple/verifying-a-user)
