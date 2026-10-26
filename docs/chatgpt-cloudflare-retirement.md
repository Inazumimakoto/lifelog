# ChatGPT・Cloudflare連携の撤去

2026-10-26。今回追加した外部AI連携を取りやめ、アプリを既存のローカル保存中心の構成に戻す。

## アプリ側の変更

- ChatGPTへの接続、MCP/OAuth、Cloudflare用Appleログイン、機能別共有設定、クラウド削除画面を撤去した。
- 買い物・日記・予定・タスク・習慣・記念日・設定・写真のCloudflare向けAPIと同期処理、専用の同期モデル、WorkersのUniversal Linkを撤去した。
- 専用バックエンド `lifelify-api-dev/` と、開発・Simulator環境の設定、SQL、関連テスト・手順書を撤去した。
- 端末にある通常のSwiftDataモデル13種と写真ファイルは保持する。同期用の補助モデルを外した保存ファイルを再オープンする回帰テストを追加した。
- 旧連携だけが使用していたローカルKeychainの2サービスを起動時に削除する。秘密情報の読み取りやサーバーへの通信は行わない。

Firebase認証・手紙送受信・E2EE、日記写真のCloudKit保存、写真アプリの元写真、MapKit検索、ウィジェット、既存のAppleログイン・APNs・App Groupsは維持する。今回の変更をインストールしても、下記のCloudflareリソースが自動削除されるわけではない。

## Cloudflare管理画面で削除するもの

以下は開発時の設定と作成履歴に基づく一覧。管理画面の現在のリソース名・IDと照合して、今回の連携専用のものだけを削除する。こちらからクラウド上の削除は実行していない。

| 種類 | 名前 | 照合用ID |
| --- | --- | --- |
| Worker | `lifelify-api-dev` | — |
| Worker | `lifelify-api-simulator` | — |
| Worker | `lifelify-connect-dev` | — |
| D1 | `lifelify-dev` | `bf8ba31b-c5d8-4315-a45e-653c1a8cbdb0` |
| D1 | `lifelify-simulator` | `d586ed79-3276-4c13-9c12-6e510334a3e5` |
| Workers KV | `lifelify-oauth-dev` | `3ffcd919c29b45108426753c9fae3e5e` |
| Workers KV | `lifelify-oauth-simulator` | `104fcb18ad3e49c9b6d36cb0ac8e1cc1` |
| R2 | `lifelify-photos-dev` | — |
| R2 | `lifelify-photos-simulator` | — |

削除前に、クラウドだけに残っている商品などで必要な内容があれば控える。端末へ取り込まれていないデータは、アプリ側の撤去では回収しない。

### 1. APIと認可ページを停止する

Cloudflareの「コンピュート → Workers & Pages」で、上記3つのWorkerそれぞれを開く。「設定」の最下部にある削除操作を選び、対象のWorker名を入力して削除する。これにより今回の公開API・MCP・認可ページを停止する。[Cloudflare公式手順](https://developers.cloudflare.com/d1/get-started/#7-optional-delete-your-database)

Workerのバインディングを外すだけでは、D1・KV・R2の保存データは削除されない。続けて次の操作を行う。

### 2. D1の2データベースを削除する

「ストレージとデータベース → D1 SQLiteデータベース」で対象を開き、「設定 → 削除」からデータベース名を入力する。`lifelify-dev` と `lifelify-simulator` の両方で行う。テーブルを1つずつ削除する必要はない。[Cloudflare公式手順](https://developers.cloudflare.com/d1/get-started/#7-optional-delete-your-database)

### 3. OAuth用KVの2名前空間を削除する

「ストレージとデータベース → Workers KV」で、上記IDと一致する2つの名前空間を削除する。キーを個別に消すだけでなく、今回専用の名前空間そのものを削除する。

管理画面で削除操作が見つからない場合は、リポジトリの外（例：ホームディレクトリ）で、既存のWranglerログインを利用して次の2コマンドを1つずつ実行してもよい。確認画面では対象IDを照合する。今回削除したバックエンドフォルダは使用しない。[Wrangler公式仕様](https://developers.cloudflare.com/kv/reference/kv-commands/#kv-namespace-delete)

```sh
cd ~
npx wrangler kv namespace delete --namespace-id 3ffcd919c29b45108426753c9fae3e5e
npx wrangler kv namespace delete --namespace-id 104fcb18ad3e49c9b6d36cb0ac8e1cc1
```

### 4. R2の写真コピーとバケットを削除する

「R2 オブジェクトストレージ」で `lifelify-photos-dev` を開く。「Settings → Empty Bucket」で中身を空にする。完了後、「Delete Bucket」でバケットを削除する。`lifelify-photos-simulator` にも同じ操作を行う。すでに空なら、そのままバケットを削除できる。[Cloudflare公式手順](https://developers.cloudflare.com/r2/buckets/delete-buckets/)

ここで削除するのはCloudflareへの写真コピー。既存のApple iCloudコンテナやiPhone内の写真は削除しない。

### 5. 専用の鍵・追加設定を片付ける

- 今回専用に作成したCloudflare APIトークンやR2 APIトークンがあれば、そのトークンだけを失効する。他のサイトで使用するWranglerログインや共通トークンは残す。
- 別途カスタムドメイン・DNS・ログ転送先を今回のために設定した場合は、その関連付けだけを解除する。開発時の標準接続先は `*.inazumimakoto.workers.dev` だった。
- Workers・D1・KV・R2の一覧で上記対象がなくなったことを確認する。リソースの削除は、提供元のバックアップ・ログまで即時消去されたことを意味しない。

`inazu.me`、`copy-gap`、ほかのCloudflareプロジェクト、Cloudflareアカウント自体は削除対象ではない。

## ChatGPT・Apple側の後片付け

ChatGPTの設定で、今回作成したlifelifyの開発用・Simulator用接続を切断し、不要なカスタムプラグインを削除する。過去のチャットに表示された内容は、接続や元のDBを削除しても遡って消えるわけではないので、不要な会話は別途整理する。

Apple Developerでは、Web用Services ID `com.inazumimakoto.lifelog.web.dev` と、今回のWeb認証用に作成したKey ID `89TL78B5D3` がほかで使われていなければ廃止する。鍵の失効前に、Firebaseの既存Appleログイン等で共用していないか確認する。Downloadsなどリポジトリ外に保存した `AuthKey_89TL78B5D3.p8` は今回のコード削除では触っていない。

**既存のiOS App ID `com.inazumimakoto.lifelog`、手紙のAppleログイン設定、Firebaseプロジェクト、CloudKitコンテナは残す。** Apple Maps Server API用の鍵を別途作成した場合も、今回専用のものだけが整理対象であり、元のアプリのMapKit検索設定は残す。

## 撤去後の検証

- iPhone向けReleaseビルド成功（`CODE_SIGNING_ALLOWED=NO`）。
- iPhone 17 Pro／iOS 26.1で、署名ありのXCTestを実行。431テスト成功、失敗0件。
- 移行テストでは、通常モデル13種と代表的な旧同期モデル2種を含む一時SQLiteを作成し、通常schemaで2回開き直した。通常データ・写真参照・写真ファイルの内容を保持した。旧同期モデルの全種類を再現した検証ではない。
- Keychain削除のテストは注入した偽の削除処理を使用し、専用サービスだけを指定すること、通常の通知・壁紙設定を保持すること、削除失敗時の再試行を確認した。
- Firebase/E2EE・手紙送受信・CloudKit写真保存の主要サービスには変更を加えていない。実際のクラウドサービス上の削除や、実アカウントでの送受信試験はこの撤去作業では実行していない。
