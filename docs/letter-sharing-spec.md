# 大切な人への手紙 仕様書（E2EE版）

## 概要

lifelogユーザー同士で手紙を送り合える機能。
**エンドツーエンド暗号化（E2EE）** により、運営も手紙の内容を見ることができない。

---

## コンセプト

> **「いつか届く」サプライズの共有 - 誰にも読まれない安心感**

- 日時指定で届く手紙（誕生日、記念日など）
- ランダムな時間に届く手紙（日常のサプライズ）
- 長期間アプリを開かなかった時に届く手紙（レガシーモード）
- **運営もメッセージ内容を見ることができない**

---

## 技術方針

### 採用技術

| 項目 | 技術 |
|------|------|
| 認証 | Sign in with Apple + Firebase Auth |
| 暗号化 | CryptoKit（Apple純正） |
| 鍵交換 | ECDH (P-256) |
| 本文暗号化 | AES-GCM |
| 鍵保存 | KeyChain (iCloud同期) |
| サーバー | Firebase (Firestore + Cloud Functions + FCM) |

### 前提条件

- **Sign in with Apple** でサインイン済み
- 既存機能（日記など）はサインイン不要のまま

### アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│                        Firebase                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ 公開鍵Store │  │ 暗号化手紙  │  │ メタデータ(配信条件)│  │
│  │   (平文)    │  │ (暗号化済み) │  │      (平文)        │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
         ↑                 ↑                 ↑
    公開鍵を登録      暗号文を保存      メタデータ更新
         │                 │                 │
┌────────┴────────┐ ┌──────┴──────────────────┴──┐
│   送信者アプリ   │ │       受信者アプリ          │
│  ┌───────────┐  │ │  ┌───────────┐              │
│  │ 秘密鍵    │  │ │  │ 秘密鍵    │ → 復号      │
│  │ (KeyChain)│  │ │  │ (KeyChain)│              │
│  └───────────┘  │ │  └───────────┘              │
└─────────────────┘ └─────────────────────────────┘
```

---

## サーバーが保持するデータ

### 📖 平文（運営が見れる）

| データ | 目的 |
|--------|------|
| 公開鍵 | 暗号化のため（公開しても安全） |
| 送信者ID | 誰が送ったか |
| 受信者ID | 誰に届けるか |
| 配信条件（日時/非アクティブ日数） | 配信判定のため |
| 手紙のステータス | pending/delivered/deleted |
| 作成日時 | 監査・開示用 |

### 🔒 暗号化（運営が見れない）

| データ | 説明 |
|--------|------|
| 手紙本文 | AES-GCM で暗号化 |
| 添付写真 | AES-GCM で暗号化 |
| 暗号化されたAESキー | 受信者の公開鍵で暗号化 |

---

## 暗号化フロー

### 1. 鍵ペア生成（初回起動時）

```swift
// CryptoKit で ECDH 鍵ペアを生成
let privateKey = P256.KeyAgreement.PrivateKey()
let publicKey = privateKey.publicKey

// 秘密鍵を KeyChain に保存（iCloud同期有効）
saveToKeychain(privateKey, synchronizable: true)

// 公開鍵を Firebase に登録
uploadPublicKey(publicKey)
```

### 2. 手紙の暗号化（送信時）

```swift
// 1. 使い捨て AES キーを生成
let aesKey = SymmetricKey(size: .bits256)

// 2. 本文を AES-GCM で暗号化
let encryptedContent = try AES.GCM.seal(content, using: aesKey)

// 3. 受信者の公開鍵を取得
let recipientPublicKey = fetchPublicKey(recipientId)

// 4. ECDH で共有シークレットを導出
let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: recipientPublicKey)

// 5. 共有シークレットで AES キーを暗号化
let derivedKey = sharedSecret.hkdfDerivedSymmetricKey(...)
let encryptedAESKey = try AES.GCM.seal(aesKey, using: derivedKey)

// 6. Firebase に保存
uploadEncryptedLetter(encryptedContent, encryptedAESKey, metadata)
```

### 3. 手紙の復号（受信時）

```swift
// 1. 暗号化された手紙を取得
let encryptedLetter = downloadLetter(letterId)

// 2. 自分の秘密鍵を KeyChain から取得
let privateKey = loadFromKeychain()

// 3. 送信者の公開鍵で共有シークレットを導出
let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: senderPublicKey)

// 4. AES キーを復号
let derivedKey = sharedSecret.hkdfDerivedSymmetricKey(...)
let aesKey = try AES.GCM.open(encryptedAESKey, using: derivedKey)

// 5. 本文を復号
let content = try AES.GCM.open(encryptedContent, using: aesKey)

// 6. サーバーから削除
deleteLetter(letterId)
```

---

## プロフィール設定

### 初回設定画面

```
┌─────────────────────────────────┐
│ プロフィール設定                │
├─────────────────────────────────┤
│                                 │
│        [ 😊 ]                   │
│   タップして変更                │
│                                 │
│ 表示名:                         │
│ [ たなか____________ ]          │
│                                 │
│ ※ 友達に表示される名前です      │
│                                 │
│      [ 保存 ]                   │
│                                 │
└─────────────────────────────────┘
```

### 仕様

| 項目 | 仕様 |
|------|------|
| 絵文字アイコン | 全ての絵文字から選択可能 |
| 表示名 | 初期値はSign in with Appleの名前、自由に編集可能 |
| 変更 | 設定画面からいつでも変更可能 |

---

## Deep Link（招待リンク）

### 仕組み

```
Firebase Hosting でウェブページを公開
  ↓
https://lifelog-xxxxx.web.app/invite/ABC123
  ↓
LINEでタップ
  ↓
アプリがインストール済み → アプリ起動 → 招待画面
アプリ未インストール → App Store → インストール後に招待画面
```

### 必要な設定

| 項目 | 内容 |
|------|------|
| Firebase Hosting | 無料で使用可能 |
| Universal Links | Xcode で Associated Domains 設定 |
| apple-app-site-association | Firebase Hosting に配置 |

---

## 写真の仕様

| 項目 | 仕様 |
|------|------|
| 最大枚数 | 5枚 |
| サイズ制限 | 1枚あたり **10MB以下** |
| 暗号化 | AES-GCM で暗号化して保存 |

---

## ユーザーフロー

### 1. 友達登録（ペアリング）

#### 招待する側

```
┌─────────────────────────────────┐
│ 友達を招待                      │
├─────────────────────────────────┤
│                                 │
│ 招待リンクを作成しました        │
│                                 │
│ [ LINEで送る ] [ コピー ]       │
│                                 │
│ リンクは24時間有効です          │
│                                 │
└─────────────────────────────────┘
```

#### 招待される側（Deep Link経由）

```
┌─────────────────────────────────┐
│ 友達申請                        │
├─────────────────────────────────┤
│                                 │
│ 田中さん があなたと手紙を       │
│ 交換したいと思っています        │
│                                 │
│ [ 拒否 ] [ 承認 ]               │
│                                 │
└─────────────────────────────────┘
```

**裏側の処理**:
1. 承認すると公開鍵をサーバーに登録
2. お互いの公開鍵を交換
3. ペアリング完了

### 2. 手紙を書く

```
┌─────────────────────────────────┐
│ 新しい手紙を書く                │
├─────────────────────────────────┤
│                                 │
│ 宛先:                           │
│ [ 田中さん ▼ ]                  │
│                                 │
│ メッセージ:                     │
│ ┌─────────────────────────────┐ │
│ │                             │ │
│ │  いつもありがとう...         │ │
│ │                             │ │
│ └─────────────────────────────┘ │
│                                 │
│ 📸 写真を追加（最大5枚）         │
│ [＋]                            │
│                                 │
│ 届ける条件:                     │
│ ○ 日時を指定                   │
│ ○ ランダム                     │
│ ● 長期間アプリを開かなかったら  │
│                                 │
│ 🔒 この手紙はE2E暗号化されます   │
│    運営も内容を見ることはできません│
│                                 │
│ ⚠️ 一度送信すると取り消せません  │
│                                 │
│      [ 送信する ]                │
└─────────────────────────────────┘
```

### 3. 手紙を受け取る

```
プッシュ通知: 「📬 田中さんから手紙が届きました」
  ↓
通知をタップ
  ↓
開封画面に直接遷移
  ↓
開封アニメーション
  ↓
手紙を表示（復号完了）
  ↓
サーバーから削除
```

---

## 重要な仕様

### 未開封手紙の上限

| 項目 | 仕様 |
|------|------|
| 上限数 | **5通/宛先** |
| 制限対象 | 同じ相手への未開封（pending）の手紙 |

```
送信前チェック:
未開封の手紙が5通ある
  ↓
「未開封の手紙が5通あります。相手が開封するまでお待ちください。」
  ↓
送信ボタン無効化
```

### 取り消し不可

```
手紙を送信
  ↓
サーバーに暗号化データが保存される
  ↓
取り消しボタンなし（郵便ポストに入れた手紙のイメージ）
```

### 友達管理UI（セッション管理）

```
┌─────────────────────────────────┐
│ 友達                            │
├─────────────────────────────────┤
│                                 │
│ 👤 田中さん                 ⋮   │
│                                 │
│ 👤 鈴木さん                 ⋮   │
│                                 │
│ [ + 友達を招待 ]                │
│                                 │
└─────────────────────────────────┘

⋮ をタップ → メニュー表示

┌─────────────────────┐
│ 🔗 セッション解除    │
│ 🚫 ブロック         │
└─────────────────────┘
```

※ 未開封数は表示しない（意識させないUX）
※ 上限到達時のみエラーメッセージで通知

### 友達削除（セッション解除）時の挙動

```
友達を削除
  ↓
確認ダイアログ「未開封の手紙は全て読めなくなります」
  ↓
鍵（セッション）を削除
  ↓
未開封の手紙は復号不可能に
  ↓
電子のゴミとして消滅
```

### 受信後のデータ削除

```
手紙をダウンロード＆復号
  ↓
サーバー上のデータを即時削除
  ↓
以降はローカル端末でのみ閲覧可能
```

---

## ブロック・通報機能（Apple審査対策）

### 手紙閲覧画面

```
┌─────────────────────────────────┐
│ 📬 田中さんからの手紙      ⋮   │  ← 右上に控えめに
├─────────────────────────────────┤
│                                 │
│ いつもありがとう。              │
│ あなたがいてくれて本当に        │
│ 幸せです。                      │
│                                 │
│ [添付写真]                      │
│                                 │
│ ───────────────────────        │
│ 2025年12月25日に届きました      │
│                                 │
└─────────────────────────────────┘

⋮ をタップ → メニュー

┌─────────────────┐
│ 🚨 通報        │
│ 🚫 ブロック    │
└─────────────────┘
```

### ブロック時の挙動

```
ブロックを選択
  ↓
確認ダイアログ「未開封の手紙は全て読めなくなります」
  ↓
セッション削除（鍵を破棄）
  ↓
未開封の手紙は復号不可能に
  ↓
相手からの新しい招待も拒否（blockedUsersリストに追加）
```

### 通報時の挙動

```
通報を選択
  ↓
理由を選択:
  ○ 不快・攻撃的なコンテンツ
  ○ スパム・迷惑行為
  ○ 個人情報の悪用
  ○ その他
  ↓
※ E2EEなので手紙の内容は送信しない
  ↓
メタデータのみ通報（送信者ID、日時、理由）
  ↓
運営が必要に応じて対応
```

### 通報後の選択肢

```
通報完了
  ↓
「このユーザーをブロックしますか？」
  ↓
[ いいえ ] [ ブロックする ]
```

---

## KeyChain と iCloud 同期

### 秘密鍵の保存

```swift
let query: [String: Any] = [
    kSecClass as String: kSecClassKey,
    kSecAttrApplicationTag as String: "com.lifelog.e2ee.privateKey",
    kSecValueRef as String: privateKey,
    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    kSecAttrSynchronizable as String: true  // iCloud同期有効
]
SecItemAdd(query as CFDictionary, nil)
```

### メリット

| シナリオ | 結果 |
|---------|------|
| アプリを削除して再インストール | ✅ 鍵が復活 |
| 機種変更（iCloudバックアップ） | ✅ 鍵が復活 |
| Apple IDからサインアウト | ❌ 鍵を失う |

---

## Firestore データ構造

```typescript
// ユーザー
interface User {
  id: string;
  emoji: string;             // プロフィール絵文字 "😊"
  displayName: string;       // 表示名（編集可能）
  publicKey: string;         // 公開鍵（Base64エンコード）
  fcmToken: string;
  lastActiveAt: Timestamp;
  blockedUsers: string[];    // ブロックしたユーザーIDリスト
  createdAt: Timestamp;
}

// ペアリング
interface Pairing {
  id: string;
  userId: string;
  pairedUserId: string;
  pairedUserName: string;
  pendingLetterCount: number;  // 未開封手紙数（上限5チェック用）
  createdAt: Timestamp;
}

// 招待リンク
interface InviteLink {
  id: string;
  userId: string;
  userName: string;
  expiresAt: Timestamp;  // 24時間後
}

// 暗号化手紙
interface EncryptedLetter {
  id: string;
  senderId: string;
  senderName: string;            // メタデータ（平文）
  recipientId: string;
  encryptedContent: string;       // 暗号化された本文（Base64）
  encryptedAESKey: string;        // 暗号化されたAESキー（Base64）
  encryptedPhotoUrls: string[];   // 暗号化された写真（Base64）
  
  // メタデータ（平文 - 開示用）
  deliveryMode: 'scheduled' | 'random' | 'legacy';
  scheduledDate?: Timestamp;
  randomStartDate?: Timestamp;
  randomEndDate?: Timestamp;
  inactiveDays?: 30 | 60 | 90;
  
  status: 'pending' | 'delivered' | 'deleted';
  createdAt: Timestamp;
  deliveredAt?: Timestamp;
}

// 通報
interface Report {
  id: string;
  reporterId: string;
  reportedUserId: string;
  letterId: string;
  reason: string;        // 通報理由
  createdAt: Timestamp;
  // ※ 手紙の内容は含まない（E2EE）
}
```

---

## プッシュ通知

### 配信タイミング

| モード | 通知タイミング |
|--------|---------------|
| 日時指定 | 指定日時に通知 |
| ランダム | 計算された日時に通知 |
| レガシー | 送信者が非アクティブ + 条件達成時 |

### 通知内容

```
タイトル: 📬 手紙が届きました
本文: 田中さんから手紙が届いています
```

### 通知タップ時

```
通知をタップ
  ↓
アプリ起動
  ↓
該当の手紙の開封画面に直接遷移
  ↓
開封アニメーション → 復号 → 表示
```

---

## セキュリティまとめ

| 項目 | 対策 |
|------|------|
| **運営の閲覧** | ❌ 不可能（E2EE） |
| **通信傍受** | ❌ 不可能（TLS + E2EE） |
| **サーバー攻撃** | △ メタデータは流出の可能性（本文は安全） |
| **端末紛失** | △ 端末ロックで保護 |
| **鍵の紛失** | KeyChain + iCloud同期で復旧可能 |

---

## 実装タスク

### Phase 1: 準備 ✅

- [x] Firebase プロジェクト作成
- [x] Firestore 有効化
- [x] Firebase Auth 有効化（Sign in with Apple）
- [x] Firebase Storage 有効化
- [x] Cloud Messaging 有効化
- [x] **Firebase Hosting 有効化**
- [x] **apple-app-site-association 配置（Universal Links）**
- [x] iOS アプリを Firebase に登録
- [x] `GoogleService-Info.plist` をダウンロード
- [x] Xcode で Associated Domains 設定
- [x] Firebase SDK 追加（SPM）
- [x] 初期化コード追加（lifelogApp.swift）

### Phase 2: 暗号化基盤 ✅

- [x] CryptoKit でキーペア生成
- [x] KeyChain への保存・読み込み（iCloud同期有効）
- [x] ECDH 共有シークレット導出
- [x] AES-GCM 暗号化・復号

**作成ファイル:**
- `Services/E2EEService.swift`

### Phase 3: 認証・プロフィール ✅

- [x] Sign in with Apple の実装
- [x] Firebase Auth との連携
- [x] **プロフィール設定画面（絵文字+表示名）**
- [x] ユーザー情報の Firestore 保存
- [x] 設定画面からのナビゲーション追加

**作成ファイル:**
- `Services/AuthService.swift`
- `Views/LetterSharing/LetterSignInView.swift`
- `Views/LetterSharing/LetterProfileSetupView.swift`
- `Views/LetterSharing/LetterSharingView.swift`

### Phase 4: ペアリング ✅

- [x] 招待リンク生成（Firebase Hosting URL、24時間有効）
- [x] **Deep Link 処理（Universal Links）**
- [x] **App未インストール時のApp Store誘導**
- [x] 公開鍵の交換
- [x] ペアリングUI（友達一覧）
- [x] **承認式ペアリングフロー**
- [x] 友達削除機能

**作成ファイル:**
- `Services/PairingService.swift`
- `Services/DeepLinkHandler.swift`
- `Views/LetterSharing/InviteFriendView.swift`
- `Views/LetterSharing/FriendRequestsView.swift`

**仕様変更:**
- 承認式ペアリング → **即時ペアリング**（招待リンクを踏んで「友達に追加」で即座に友達に）
- リクエスト/承認プロセス不要

### Phase 5: 手紙機能

- [ ] 手紙作成UI（既存の「未来への手紙」UIを流用）
- [ ] 写真添付（10MB制限チェック）
- [ ] 暗号化して送信
- [ ] 配信条件設定（既存ロジック流用）
- [ ] **未開封上限5通チェック**

### Phase 6: 配信・受信

- [x] Cloud Functions: 配信判定 ✅ 実装済み
- [x] プッシュ通知送信 ✅ 実装済み（通知設定に連動）
- [x] 受信・復号処理 ✅ 実装済み
- [x] 開封画面遷移（既存の開封画面を流用）✅ 実装済み

### Phase 7: 安全機能

- [ ] **ブロック機能**
- [ ] **通報機能**
- [ ] **友達削除（セッション解除）** ✅ 実装済み
- [ ] **公開鍵フィンガープリント確認**（MITM対策）
- [ ] **送信者署名検証**（なりすまし防止）
- [ ] **リプレイ攻撃防止**（letterId+タイムスタンプ署名）
- [ ] **DoS防止**（Cloud Functionsでサーバーサイド検証）

### Phase 8: ローカル保存

- [x] 復号した手紙をローカルに保存 ✅ 実装済み
- [x] 手紙一覧表示（開封済みセクション）✅ 実装済み
- [ ] 手紙削除機能（UI未実装）
- [x] **サーバーからの削除（開封後、ローカル保存完了時に削除）** ✅ 実装済み

---

## 予想作業時間

| Phase | 作業時間 | 難易度 |
|-------|---------|--------|
| Phase 1: 準備 | 4-6時間 | ⭐⭐ |
| Phase 2: 暗号化基盤 | 8-12時間 | ⭐⭐⭐⭐⭐ |
| Phase 3: 認証・プロフィール | 4-6時間 | ⭐⭐⭐ |
| Phase 4: ペアリング | 8-10時間 | ⭐⭐⭐⭐ |
| Phase 5: 手紙機能 | 5-7時間 | ⭐⭐⭐ |
| Phase 6: 配信・受信 | 8-10時間 | ⭐⭐⭐⭐ |
| Phase 7: 安全機能 | 4-6時間 | ⭐⭐⭐ |
| Phase 8: ローカル保存 | 4-5時間 | ⭐⭐ |
| **合計** | **45-62時間** | |

---

## 将来の拡張案

1. **グループ手紙** - 複数人に同時送信
2. **動画サポート** - 短い動画の暗号化添付
3. **音声メッセージ** - 録音の暗号化添付
4. **Android対応** - Kotlin/Java で同等の暗号化実装

---

## 参考リンク

- [CryptoKit Documentation](https://developer.apple.com/documentation/cryptokit)
- [Keychain Services](https://developer.apple.com/documentation/security/keychain_services)
- [Universal Links](https://developer.apple.com/documentation/xcode/allowing-apps-and-websites-to-link-to-your-content)
- [Firebase Cloud Messaging](https://firebase.google.com/docs/cloud-messaging)
