# 大切な人への手紙 - セキュリティ監査レポート

**監査日**: 2025-12-13
**対象バージョン**: v1.7
**監査者**: 外部AI（セキュリティレビュー）
**ステータス**: 対応済み（#5の署名検証のみリスク評価のうえ見送り） — 2026-06-12 更新

## 対応状況サマリ（2026-06-12）

| # | 指摘 | 状況 |
|---|------|------|
| 1 | pairings / inviteLinks ルール | ✅ 対応済み。inviteLinks は作成者のみ書き込み可。pairings は**クライアント書き込みを全面禁止**し、ペアリング作成を Cloud Functions（onFriendRequestCreated / onFriendRequestAccepted / onPairingDeleted）に移管。公開鍵は invite/request のコピーではなく users/{uid}.publicKey（正本）から取得 |
| 2 | letters 作成の senderId 未検証 | ✅ 対応済み。create に senderId == auth.uid + 型検証 + 写真5枚上限。update は受信者の開封操作（status/openedAt）のみに制限 |
| 3 | Storage ルール | ✅ 対応済み。letters/{letterId}/ 配下のみ、read/delete は Firestore の送受信者照合、create はファイル名パターン + 20MB + contentType 制限（写真は手紙ドキュメントより先にアップロードされるため存在チェックは不可） |
| 4 | サインアウト時の鍵未削除 | ✅ 対応済み（選択制）。鍵は iCloud キーチェーン同期のため無条件削除は他デバイスの未開封手紙を読めなくする恐れがあり、サインアウト時に「暗号鍵も削除」を警告つきで選択させる方式を採用 |
| 5 | 公開鍵・メッセージの真正性 | ⚠️ 一部対応 + **見送り（リスク評価済み）**。鍵注入経路は #1 の対応で遮断済み。送信者署名・鍵フィンガープリント照合は、残る脅威が「Firebase アカウント自体の乗っ取り・運営者・Google」に限られること、署名導入は手紙データ形式の互換性を壊すリスクがあること、フィンガープリント照合は自動テスト不能で QA 負担が大きいことから、現在の利用規模（開発者+知人）では見送りと判断（2026-06-12） |
| 6 | 添付 URL 検証なし | ✅ 対応済み。https + Firebase Storage ドメインのホワイトリスト + 30MB 上限 |

追加で対応した監査対象外の問題: encryptedLetters 旧コレクションの全開放ルールを撤去（全履歴で参照ゼロを確認）、friendRequests の作成者検証と status 限定 update、reports の reporterId 検証、stats のインクリメント限定化、Cloud Functions のクエリ limit 付与。

---

---

## 概要

「大切な人への手紙」機能のセキュリティ監査で、複数の脆弱性が指摘された。
本ドキュメントは指摘事項と対応方針をまとめたものである。

---

## 🔴 高リスク（Critical）

### 1. Firestoreルールが緩すぎる（ペアリング/招待リンク）

**指摘箇所**: `firestore.rules:10`, `firestore.rules:15`

**問題**:
- `pairings` と `inviteLinks` コレクションが認証済みユーザーなら誰でも読み書き可能
- 攻撃者が招待ドキュメントの `userId` や `userPublicKey` を書き換え可能

**攻撃シナリオ**:
1. 被害者が招待リンクを発行
2. 攻撃者がFirestoreコンソール等でドキュメントを書き換え
3. 公開鍵を攻撃者のものに差し替え
4. リンクを踏んだ友達は「攻撃者」とペアリング
5. 以後の手紙は攻撃者が復号可能

**対策案**:
```javascript
// inviteLinks: 作成者のみ書き込み可能
match /inviteLinks/{linkId} {
  allow read: if true;  // リンク検証のため必要
  allow create: if request.auth.uid == request.resource.data.userId;
  allow update, delete: if request.auth.uid == resource.data.userId;
}
```

---

### 2. 手紙作成にsenderIdチェックがない

**指摘箇所**: `firestore.rules:27`, `functions/src/index.ts:37`, `LetterReceivingService.swift:80`

**問題**:
- `letters` コレクションへの `create` 時に `senderId == request.auth.uid` の検証がない
- 認証済みなら誰でも任意の `senderId` で手紙を作成可能

**攻撃シナリオ**:
1. 攻撃者がFirestoreに直接書き込み
2. `senderId` を被害者のIDに偽装
3. Cloud Functionsが正規の手紙として配信
4. 受信者は「友達からの手紙」と信じてしまう

**対策案**:
```javascript
// letters: 送信者本人のみ作成可能
match /letters/{letterId} {
  allow create: if request.auth.uid == request.resource.data.senderId;
  allow read: if request.auth.uid == resource.data.senderId 
              || request.auth.uid == resource.data.recipientId;
  allow update: if request.auth.uid == resource.data.senderId;
  allow delete: if request.auth.uid == resource.data.senderId;
}
```

---

### 3. Storageルールがガバガバ

**指摘箇所**: `storage.rules:3`

**問題**:
- 認証済みなら全パスに対して read/write 可能
- 第三者が他人の添付写真を読み取り・上書き・削除可能

**現状のルール**:
```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /{allPaths=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

**対策案**:
```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /letters/{senderId}/{letterId}/{fileName} {
      // 送信者のみ書き込み可能
      allow write: if request.auth.uid == senderId;
      // 送信者と受信者のみ読み取り可能（受信者確認はFirestoreと連携必要）
      allow read: if request.auth != null;
    }
  }
}
```

---

## 🟠 中リスク（High）

### 4. サインアウトしても秘密鍵が削除されない

**指摘箇所**: `E2EEService.swift:83`, `AuthService.swift:342`

**問題**:
- サインアウト時にKeychainの秘密鍵が削除されない
- 端末共有時に別アカウントが旧アカウントの鍵を使用する可能性
- 再ログイン時に古い鍵が残っていると不整合が発生

**対策案**:
```swift
// AuthService.swift - signOut時
func signOut() {
    // 既存のサインアウト処理
    try? Auth.auth().signOut()
    
    // E2EE鍵を削除
    E2EEService.shared.deleteKeyPair()
}
```

---

### 5. 公開鍵・メッセージの真正性が未検証

**指摘箇所**: `PairingService.swift:143`, `PairingService.swift:223`, `E2EEService.swift:194`, `LetterReceivingService.swift:141`

**問題**:
- 招待で受け取る公開鍵がユーザーレコードと照合されていない
- 署名やAAD（追加認証データ）なしで暗号文を受理
- 中間者が鍵をすり替えたり偽手紙を生成可能

**対策案**:
1. 招待時に公開鍵をユーザードキュメントから取得して照合
2. 手紙に送信者の署名を追加、受信時に検証
3. 公開鍵の指紋確認UI（上級者向け）

---

### 6. 添付ダウンロードが任意URLを許容

**指摘箇所**: `LetterReceivingService.swift:225`

**問題**:
- 添付のダウンロードURLに検証がない
- サイズ制限やホワイトリストなし
- 悪意あるURLへ誘導される可能性

**対策案**:
```swift
// URLのホワイトリスト検証
func validateAttachmentURL(_ urlString: String) -> Bool {
    guard let url = URL(string: urlString),
          let host = url.host else { return false }
    
    let allowedHosts = [
        "firebasestorage.googleapis.com",
        "storage.googleapis.com"
    ]
    return allowedHosts.contains(host)
}
```

---

## 📋 対応優先度

| 優先度 | 項目 | 工数目安 | 影響 |
|--------|------|----------|------|
| 🔴 P0 | Firestoreルール強化 | 30分 | 全ユーザー |
| 🔴 P0 | Storageルール強化 | 30分 | 全ユーザー |
| 🔴 P0 | letters作成時のsenderIdチェック | 15分 | 全ユーザー |
| 🟠 P1 | サインアウト時の鍵削除 | 15分 | 端末共有者 |
| 🟠 P1 | 添付URL検証 | 15分 | 全ユーザー |
| 🟡 P2 | 署名検証の実装 | 数時間 | 高度な攻撃対策 |

---

## 疑問点・検討事項

1. **招待リンクのread権限**: 誰でも読める必要があるか？リンクIDを知っている人のみで十分では？
2. **Storageの受信者確認**: Firestoreとの連携が必要だが、どう実装するか？
3. **署名検証の複雑さ**: E2EEに加えて署名まで必要か？実装コストは？
4. **既存ユーザーへの影響**: ルール変更による既存データへの影響は？

---

## 参考ファイル

- `firestore.rules` - Firestoreセキュリティルール
- `storage.rules` - Storageセキュリティルール
- `functions/src/index.ts` - Cloud Functions
- `lifelog/Services/E2EEService.swift` - 暗号化サービス
- `lifelog/Services/PairingService.swift` - ペアリングサービス
- `lifelog/Services/LetterSendingService.swift` - 送信サービス
- `lifelog/Services/LetterReceivingService.swift` - 受信サービス
- `lifelog/Services/AuthService.swift` - 認証サービス
