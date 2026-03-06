//
//  LetterReceivingService.swift
//  lifelog
//
//  大切な人への手紙 - 手紙受信サービス
//  E2EE暗号化された手紙を復号
//

import Foundation
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth

/// 手紙受信サービス
class LetterReceivingService {
    
    static let shared = LetterReceivingService()
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let e2eeService = E2EEService.shared
    
    private init() {}
    
    // MARK: - Models
    
    /// 復号された手紙
    struct DecryptedLetter: Identifiable {
        let id: String
        let senderId: String
        let senderEmoji: String
        let senderName: String
        let content: String
        let photos: [UIImage]
        let deliveredAt: Date
        let openedAt: Date?
        
        var isOpened: Bool {
            openedAt != nil
        }
    }
    
    /// 受信した手紙（未復号）
    struct ReceivedLetter: Identifiable, Equatable {
        let id: String
        let senderId: String
        let senderEmoji: String
        let senderName: String
        let encryptedContent: String
        let encryptedPhotoURLs: [String]
        let status: String
        let deliveredAt: Date
    }
    
    // MARK: - Errors
    
    enum ReceiveError: Error, LocalizedError {
        case notAuthenticated
        case letterNotFound
        case decryptionFailed
        case photoDownloadFailed
        
        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "ログインが必要です"
            case .letterNotFound:
                return "手紙が見つかりません"
            case .decryptionFailed:
                return "復号に失敗しました"
            case .photoDownloadFailed:
                return "写真のダウンロードに失敗しました"
            }
        }
    }
    
    // MARK: - Get Received Letters
    
    /// 受信した手紙一覧を取得（配信済みのみ）
    func getReceivedLetters() async throws -> [ReceivedLetter] {
        guard let currentUser = Auth.auth().currentUser else {
            throw ReceiveError.notAuthenticated
        }
        
        let snapshot = try await db.collection("letters")
            .whereField("recipientId", isEqualTo: currentUser.uid)
            .whereField("status", in: ["delivered", "opened"])
            .order(by: "deliveredAt", descending: true)
            .getDocuments()
        
        var letters: [ReceivedLetter] = []
        
        for doc in snapshot.documents {
            let data = doc.data()
            let senderId = data["senderId"] as? String ?? ""
            let senderProfile = await resolveSenderProfile(
                senderId: senderId,
                letterData: data,
                currentUserId: currentUser.uid
            )
            
            let letter = ReceivedLetter(
                id: doc.documentID,
                senderId: senderId,
                senderEmoji: senderProfile.emoji,
                senderName: senderProfile.name,
                encryptedContent: data["encryptedContent"] as? String ?? "",
                encryptedPhotoURLs: data["encryptedPhotoURLs"] as? [String] ?? [],
                status: data["status"] as? String ?? "",
                deliveredAt: (data["deliveredAt"] as? Timestamp)?.dateValue() ?? Date()
            )
            
            letters.append(letter)
        }
        
        return letters
    }
    
    /// 未開封の手紙数を取得
    func getUnreadCount() async throws -> Int {
        guard let currentUser = Auth.auth().currentUser else {
            return 0
        }
        
        let snapshot = try await db.collection("letters")
            .whereField("recipientId", isEqualTo: currentUser.uid)
            .whereField("status", isEqualTo: "delivered")
            .getDocuments()
        
        return snapshot.documents.count
    }
    
    // MARK: - Open Letter
    
    /// 手紙を開封して復号
    func openLetter(letterId: String) async throws -> DecryptedLetter {
        guard let currentUser = Auth.auth().currentUser else {
            throw ReceiveError.notAuthenticated
        }
        
        // 手紙データを取得
        let letterDoc = try await db.collection("letters").document(letterId).getDocument()
        
        guard let data = letterDoc.data() else {
            throw ReceiveError.letterNotFound
        }
        
        // 権限チェック
        guard data["recipientId"] as? String == currentUser.uid else {
            throw ReceiveError.letterNotFound
        }
        
        let encryptedContent = data["encryptedContent"] as? String ?? ""
        let encryptedPhotoURLs = data["encryptedPhotoURLs"] as? [String] ?? []
        let senderId = data["senderId"] as? String ?? ""
        let senderProfile = await resolveSenderProfile(
            senderId: senderId,
            letterData: data,
            currentUserId: currentUser.uid
        )
        
        // 本文を復号
        let decryptedContent: String
        do {
            let encryptedMessage = try e2eeService.deserializeEncryptedMessage(encryptedContent)
            decryptedContent = try e2eeService.decrypt(encryptedMessage: encryptedMessage)
        } catch {
            throw ReceiveError.decryptionFailed
        }
        
        // 写真を復号
        var decryptedPhotos: [UIImage] = []
        for url in encryptedPhotoURLs {
            if let photo = try? await downloadAndDecryptPhoto(url: url) {
                decryptedPhotos.append(photo)
            }
        }
        
        // ステータスを開封済みに更新
        try await db.collection("letters").document(letterId).updateData([
            "status": "opened",
            "openedAt": FieldValue.serverTimestamp()
        ])
        
        // アプリアイコンのバッジを更新
        await updateBadgeCount()
        
        let deliveredAt = (data["deliveredAt"] as? Timestamp)?.dateValue() ?? Date()
        
        return DecryptedLetter(
            id: letterId,
            senderId: senderId,
            senderEmoji: senderProfile.emoji,
            senderName: senderProfile.name,
            content: decryptedContent,
            photos: decryptedPhotos,
            deliveredAt: deliveredAt,
            openedAt: Date()
        )
    }
    
    /// 手紙メタデータまたはペアリング情報から送信者表示名を解決
    private func resolveSenderProfile(
        senderId: String,
        letterData: [String: Any],
        currentUserId: String
    ) async -> (emoji: String, name: String) {
        // 新しい手紙はメタデータに送信者情報を保持する
        if let senderName = normalizedDisplayName(letterData["senderName"] as? String) {
            let senderEmoji = normalizedEmoji(letterData["senderEmoji"] as? String) ?? "😊"
            return (senderEmoji, senderName)
        }
        
        // 既存データ向け: 自分のpairingsから相手情報を引く
        if let pairingSnapshot = try? await db.collection("pairings")
            .whereField("userId", isEqualTo: currentUserId)
            .whereField("friendId", isEqualTo: senderId)
            .limit(to: 1)
            .getDocuments(),
           let pairingData = pairingSnapshot.documents.first?.data(),
           let senderName = normalizedDisplayName(pairingData["friendName"] as? String) {
            let senderEmoji = normalizedEmoji(pairingData["friendEmoji"] as? String) ?? "😊"
            return (senderEmoji, senderName)
        }
        
        // 送信者＝自分の場合のみusersを直接参照できる
        if senderId == currentUserId,
           let senderDoc = try? await db.collection("users").document(senderId).getDocument(),
           let senderData = senderDoc.data(),
           let senderName = normalizedDisplayName(senderData["displayName"] as? String) {
            let senderEmoji = normalizedEmoji(senderData["emoji"] as? String) ?? "😊"
            return (senderEmoji, senderName)
        }
        
        return ("😊", "送信者")
    }
    
    private func normalizedDisplayName(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    private func normalizedEmoji(_ emoji: String?) -> String? {
        guard let emoji else { return nil }
        let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    /// アプリアイコンのバッジカウントを更新
    @MainActor
    private func updateBadgeCount() async {
        do {
            let unreadCount = try await getUnreadCount()
            try await UNUserNotificationCenter.current().setBadgeCount(unreadCount)
        } catch {
            print("バッジ更新エラー: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Download and Decrypt Photo
    
    /// 暗号化された写真をダウンロードして復号
    private func downloadAndDecryptPhoto(url: String) async throws -> UIImage {
        guard let downloadURL = URL(string: url) else {
            throw ReceiveError.photoDownloadFailed
        }
        
        // ダウンロード
        let (data, _) = try await URLSession.shared.data(from: downloadURL)
        
        // Base64文字列として解釈
        guard let serialized = String(data: data, encoding: .utf8) else {
            throw ReceiveError.photoDownloadFailed
        }
        
        // 復号
        let encryptedMessage = try e2eeService.deserializeEncryptedMessage(serialized)
        let decryptedData = try e2eeService.decryptData(encryptedMessage: encryptedMessage)
        
        // UIImageに変換
        guard let image = UIImage(data: decryptedData) else {
            throw ReceiveError.photoDownloadFailed
        }
        
        return image
    }
    
    // MARK: - Delete Letter
    
    /// 手紙を削除（開封後のみ）
    func deleteLetter(letterId: String) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw ReceiveError.notAuthenticated
        }
        
        // 権限チェック
        let letterDoc = try await db.collection("letters").document(letterId).getDocument()
        guard let data = letterDoc.data(),
              data["recipientId"] as? String == currentUser.uid else {
            throw ReceiveError.letterNotFound
        }
        
        // 写真を削除
        let photoURLs = data["encryptedPhotoURLs"] as? [String] ?? []
        for url in photoURLs {
            if let storageRef = try? storage.reference(forURL: url) {
                try? await storageRef.delete()
            }
        }
        
        // ドキュメントを削除
        try await db.collection("letters").document(letterId).delete()
    }
}
