# lifelify 買い物APIの開発用プロジェクト

SwiftDataとの対応は `../docs/cloudflare-shopping/README.md` を参照。
Worker名は `lifelify-api-dev`、接続先は開発用D1 `lifelify-dev`。
`remote: true` により、Mac上の `npm run dev` からもクラウドD1へアクセスする。
現在の設定はAppleログイン用。デプロイ前に [Apple認証の設定](./apple-auth-setup.md)
に従って `APPLE_PRIVATE_KEY` をWorkerのSecretへ登録する。

アプリでのアカウント作成・ChatGPTアクセス承認は
[ネイティブ接続の手順](./native-app-connection-setup.md) を参照。
DEBUGビルド専用で、Universal Link用Workerと追加のD1表が必要。
`APP_APPROVAL_ENABLED = "false"` の間は従来のWeb認可を維持する。

## Macで確認する

```sh
npm run setup:dev
npm run cf-typegen
npm run dev
```

別のターミナルで次を実行する。

```sh
npm run shopping:list
npm run shopping:add -- 牛乳 "1リットルを1本"
npm run shopping:list
```

追加するたびにクラウドの開発用D1へ1件保存する。同名商品は追加できる。
再送を識別する冪等性キーはまだ実装していない。
購入先を指定する場合は、メモの次に自分の購入先UUIDを渡す。
CLIは `http://localhost:8787` のみを使い、秘密のトークンを引数や出力に含めない。

## API

| メソッド / パス | 動作 |
| --- | --- |
| `GET /health` | 3表の存在を確認する |
| `GET /api/shopping/items` | 未削除商品の新しい順の先頭100件と `has_more` を返す |
| `POST /api/shopping/items` | 商品を追加し `201` と作成した商品を返す |

商品APIは `Authorization: Bearer <DEV_API_TOKEN>` が必須。
このトークンは固定の開発用ユーザー `dev-user` にだけ対応する。
リクエストの `user_id` は認証として使わない。
ユーザーが未作成または論理削除済みならアクセスを拒否する。

追加のJSONは `title`、任意の `note`、任意の `place_id` のみ。
タイトルは前後の空白を除いて1〜200 UTF-16コード単位で、NUL文字は受け付けない。
メモは最大4000コード単位。
メモの空白や改行は保持する。購入先は同じユーザーの未削除レコードだけを受け付ける。
JSON全体は16 KiBまで。ID・時刻・初期 `version = 1` はサーバーで設定する。

`has_more = true` の場合の続きのページ取得、編集・購入/削除、同期は次の段階で実装する。
**このREST APIは固定の開発用ユーザーの確認用。Appleユーザーの接続はMCP側で処理する。**

## 秘密情報と公開設定

`npm run setup:dev` は暗号学的乱数でトークンを生成し、Git除外済みの `.dev.vars` に保存する。
有効な既存トークンは保持する。`npm run cf-typegen` は設定から型を生成する。
`.dev.vars` はローカル専用で、デプロイ先へ自動転送されない。
Workerの作成・リモートの秘密情報設定・デプロイはユーザーが手順に沿って行う。

## 作成済みのWorkerへデプロイする

次のコマンドはユーザーが実行する。`lifelify-api-dev` の公開コードを更新し、
`.dev.vars` の開発用トークンを同じWorkerのSecretとして登録する。
今回のファイルには `DEV_API_TOKEN` だけが入っている。

```sh
npm run deploy -- --secrets-file .dev.vars
```

`.dev.vars` の内容は通常のデプロイでは転送されないため、初回はこのオプションを指定する。
設定後のコード更新は `npm run deploy` で行える。既存のSecretは保持される。
デプロイ完了後は、表示された公開URLの `/health` を開いて `ok: true` を確認する。
商品APIは認証が必要なので、ブラウザで直接開くと401になる。
`preview_urls: false` を明記して、バージョンごとの確認用URLを無効にしている。
通常の `lifelify-api-dev.<subdomain>.workers.dev` は引き続き公開URLとして使う。
`AUTH_MODE = "development"` は固定の開発用ユーザー向けOAuth。
現在は `apple` に設定済み。秘密鍵の登録と接続確認は [Apple認証の設定](./apple-auth-setup.md) を参照。

## ChatGPTのカスタムMCPサーバーで接続する

このアカウントの「プラグインを作成」「カスタムMCPサーバーを追加」から接続する。
MCPはWorkerの `/mcp` でツールを公開する。OpenAPIを登録画面へ貼り付ける方式ではない。
`openapi.json` は従来のREST APIの一覧・商品名/メモでの追加を記述する補助資料。

### Cloudflareに追加する設定

ユーザーが作成したKV `lifelify-oauth-dev` を `OAUTH_KV` として設定済み。
Namespace IDは `3ffcd919c29b45108426753c9fae3e5e`。
設定ファイルには `global_fetch_strictly_public` も追加している。
これはChatGPTのClient ID Metadata Documentを安全に取得するために必要。
OAuthの認可・トークンなどの接続情報はKV、買い物データは既存のD1に保存する。

現在のAppleモードでは、CloudflareのSecretに `APPLE_PRIVATE_KEY` を登録してから
ユーザーが次を実行する。従来のREST確認用 `DEV_API_TOKEN` は登録済みのものを保持する。

```sh
npm run deploy
```

完了ログで `env.OAUTH_KV` と `env.DB` が表示されることを確認する。
REST用のSecretをまだ登録していない場合だけ、前述の `--secrets-file .dev.vars` を指定する。
Appleの秘密鍵は `.dev.vars` に含まれないため、別途登録する。

デプロイ後、次のURLをブラウザで開くとOAuthのメタデータJSONを確認できる。

- https://lifelify-api-dev.inazumimakoto.workers.dev/.well-known/oauth-protected-resource/mcp
- https://lifelify-api-dev.inazumimakoto.workers.dev/.well-known/oauth-authorization-server

`/mcp` はOAuthアクセストークンなしでは401になる。開発用RESTトークンを直接渡しても通らない。
認可サーバーのURLは `src/config.ts` で公開Workerのoriginに固定している。
ブラウザでのOAuth疎通はデプロイしたURLを使う。ローカルの `npm run dev` は従来のREST確認に使える。

### ChatGPTへ登録する

1. [ChatGPT Plugins](https://chatgpt.com/plugins) を開き、プラスボタンから「カスタムMCPサーバーを追加」を選ぶ。
2. 名前は `lifelify 開発用`、Server URLは
   `https://lifelify-api-dev.inazumimakoto.workers.dev/mcp`、AuthenticationはOAuthを選ぶ。
   Client ID・Client secretを入力する任意欄は空にする。CIMD、または動的クライアント登録を利用する。
   開発用トークンをChatGPTの設定欄や会話に入力しない。
3. プラットフォームの確認を読み、自分専用のプラグインとして作成する。公開ディレクトリへは提出しない。
4. lifelifyの認可画面が開いたら、URLのホストが
   `lifelify-api-dev.inazumimakoto.workers.dev` であること、クライアント・コールバック・権限を確認する。
5. AppleモードではAppleでログインし、lifelifyに戻って表示されたアクセスを許可する。
   developmentモードの場合だけ「Development access token」に `.dev.vars` の
   `DEV_API_TOKEN=` の右側64文字を入力する。ChatGPTには別のOAuthトークンを発行する。
6. [自分のプラグイン](https://chatgpt.com/plugins?view=personal) からインストールする。
7. ChatGPTのWorkチャットで `@` からプラグインを選び、「買い物リストを見せて」と依頼する。
8. 次に「卵を追加して。メモは6個入りを1パック、購入先は未指定で」と依頼する。
   書き込みの確認や追加権限の認可が表示されたら内容を確認する。
   再認可が必要な場合はlifelifyの画面で `shopping:write` を含む権限を許可する。
9. 続けて一覧を取得し、新しい商品が保存されていることを確認する。
   追加は実際の開発用D1に保存される。同名商品を別のIDで複数登録できる。

### ツールと認証の実装範囲

| MCPツール | 権限 | 動作 |
| --- | --- | --- |
| `list_shopping_places` | `shopping:read` | 未削除の購入先名・ID・表示順の先頭100件と `has_more` |
| `list_shopping_items` | `shopping:read` | 未削除商品の先頭100件と `has_more` |
| `add_shopping_item` | `shopping:read` + `shopping:write` | 商品名・メモ・購入先を指定して1件追加、作成したIDを返す |

個数・グラム数はメモに入れる。購入先は一覧から得た `place_id` を渡す。
MCPでは `place_id` を省略できず、購入先なしの場合にも `null` を明示する必要がある。
RESTの追加APIは従来どおり購入先の省略を受け付ける。

購入先を会話で指定していない場合は、登録済みの候補と「未指定」を示して質問し、
回答を待ってから追加するようにMCPの共通指示・ツール説明を設定している。
すでに指定している場合は購入先一覧と照合して追加し、再質問しない。
同名候補が複数ある場合や未登録の購入先名の場合は確認する。
購入先やIDを推測せず、勝手に新しい購入先を作らない。
この説明はChatGPTの会話を誘導するものであり、人間の回答そのものをAPIが検証する仕組みではない。

この変更のデプロイ後は、ChatGPTのプラグイン詳細画面でツールの定義を更新する。
古い定義には `place_id` がないため、更新せず追加すると入力検証で拒否される。
新しいチャットで次の3パターンを確認する。
「スーパー」のパターンはその購入先が登録済みのアカウントで確認する。
新しいAppleアカウントの購入先は空なので、最初は「未指定」で追加を確認する。

- 「リンゴを3つ追加して」→購入先の質問→「スーパー」→その購入先に追加。
- 「スーパーで買うリンゴを3つ追加して」→購入先の再質問なしで追加。
- 「リンゴを3つ追加して。購入先は未指定で」→`place_id: null` で追加。

ID・時刻・所有者はサーバーで決め、ツールの引数では所有者を指定できない。
認可後も各操作でユーザーの有効性を確認する。
`development` モードは固定の `dev-user`、`apple` モードはAppleで確認した本人に対応する。
ChatGPT OAuth接続の連携解除UI、iOS同期はまだ実装していない。
この段階の成功はクラウドへの追加を意味する。

OAuthはCloudflareの `@cloudflare/workers-oauth-provider` を利用する。
ChatGPTのコールバックに限定し、S256 PKCEとresourceの指定を必須にしている。
同意フォームはライブラリのブラウザに紐づくCookie/ハンドルで保護し、Originも検証する。
アクセストークンは1時間、更新可能期間は7日。CIMDとDCRに対応する。
失効エンドポイントは認可サーバーのメタデータに記載される `/oauth/token`。
開発用トークンを変更しただけでは、既存のOAuth接続は失効しない。

POSTやMCP追加の冪等性キーは未実装。結果不明時に自動再送をしない指示だけでは
重複防止を保証できない。一般公開前に追加の冪等性、連携の失効・削除、同期を設計する。
認可・コード・失効のKV保存にはKVの整合性に由来する制限があるため、厳密な同時実行の
一回使用や即時失効までを今回のローカルテストで保証するものではない。
一覧の長いメモが大量にある場合の応答サイズ制御も次段階の課題。
開発用認可画面は英語。一般公開前にja/en/ko/zh-Hans/zh-Hantの表示を整える。
Appleモードのコード・設定手順は [Apple認証の設定](./apple-auth-setup.md) を参照。
ネイティブ認証・アプリでの許可は [ネイティブ接続の手順](./native-app-connection-setup.md) を参照。

## 検証

```sh
npm run typecheck
npm test
npx wrangler deploy --dry-run
```

テストは一時ディレクトリのMiniflare D1だけを使用し、クラウドD1を読み書きしない。
dry runは公開せず、梱包までを確認する。

- [HonoのBearer認証](https://hono.dev/docs/middleware/builtin/bearer-auth)
- [Cloudflareのローカル秘密情報](https://developers.cloudflare.com/workers/configuration/secrets/)
- [コードとSecretの同時デプロイ](https://developers.cloudflare.com/workers/configuration/secrets/#upload-secrets-alongside-code)
- [ChatGPTのMCPプラグイン登録手順](https://developers.openai.com/plugins/quickstart)
- [ChatGPTのMCP認証](https://developers.openai.com/plugins/build/auth)
- [CloudflareのMCP handler](https://developers.cloudflare.com/agents/model-context-protocol/apis/handler-api/)
- [Workers OAuth Provider](https://github.com/cloudflare/workers-oauth-provider)
