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
import { onDocumentCreated } from "firebase-functions/v2/firestore";
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
    const fixedDeliveryLetters = await db.collection("letters")
      .where("status", "==", "pending")
      .where("deliveryCondition", "==", "fixed")
      .where("deliveryDate", "<=", Timestamp.fromDate(now))
      .get();

    for (const doc of fixedDeliveryLetters.docs) {
      await deliverLetter(doc.id, doc.data());
    }

    // 2. ランダム配信の手紙をチェック（scheduled状態のもの）
    const scheduledLetters = await db.collection("letters")
      .where("status", "==", "scheduled")
      .where("scheduledDeliveryDate", "<=", Timestamp.fromDate(now))
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
  const pendingLetters = await db.collection("letters")
    .where("senderId", "==", senderId)
    .where("recipientId", "==", recipientId)
    .where("status", "in", ["pending", "scheduled", "delivered"])
    .get();

  if (pendingLetters.size > 5) {
    // 5通を超えている → この手紙を削除
    await event.data?.ref.delete();
    logger.warn(`未開封上限超過のため削除: ${event.params.letterId}`);
  }
});

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
