/**
 * 大切な人への手紙 - Cloud Functions
 *
 * 機能:
 * 1. 配信判定（定期実行）
 * 2. 最終ログインチェック
 * 3. プッシュ通知送信
 * 4. 未開封上限チェック
 */

import { setGlobalOptions } from "firebase-functions/v2";
import { onSchedule } from "firebase-functions/v2/scheduler";
import {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentDeleted,
} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import { initializeApp, applicationDefault } from "firebase-admin/app";
import { getFirestore, Timestamp, FieldValue } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";

// Initialize Firebase Admin
initializeApp({
  credential: applicationDefault(),
});

const db = getFirestore();

// Global options for cost control
setGlobalOptions({ maxInstances: 10 });

// ============================================================
// 配信判定（毎分実行）
// ============================================================

/**
 * 配信予定の手紙をチェックして配信する
 * 毎分実行
 */
export const checkDelivery = onSchedule("every 1 minutes", async () => {
  logger.info("配信チェック開始");

  const now = new Date();

  try {
    // 1. 固定日時配信の手紙をチェック
    // limit は不正な大量作成によるコスト爆発のガード。毎分実行なので
    // あふれた分は次回の実行で処理される。
    const fixedDeliveryLetters = await db.collection("letters")
      .where("status", "==", "pending")
      .where("deliveryCondition", "==", "fixed")
      .where("deliveryDate", "<=", Timestamp.fromDate(now))
      .limit(200)
      .get();

    for (const doc of fixedDeliveryLetters.docs) {
      await deliverLetter(doc.id, doc.data());
    }

    // 2. ランダム配信の手紙をチェック（scheduled状態のもの）
    const scheduledLetters = await db.collection("letters")
      .where("status", "==", "scheduled")
      .where("scheduledDeliveryDate", "<=", Timestamp.fromDate(now))
      .limit(200)
      .get();

    for (const doc of scheduledLetters.docs) {
      await deliverLetter(doc.id, doc.data());
    }

    logger.info(`配信チェック完了: 固定=${fixedDeliveryLetters.size}, 予約=${scheduledLetters.size}`);
  } catch (error) {
    logger.error("配信チェックエラー", error);
  }
});

// ============================================================
// ランダム配信のスケジューリング
// ============================================================

/**
 * 新しい手紙が作成されたらランダム配信日時を決定
 */
export const scheduleRandomDelivery = onDocumentCreated("letters/{letterId}", async (event) => {
  const data = event.data?.data();
  if (!data) return;

  // ランダム配信の場合のみ
  if (data.deliveryCondition !== "random") return;
  // クライアント側で日時確定済みのデータはそのまま使う
  if (data.status !== "pending" || data.scheduledDeliveryDate) return;

  const startDate = data.randomStartDate?.toDate() || new Date(Date.now() + 24 * 60 * 60 * 1000);
  const endDate = data.randomEndDate?.toDate() || new Date(Date.now() + 3 * 365 * 24 * 60 * 60 * 1000);

  // ランダムな配信日時を計算
  const startTime = startDate.getTime();
  const endTime = endDate.getTime();
  const randomTime = startTime + Math.random() * (endTime - startTime);
  const scheduledDate = new Date(randomTime);

  // 更新
  await event.data?.ref.update({
    scheduledDeliveryDate: Timestamp.fromDate(scheduledDate),
    status: "scheduled",
  });

  logger.info(`ランダム配信をスケジュール: ${event.params.letterId} -> ${scheduledDate.toISOString()}`);
});

// ============================================================
// 最終ログインチェック（1時間ごと）
// ============================================================

/**
 * 最終ログイン配信の手紙をチェック
 * 1時間ごとに実行
 */
export const checkLastLoginDelivery = onSchedule("every 60 minutes", async () => {
  logger.info("最終ログインチェック開始");

  const now = new Date();

  try {
    // 最終ログイン配信の手紙を取得
    const lastLoginLetters = await db.collection("letters")
      .where("status", "==", "pending")
      .where("deliveryCondition", "==", "lastLogin")
      .limit(200)
      .get();

    for (const doc of lastLoginLetters.docs) {
      const data = doc.data();
      const senderId = data.senderId;
      const lastLoginDays = data.lastLoginDays || 7;

      // 送信者の最終ログイン日時を取得
      const userDoc = await db.collection("users").doc(senderId).get();
      const userData = userDoc.data();
      const lastLoginAt = userData?.lastLoginAt?.toDate();

      if (!lastLoginAt) continue;

      // 最終ログインからの経過日数を計算
      const daysSinceLogin = Math.floor((now.getTime() - lastLoginAt.getTime()) / (24 * 60 * 60 * 1000));

      // 警告日（配信2日前）
      const warningDays = lastLoginDays - 2;

      // 前回の警告送信日時（ユーザーがログインしたら無効化）
      const warningSentAt = data.warningSentAt?.toDate();
      const shouldSendWarning = !warningSentAt || warningSentAt < lastLoginAt;

      if (daysSinceLogin >= lastLoginDays) {
        // 配信日数に達した → 配信
        await deliverLetter(doc.id, data);
        logger.info(`最終ログイン配信実行: ${doc.id} (${daysSinceLogin}日経過)`);
      } else if (daysSinceLogin >= warningDays && shouldSendWarning) {
        // 警告期間に入った → 通知を送る（前回ログイン以降なら再送可能）
        await sendDeliveryWarning(senderId, doc.id, lastLoginDays - daysSinceLogin);
        await doc.ref.update({ warningSentAt: Timestamp.now() });
        logger.info(`最終ログイン警告送信: ${doc.id} (残り${lastLoginDays - daysSinceLogin}日)`);
      }
    }

    logger.info(`最終ログインチェック完了: ${lastLoginLetters.size}件`);
  } catch (error) {
    logger.error("最終ログインチェックエラー", error);
  }
});

// ============================================================
// 未開封上限チェック
// ============================================================

/**
 * 新しい手紙作成時に未開封上限をチェック
 */
export const validatePendingLimit = onDocumentCreated("letters/{letterId}", async (event) => {
  const data = event.data?.data();
  if (!data) return;

  const senderId = data.senderId;
  const recipientId = data.recipientId;

  // 同じ送信者→受信者の未開封手紙数をチェック
  // (5通超かどうかだけ分かればよいので limit で読み取り数を抑える)
  const pendingLetters = await db.collection("letters")
    .where("senderId", "==", senderId)
    .where("recipientId", "==", recipientId)
    .where("status", "in", ["pending", "scheduled", "delivered"])
    .limit(10)
    .get();

  if (pendingLetters.size > 5) {
    // 5通を超えている → この手紙を削除
    await event.data?.ref.delete();
    logger.warn(`未開封上限超過のため削除: ${event.params.letterId}`);
  }
});

// ============================================================
// ペアリング作成（サーバーサイド）
// ============================================================
// pairings はクライアントから書き込み禁止(firestore.rules)。
// 公開鍵をinviteLinks/friendRequestsのコピーではなく users コレクション
// (正本)から取得することで、偽の公開鍵を友達リストに注入して手紙を
// 傍受する攻撃を防ぐ。

/**
 * 招待リンク経由の即時友達追加。
 * クライアントは source == "inviteLink" の friendRequest を作成し、
 * この関数がリンクを検証して双方向ペアリングを作成、status を
 * accepted / rejected に更新する。クライアントは status を待つ。
 */
export const onFriendRequestCreated = onDocumentCreated("friendRequests/{requestId}", async (event) => {
  const data = event.data?.data();
  if (!data) return;
  // 手動承認フローは onFriendRequestAccepted が処理する
  if (data.source !== "inviteLink") return;

  const reject = async (reason: string) => {
    await event.data?.ref.update({ status: "rejected", rejectReason: reason });
    logger.warn(`招待リンク追加を拒否: ${event.params.requestId} (${reason})`);
  };

  const fromUserId = data.fromUserId;
  const toUserId = data.toUserId;
  const inviteLinkId = data.inviteLinkId;

  if (typeof inviteLinkId !== "string" || inviteLinkId.length === 0) {
    await reject("inviteLinkNotFound");
    return;
  }
  if (fromUserId === toUserId) {
    await reject("cannotAddSelf");
    return;
  }

  const linkDoc = await db.collection("inviteLinks").doc(inviteLinkId).get();
  const linkData = linkDoc.data();
  if (!linkDoc.exists || !linkData) {
    await reject("inviteLinkNotFound");
    return;
  }
  // リンクの所有者と宛先が一致しないリクエストは偽装とみなす
  if (linkData.userId !== toUserId) {
    await reject("inviteLinkNotFound");
    return;
  }
  const expiresAt = linkData.expiresAt?.toDate();
  if (!expiresAt || expiresAt < new Date()) {
    await reject("inviteLinkExpired");
    return;
  }

  const created = await createMutualPairing(fromUserId, toUserId);
  if (!created) {
    await reject("userNotFound");
    return;
  }
  await event.data?.ref.update({ status: "accepted" });
  logger.info(`招待リンクから友達追加: ${fromUserId} <-> ${toUserId}`);
});

/**
 * 友達リクエストの手動承認(受信者が status を accepted に更新)を検知し、
 * 双方向ペアリングを作成する。
 */
export const onFriendRequestAccepted = onDocumentUpdated("friendRequests/{requestId}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after) return;
  if (before.status !== "pending" || after.status !== "accepted") return;
  // 招待リンク即時追加は onFriendRequestCreated がペアリング作成済み
  if (after.source === "inviteLink") return;

  await createMutualPairing(after.fromUserId, after.toUserId);
});

/**
 * 友達解除: クライアントはルール上、自分の行しか削除できないため、
 * 相手側(鏡像)の行はここで削除する。鏡像削除で再発火しても
 * 対応する行は既に存在しないため安全に終了する。
 */
export const onPairingDeleted = onDocumentDeleted("pairings/{pairingId}", async (event) => {
  const data = event.data?.data();
  if (!data) return;

  const mirror = await db.collection("pairings")
    .where("userId", "==", data.friendId)
    .where("friendId", "==", data.userId)
    .get();
  for (const doc of mirror.docs) {
    await doc.ref.delete();
  }
  if (!mirror.empty) {
    logger.info(`鏡像ペアリングを削除: ${data.userId} <-> ${data.friendId}`);
  }
});

/**
 * 双方向の pairings ドキュメントを作成する(冪等)。
 * 表示名・絵文字・公開鍵は users コレクションの正本から取得する。
 */
async function createMutualPairing(userIdA: string, userIdB: string): Promise<boolean> {
  if (typeof userIdA !== "string" || typeof userIdB !== "string" ||
      userIdA.length === 0 || userIdB.length === 0) {
    return false;
  }

  const [userADoc, userBDoc] = await Promise.all([
    db.collection("users").doc(userIdA).get(),
    db.collection("users").doc(userIdB).get(),
  ]);
  const userA = userADoc.data();
  const userB = userBDoc.data();
  if (!userA || !userB || !userA.publicKey || !userB.publicKey) {
    logger.error(`ペアリング作成失敗: ユーザー情報が不完全 (${userIdA}, ${userIdB})`);
    return false;
  }

  const writeRow = async (ownerId: string, friendId: string, friend: FirebaseFirestore.DocumentData) => {
    // 冪等性: 既に友達関係がある側は書かない(重複行を防ぐ)
    const existing = await db.collection("pairings")
      .where("userId", "==", ownerId)
      .where("friendId", "==", friendId)
      .limit(1)
      .get();
    if (!existing.empty) return;

    await db.collection("pairings").doc().set({
      userId: ownerId,
      friendId: friendId,
      friendEmoji: friend.emoji || "😊",
      friendName: friend.displayName || "ユーザー",
      friendPublicKey: friend.publicKey,
      createdAt: FieldValue.serverTimestamp(),
    });
  };

  await Promise.all([
    writeRow(userIdA, userIdB, userB),
    writeRow(userIdB, userIdA, userA),
  ]);
  logger.info(`ペアリング作成: ${userIdA} <-> ${userIdB}`);
  return true;
}

// ============================================================
// ヘルパー関数
// ============================================================

/**
 * 手紙を配信する
 */
async function deliverLetter(letterId: string, data: FirebaseFirestore.DocumentData) {
  const recipientId = data.recipientId;
  const senderId = data.senderId;

  // ブロックチェック: 受信者が送信者をブロックしているか確認
  const recipientDoc = await db.collection("users").doc(recipientId).get();
  const blockedUsers = recipientDoc.data()?.blockedUsers || [];
  if (blockedUsers.includes(senderId)) {
    // ブロック中 → 配信せずに手紙を削除
    await db.collection("letters").doc(letterId).delete();
    logger.info(`ブロック中のため配信スキップ: ${letterId} (sender: ${senderId})`);
    return;
  }

  // ステータスを更新
  await db.collection("letters").doc(letterId).update({
    status: "delivered",
    deliveredAt: FieldValue.serverTimestamp(),
  });

  // プッシュ通知を送信（FCMトークンがあれば）
  await sendPushNotification(recipientId, letterId);

  logger.info(`手紙配信完了: ${letterId}`);
}

/**
 * プッシュ通知を送信
 */
async function sendPushNotification(userId: string, letterId: string) {
  try {
    // ユーザーのFCMトークンと通知設定を取得
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data();
    const fcmToken = userData?.fcmToken;
    const letterNotificationEnabled = userData?.letterNotificationEnabled ?? true;

    if (!fcmToken) {
      logger.info(`FCMトークンなし: ${userId}`);
      return;
    }

    // 通知設定がオフの場合はスキップ
    if (!letterNotificationEnabled) {
      logger.info(`手紙通知オフ: ${userId}`);
      return;
    }

    // 送信者情報を取得（手紙から）
    const letterDoc = await db.collection("letters").doc(letterId).get();
    const letterData = letterDoc.data();
    const senderId = letterData?.senderId;

    // 送信者名を取得
    const senderDoc = await db.collection("users").doc(senderId).get();
    const senderData = senderDoc.data();
    const senderName = senderData?.displayName || "誰か";
    const senderEmoji = senderData?.emoji || "💌";

    // プッシュ通知を送信
    // 未開封手紙数を取得してバッジに設定
    const unreadLetters = await db.collection("letters")
      .where("recipientId", "==", userId)
      .where("status", "==", "delivered")
      .get();
    const badgeCount = unreadLetters.size;

    const message = {
      token: fcmToken,
      notification: {
        title: `${senderEmoji} 手紙が届きました`,
        body: `${senderName}さんからの手紙です`,
      },
      data: {
        type: "letter",
        letterId: letterId,
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: badgeCount,
          },
        },
      },
    };

    await getMessaging().send(message);
    logger.info(`プッシュ通知を送信しました: ${userId}`);
  } catch (error) {
    logger.error(`プッシュ通知送信エラー: ${userId}`, error);
  }
}

/**
 * 最終ログイン配信の警告通知を送信
 */
async function sendDeliveryWarning(userId: string, letterId: string, daysRemaining: number) {
  try {
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data();
    const fcmToken = userData?.fcmToken;

    if (!fcmToken) {
      logger.info(`FCMトークンなし（警告）: ${userId}`);
      return;
    }

    const message = {
      token: fcmToken,
      notification: {
        title: "⚠️ 手紙が配信されます",
        body: `あと${daysRemaining}日ログインがないと、大切な人への手紙が配信されます`,
      },
      data: {
        type: "delivery_warning",
        letterId: letterId,
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
    };

    await getMessaging().send(message);
    logger.info(`警告通知を送信しました: ${userId}`);
  } catch (error) {
    logger.error(`警告通知送信エラー: ${userId}`, error);
  }
}
