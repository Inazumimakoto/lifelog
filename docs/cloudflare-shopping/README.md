# 買い物連携のD1初期スキーマ

対象は開発用データベース `lifelify-dev`。SwiftDataの買い物モデルとの対応は
`docs/requirements.md` §4.13 / §5 を参照。
`schema.sql` と `seed.dev.sql` はコンソール貼り付け用にコメントを含めない。
単一行の入力欄へ貼ると改行が消える場合があり、`--` コメントから始まるSQLは
全文がコメントとして扱われ、`Requests without any query are not supported` になる。
説明・コメントを足す場合も、ダッシュボードへ貼るSQLには `--` を混ぜない。

## ダッシュボードで作成する

1. Cloudflareの「ストレージとデータベース」→「D1 SQLite データベース」を開く。
2. `lifelify-dev` を選び、「コンソール」を開く。
3. `schema.sql` の全文をSQL入力欄に貼り付け、「実行 / Execute」を押す。
   複数文をまとめて実行できない入力欄の場合は、セミコロンまでの1文ずつ順番に実行する。
4. 以下を実行し、3つのテーブルが表示されることを確認する。

```sql
SELECT name
FROM sqlite_schema
WHERE type = 'table'
  AND name IN ('users', 'shopping_places', 'shopping_items')
ORDER BY name;
```

「データを探索」から列とデータも確認できる。作成直後は0件で正常。

任意の書き込み確認には `seed.dev.sql` をコンソールで実行し、以下を確認する。

```sql
SELECT i.title, i.note, p.name AS place_name
FROM shopping_items AS i
LEFT JOIN shopping_places AS p
  ON p.user_id = i.user_id AND p.id = i.place_id AND p.deleted_at IS NULL
WHERE i.user_id = 'dev-user' AND i.deleted_at IS NULL;
```

期待値は `卵 / 6個入りを1パック / スーパー`。
サンプルSQLは先に `users` に `dev-user` と架空のApple識別子を登録する。
これは認証前の開発用データであり、実際のユーザーとは結び付かない。
本番では内部ユーザーIDにもUUIDを生成する。`dev-user` は開発時だけの固定マーカー。
このSQLはローカルでも検証できるが、本番D1での実行を代行したものではない。

## 列の意味とAPI実装時の契約

### ユーザー

`users` はCloudflare側のアカウント台帳であり、商品・購入先の所有者を管理する。

- `id`: アプリ内部で生成する不変のユーザーUUID。Appleの識別子やFirebase UIDを直接使用しない。
- `apple_sub`: サーバーで検証済みのApple ID tokenに含まれる `sub`。
  同じAppleユーザーに複数の内部アカウントを作らないため、一意制約を付ける。
  最初はAppleログインのみを想定するため必須。メールアドレスやパスワード、氏名は保存しない。
- `created_at` / `updated_at`: アカウントの作成・更新日時のUNIXミリ秒。
- `deleted_at`: 利用停止・削除処理中の日時。通常のログイン・APIアクセスでは未設定であることを確認する。

認証APIはApple ID tokenの署名・issuer・許可したaudience・期限・nonceを検証し、
検証した `sub` に対応する有効な `users.id` を解決する。リクエスト本文に書かれた
`apple_sub` や `user_id` を本人確認として信用しない。iOSとWebのSign in with Appleは
同じAppグループに設定し、同じアカウントへ解決することを検証する。
Firebaseの手紙機能の認証とは分けて管理する。

`users` とは別に、認証APIの実装時にはログインセッション・OAuth認可コード・
アクセストークン・リフレッシュトークンの安全な管理が必要。
これらの保存方式は採用するOAuth実装に合わせて決め、`users` に平文トークンの列を足さない。
利用停止の日時だけではトークン失効や退会時の実データ削除は完了しない。

### 商品・購入先

- `id`: 商品・購入先のUUID。オフライン作成と取り消しでも同じIDを保つ。
- `user_id`: Cloudflare側で管理するアプリ内部のアカウントID。
  OAuthトークンを検証して取得し、すべての読み書きを本人のIDに限定する。
  `users.id` への外部キーにより、存在しないユーザーの商品・購入先は作成できない。
  この制約は利用停止の日時までは判定しないため、有効なユーザーかの確認はAPIでも行う。
- `note`: 個数・重さを含む自由入力メモ。専用の数量列は持たない。
- `place_id`: 購入先のUUID。`NULL` が「未指定」。複合外部キーにより、
  別ユーザーの購入先を参照できない。この制約だけでは読み取りの認可は行われない。
- `order_index`: 購入先を手動で並べ替えた順番。一意制約は付けない。
- `created_at`: 作成日時のUNIXミリ秒。既存商品の取り込み・復元時には元の作成日時を保つ。
- `updated_at`: サーバーが管理する最終更新日時のUNIXミリ秒。
- `version`: レコードの更新回数。APIが編集・削除・復元時に増やし、
  クライアントの前提バージョンと比較して競合を検出する。自動更新トリガーは設けない。
- `deleted_at`: 未削除は `NULL`、削除済みはサーバーが記録したUNIXミリ秒。
  購入時も論理削除し、通常の一覧では除外する。購入履歴の画面を作るための列ではない。

商品名の重複は許可する。購入先名の重複判定はアプリと同じ大文字小文字・文字幅の扱いを
API実装時に設計する。SQLiteの `NOCASE` だけではSwiftの文字幅を考慮した比較と一致しない。

購入先の論理削除は、参照している商品の `place_id` を `NULL` に変更し、
各商品の `version` / `updated_at` も更新してから、購入先の削除日時を記録する。
WorkersのD1 `batch()` でまとめて保存する。新規商品・編集時は購入先が未削除であることも確認する。
外部キーは論理削除を判定しない。物理削除は `RESTRICT` とし、参照がある購入先の削除による
商品の巻き込みを防ぐ。後日の削除記録整理では、論理削除済み商品からの参照も確認する。

この3表だけで差分同期は完成しない。同じ更新日時やページングによる取りこぼしを避けるため、
同期実装時に単調増加する変更番号を持つ変更ログとカーソルを追加する。
`updated_at > 前回の時刻` だけを確実な同期として使用しない。

初期SQLの `IF NOT EXISTS` は再実行時に既存テーブルを保持するが、定義の変更は適用しない。
Workersプロジェクトを作った後は、初期状態を確認したうえでこのSQLを最初のマイグレーションに
取り込み、以降のスキーマ変更をWranglerのマイグレーションで管理する。

## 公式資料

- [D1の開始手順（コンソールでのSQL実行）](https://developers.cloudflare.com/d1/get-started/)
- [D1の外部キー](https://developers.cloudflare.com/d1/sql-api/foreign-keys/)
- [D1のマイグレーション](https://developers.cloudflare.com/d1/reference/migrations/)
- [Sign in with Appleのユーザー認証](https://developer.apple.com/documentation/signinwithapple/authenticating-users-with-sign-in-with-apple)
