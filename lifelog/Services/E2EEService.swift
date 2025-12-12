//
//  E2EEService.swift
//  lifelog
//
//  大切な人への手紙機能のE2EE暗号化サービス
//

import Foundation
import CryptoKit
import Security

/// E2EE暗号化サービス
/// CryptoKitを使用してECDH鍵交換とAES-GCM暗号化を実装
class E2EEService {
    
    static let shared = E2EEService()
    
    // MARK: - Constants
    
    private let privateKeyTag = "com.lifelog.e2ee.privateKey"
    private let serviceName = "com.lifelog.e2ee"
    
    // MARK: - Errors
    
    enum E2EEError: Error, LocalizedError {
        case keyGenerationFailed
        case keyNotFound
        case keychainError(OSStatus)
        case encryptionFailed
        case decryptionFailed
        case invalidPublicKey
        case invalidData
        
        var errorDescription: String? {
            switch self {
            case .keyGenerationFailed:
                return "鍵ペアの生成に失敗しました"
            case .keyNotFound:
                return "秘密鍵が見つかりません"
            case .keychainError(let status):
                return "Keychainエラー: \(status)"
            case .encryptionFailed:
                return "暗号化に失敗しました"
            case .decryptionFailed:
                return "復号に失敗しました"
            case .invalidPublicKey:
                return "無効な公開鍵です"
            case .invalidData:
                return "無効なデータです"
            }
        }
    }
    
    // MARK: - Encrypted Message Structure
    
    /// 暗号化されたメッセージの構造
    struct EncryptedMessage: Codable {
        let encryptedContent: Data      // AES-GCMで暗号化された本文
        let ephemeralPublicKey: Data    // 一時的な公開鍵（ECDH用）
        let nonce: Data                 // AES-GCMのnonce
        let tag: Data                   // AES-GCMの認証タグ
    }
    
    private init() {}
    
    // MARK: - Key Generation
    
    /// 新しい鍵ペアを生成してKeychainに保存
    /// - Returns: 公開鍵のData表現
    func generateKeyPair() throws -> Data {
        // 新しいP-256キーペアを生成
        let privateKey = P256.KeyAgreement.PrivateKey()
        
        // Keychainに保存
        try savePrivateKeyToKeychain(privateKey)
        
        // 公開鍵を返す
        return privateKey.publicKey.rawRepresentation
    }
    
    /// 既存の鍵ペアがあるか確認し、なければ生成
    /// - Returns: 公開鍵のData表現
    func getOrCreateKeyPair() throws -> Data {
        // まず既存の鍵を探す
        if let existingKey = try? loadPrivateKeyFromKeychain() {
            return existingKey.publicKey.rawRepresentation
        }
        
        // なければ新規生成
        return try generateKeyPair()
    }
    
    /// 公開鍵を取得
    func getPublicKey() throws -> Data {
        let privateKey = try loadPrivateKeyFromKeychain()
        return privateKey.publicKey.rawRepresentation
    }
    
    // MARK: - Keychain Operations
    
    /// 秘密鍵をKeychainに保存（iCloud同期有効）
    private func savePrivateKeyToKeychain(_ privateKey: P256.KeyAgreement.PrivateKey) throws {
        let privateKeyData = privateKey.rawRepresentation
        
        // 既存の鍵を削除
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: privateKeyTag
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // 新しい鍵を保存
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: privateKeyTag,
            kSecValueData as String: privateKeyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: true  // iCloud同期有効
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw E2EEError.keychainError(status)
        }
    }
    
    /// Keychainから秘密鍵を読み込み
    private func loadPrivateKeyFromKeychain() throws -> P256.KeyAgreement.PrivateKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: privateKeyTag,
            kSecReturnData as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound {
                throw E2EEError.keyNotFound
            }
            throw E2EEError.keychainError(status)
        }
        
        return try P256.KeyAgreement.PrivateKey(rawRepresentation: data)
    }
    
    /// Keychainから秘密鍵を削除
    func deletePrivateKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: privateKeyTag,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw E2EEError.keychainError(status)
        }
    }
    
    // MARK: - Encryption
    
    /// メッセージを暗号化
    /// - Parameters:
    ///   - message: 暗号化する平文
    ///   - recipientPublicKey: 受信者の公開鍵（Base64エンコード）
    /// - Returns: 暗号化されたメッセージ
    func encrypt(message: String, recipientPublicKey: String) throws -> EncryptedMessage {
        guard let messageData = message.data(using: .utf8) else {
            throw E2EEError.invalidData
        }
        return try encrypt(data: messageData, recipientPublicKey: recipientPublicKey)
    }
    
    /// データを暗号化
    /// - Parameters:
    ///   - data: 暗号化するデータ
    ///   - recipientPublicKey: 受信者の公開鍵（Base64エンコード）
    /// - Returns: 暗号化されたメッセージ
    func encrypt(data: Data, recipientPublicKey: String) throws -> EncryptedMessage {
        // 受信者の公開鍵をデコード
        guard let recipientKeyData = Data(base64Encoded: recipientPublicKey) else {
            throw E2EEError.invalidPublicKey
        }
        
        let recipientKey = try P256.KeyAgreement.PublicKey(rawRepresentation: recipientKeyData)
        
        // 一時的な鍵ペアを生成（Forward Secrecy）
        let ephemeralPrivateKey = P256.KeyAgreement.PrivateKey()
        let ephemeralPublicKey = ephemeralPrivateKey.publicKey
        
        // ECDH共有シークレットを導出
        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: recipientKey)
        
        // HKDFで対称鍵を導出
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: "lifelog-e2ee-v1".data(using: .utf8)!,
            outputByteCount: 32
        )
        
        // AES-GCMで暗号化
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: symmetricKey, nonce: nonce)
        
        return EncryptedMessage(
            encryptedContent: sealedBox.ciphertext,
            ephemeralPublicKey: ephemeralPublicKey.rawRepresentation,
            nonce: Data(nonce),
            tag: sealedBox.tag
        )
    }
    
    // MARK: - Decryption
    
    /// 暗号化されたメッセージを復号
    /// - Parameter encryptedMessage: 暗号化されたメッセージ
    /// - Returns: 復号された文字列
    func decrypt(encryptedMessage: EncryptedMessage) throws -> String {
        let decryptedData = try decryptData(encryptedMessage: encryptedMessage)
        guard let message = String(data: decryptedData, encoding: .utf8) else {
            throw E2EEError.decryptionFailed
        }
        return message
    }
    
    /// 暗号化されたデータを復号
    /// - Parameter encryptedMessage: 暗号化されたメッセージ
    /// - Returns: 復号されたデータ
    func decryptData(encryptedMessage: EncryptedMessage) throws -> Data {
        // 自分の秘密鍵を取得
        let privateKey = try loadPrivateKeyFromKeychain()
        
        // 送信者の一時公開鍵を復元
        let ephemeralPublicKey = try P256.KeyAgreement.PublicKey(
            rawRepresentation: encryptedMessage.ephemeralPublicKey
        )
        
        // ECDH共有シークレットを導出
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)
        
        // HKDFで対称鍵を導出
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: "lifelog-e2ee-v1".data(using: .utf8)!,
            outputByteCount: 32
        )
        
        // AES-GCMで復号
        let nonce = try AES.GCM.Nonce(data: encryptedMessage.nonce)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: encryptedMessage.encryptedContent,
            tag: encryptedMessage.tag
        )
        
        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }
    
    // MARK: - Serialization
    
    /// EncryptedMessageをBase64エンコードされたJSON文字列に変換
    func serializeEncryptedMessage(_ message: EncryptedMessage) throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        return data.base64EncodedString()
    }
    
    /// Base64エンコードされたJSON文字列からEncryptedMessageを復元
    func deserializeEncryptedMessage(_ serialized: String) throws -> EncryptedMessage {
        guard let data = Data(base64Encoded: serialized) else {
            throw E2EEError.invalidData
        }
        let decoder = JSONDecoder()
        return try decoder.decode(EncryptedMessage.self, from: data)
    }
    
    // MARK: - Utility
    
    /// 公開鍵をBase64エンコード
    func encodePublicKey(_ publicKeyData: Data) -> String {
        return publicKeyData.base64EncodedString()
    }
    
    /// Base64エンコードされた公開鍵をデコード
    func decodePublicKey(_ base64String: String) throws -> Data {
        guard let data = Data(base64Encoded: base64String) else {
            throw E2EEError.invalidPublicKey
        }
        return data
    }
    
    /// 秘密鍵が存在するかチェック
    func hasPrivateKey() -> Bool {
        do {
            _ = try loadPrivateKeyFromKeychain()
            return true
        } catch {
            return false
        }
    }
}
