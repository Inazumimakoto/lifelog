//
//  LetterSendingService.swift
//  lifelog
//
//  大切な人への手紙 - 手紙送信サービス
//  E2EE暗号化してFirestoreに保存
//

import Foundation
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth

/// 手紙送信サービス
class LetterSendingService {
    
    static let shared = LetterSendingService()
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let e2eeService = E2EEService.shared
    
    private init() {}
    
    // MARK: - Models
    
    /// 手紙の配信条件
    enum DeliveryCondition: String, Codable {
        case fixedDate = "fixed"          // 日時指定
        case random = "random"            // ランダム
        case lastLogin = "lastLogin"      // 最終ログイン
    }
    
    /// 暗号化された手紙（Firestore保存用）
    struct EncryptedLetter: Codable {
        let id: String
        let senderId: String
        let recipientId: String
        let encryptedContent: String       // 暗号化された本文（Base64）
        let encryptedPhotoURLs: [String]   // 暗号化された写真のStorage URL
        let deliveryCondition: DeliveryCondition
        let deliveryDate: Date?            // 固定日時の場合
        let randomStartDate: Date?         // ランダム開始日
        let randomEndDate: Date?           // ランダム終了日
        let lastLoginDays: Int?            // 最終ログイン日数
        let status: LetterStatus
        let createdAt: Date
        
        enum LetterStatus: String, Codable {
            case pending = "pending"       // 配信待ち
            case scheduled = "scheduled"   // 配信予定
            case delivered = "delivered"   // 配信済み
            case opened = "opened"         // 開封済み
        }
    }
    
    // MARK: - Errors
    
    enum SendError: Error, LocalizedError {
        case notAuthenticated
        case noRecipient
        case encryptionFailed
        case uploadFailed
        case firestoreFailed
        case tooManyPendingLetters
        
        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "ログインが必要です"
            case .noRecipient:
                return "送信先が指定されていません"
            case .encryptionFailed:
                return "暗号化に失敗しました"
            case .uploadFailed:
                return "写真のアップロードに失敗しました"
            case .firestoreFailed:
                return "手紙の保存に失敗しました"
            case .tooManyPendingLetters:
                return "未開封手紙が上限（5通）に達しています"
            }
        }
    }
    
    // MARK: - Send Letter
    
    /// 手紙を送信
    /// - Parameters:
    ///   - content: 手紙の本文
    ///   - photos: 添付写真
    ///   - recipient: 送信先の友達
    ///   - deliveryCondition: 配信条件
    ///   - deliveryDate: 固定配信日時
    ///   - randomStartDate: ランダム開始日
    ///   - randomEndDate: ランダム終了日
    ///   - lastLoginDays: 最終ログイン日数
    func sendLetter(
        content: String,
        photos: [UIImage],
        recipient: PairingService.Friend,
        deliveryCondition: DeliveryCondition,
        deliveryDate: Date? = nil,
        randomStartDate: Date? = nil,
        randomEndDate: Date? = nil,
        lastLoginDays: Int? = nil
    ) async throws {
        
        // 1. 認証チェック
        guard let currentUser = Auth.auth().currentUser else {
            throw SendError.notAuthenticated
        }
        
        // 2. 未開封上限チェック（5通）
        let pendingCount = try await getPendingLetterCount(
            senderId: currentUser.uid,
            recipientId: recipient.odic
        )
        if pendingCount >= 5 {
            throw SendError.tooManyPendingLetters
        }
        
        // 3. 本文をE2EE暗号化
        let encryptedMessage: E2EEService.EncryptedMessage
        do {
            encryptedMessage = try e2eeService.encrypt(
                message: content,
                recipientPublicKey: recipient.friendPublicKey
            )
        } catch {
            throw SendError.encryptionFailed
        }
        
        // 4. 暗号化メッセージをシリアライズ
        let encryptedContentBase64: String
        do {
            encryptedContentBase64 = try e2eeService.serializeEncryptedMessage(encryptedMessage)
        } catch {
            throw SendError.encryptionFailed
        }
        
        // 5. 写真を暗号化してアップロード
        let letterId = UUID().uuidString
        var encryptedPhotoURLs: [String] = []
        
        for (index, photo) in photos.enumerated() {
            let url = try await uploadEncryptedPhoto(
                photo: photo,
                letterId: letterId,
                photoIndex: index,
                recipientPublicKey: recipient.friendPublicKey
            )
            encryptedPhotoURLs.append(url)
        }
        
        // 6. Firestoreに保存
        let letterData: [String: Any] = [
            "senderId": currentUser.uid,
            "recipientId": recipient.odic,
            "encryptedContent": encryptedContentBase64,
            "encryptedPhotoURLs": encryptedPhotoURLs,
            "deliveryCondition": deliveryCondition.rawValue,
            "deliveryDate": deliveryDate.map { Timestamp(date: $0) } as Any,
            "randomStartDate": randomStartDate.map { Timestamp(date: $0) } as Any,
            "randomEndDate": randomEndDate.map { Timestamp(date: $0) } as Any,
            "lastLoginDays": lastLoginDays as Any,
            "status": EncryptedLetter.LetterStatus.pending.rawValue,
            "createdAt": Timestamp(date: Date())
        ]
        
        do {
            try await db.collection("letters").document(letterId).setData(letterData)
        } catch {
            throw SendError.firestoreFailed
        }
        
        print("✅ 手紙送信完了: \(letterId)")
    }
    
    // MARK: - Upload Encrypted Photo
    
    /// 写真を暗号化してFirebase Storageにアップロード
    private func uploadEncryptedPhoto(
        photo: UIImage,
        letterId: String,
        photoIndex: Int,
        recipientPublicKey: String
    ) async throws -> String {
        
        // 1. 写真をJPEGデータに変換
        guard let photoData = photo.jpegData(compressionQuality: 0.7) else {
            throw SendError.uploadFailed
        }
        
        // 2. E2EE暗号化
        let encryptedMessage: E2EEService.EncryptedMessage
        do {
            encryptedMessage = try e2eeService.encrypt(
                data: photoData,
                recipientPublicKey: recipientPublicKey
            )
        } catch {
            throw SendError.encryptionFailed
        }
        
        // 3. シリアライズ
        let serialized: String
        do {
            serialized = try e2eeService.serializeEncryptedMessage(encryptedMessage)
        } catch {
            throw SendError.encryptionFailed
        }
        
        // 4. Firebase Storageにアップロード
        let storageRef = storage.reference()
            .child("letters")
            .child(letterId)
            .child("photo_\(photoIndex).enc")
        
        guard let uploadData = serialized.data(using: .utf8) else {
            throw SendError.uploadFailed
        }
        
        let metadata = StorageMetadata()
        metadata.contentType = "application/octet-stream"
        
        do {
            _ = try await storageRef.putDataAsync(uploadData, metadata: metadata)
            let downloadURL = try await storageRef.downloadURL()
            return downloadURL.absoluteString
        } catch {
            throw SendError.uploadFailed
        }
    }
    
    // MARK: - Pending Letter Count
    
    /// 未開封手紙の数を取得
    private func getPendingLetterCount(senderId: String, recipientId: String) async throws -> Int {
        let snapshot = try await db.collection("letters")
            .whereField("senderId", isEqualTo: senderId)
            .whereField("recipientId", isEqualTo: recipientId)
            .whereField("status", in: ["pending", "scheduled", "delivered"])
            .getDocuments()
        
        return snapshot.documents.count
    }
    
    // MARK: - Get Sent Letters
    
    /// 送信した手紙一覧を取得
    func getSentLetters() async throws -> [EncryptedLetter] {
        guard let currentUser = Auth.auth().currentUser else {
            throw SendError.notAuthenticated
        }
        
        let snapshot = try await db.collection("letters")
            .whereField("senderId", isEqualTo: currentUser.uid)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc -> EncryptedLetter? in
            let data = doc.data()
            
            return EncryptedLetter(
                id: doc.documentID,
                senderId: data["senderId"] as? String ?? "",
                recipientId: data["recipientId"] as? String ?? "",
                encryptedContent: data["encryptedContent"] as? String ?? "",
                encryptedPhotoURLs: data["encryptedPhotoURLs"] as? [String] ?? [],
                deliveryCondition: DeliveryCondition(rawValue: data["deliveryCondition"] as? String ?? "") ?? .fixedDate,
                deliveryDate: (data["deliveryDate"] as? Timestamp)?.dateValue(),
                randomStartDate: (data["randomStartDate"] as? Timestamp)?.dateValue(),
                randomEndDate: (data["randomEndDate"] as? Timestamp)?.dateValue(),
                lastLoginDays: data["lastLoginDays"] as? Int,
                status: EncryptedLetter.LetterStatus(rawValue: data["status"] as? String ?? "") ?? .pending,
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            )
        }
    }
}
