# 未来への手紙 iCloud同期 仕様書

> ⚠️ **保留中**: App GroupとCloudKitの併用に追加設定が必要なため、一旦保留。

## 概要

「未来への手紙」機能のデータをiCloudで同期し、複数デバイス間で共有できるようにする。

---

## 技術方針

| 項目 | 内容 |
|------|------|
| フレームワーク | SwiftData + CloudKit |
| Container | `iCloud.com.inazumimakoto.lifelog` |
| 同期対象 | `SDLetter` モデル |

---

## ユーザー体験

| iCloud状態 | 挙動 |
|-----------|------|
| サインイン済み | 自動で同期 |
| 未サインイン | ローカルのみ保存 |

---

## 実装内容

1. `ModelConfiguration` に `cloudKitDatabase: .automatic` を追加
2. 設定画面にiCloud同期状態を表示（任意）

---

## 注意点

- 写真は `photoPaths` としてパスのみ保存
- 写真自体の同期は将来対応
