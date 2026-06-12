//
//  AuthService.swift
//  lifelog
//
//  Sign in with Apple + Firebase Auth 認証サービス
//

import Foundation
import Combine
import AuthenticationServices
import FirebaseAuth
import FirebaseFirestore
import CryptoKit

/// 認証サービス
/// Sign in with Apple と Firebase Auth の連携を管理
class AuthService: ObservableObject {
    
    static let shared = AuthService()
    
    // MARK: - Published Properties
    
    @Published var isSignedIn: Bool = false
    @Published var currentUser: LetterUser?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private var currentNonce: String?
    private let db = Firestore.firestore()
    
    // MARK: - User Model
    
    struct LetterUser: Codable, Identifiable {
        let id: String
        var emoji: String
        var displayName: String
        var publicKey: String
        var fcmToken: String?
        var blockedUsers: [String]
        let createdAt: Date
        var lastActiveAt: Date
        
        init(id: String, emoji: String, displayName: String, publicKey: String) {
            self.id = id
            self.emoji = emoji
            self.displayName = displayName
            self.publicKey = publicKey
            self.fcmToken = nil
            self.blockedUsers = []
            self.createdAt = Date()
            self.lastActiveAt = Date()
        }
    }
    
    // MARK: - Initialization
    
    init() {
        checkAuthState()
    }
    
    /// 認証状態をチェック
    func checkAuthState() {
        if let user = Auth.auth().currentUser {
            isSignedIn = true
            _Concurrency.Task {
                await fetchUserData(userId: user.uid)
            }
        } else {
            isSignedIn = false
            currentUser = nil
        }
    }
    
    // MARK: - Sign in with Apple
    
    /// Apple サインインリクエストを生成
    func createAppleSignInRequest() -> ASAuthorizationAppleIDRequest {
        let nonce = randomNonceString()
        currentNonce = nonce
        
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        return request
    }
    
    /// Apple サインイン結果を処理
    func handleAppleSignIn(result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil
        
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "無効な認証情報です"
                isLoading = false
                return
            }
            
            guard let nonce = currentNonce else {
                errorMessage = "認証エラー: nonceが見つかりません"
                isLoading = false
                return
            }
            
            guard let appleIDToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                errorMessage = "認証トークンの取得に失敗しました"
                isLoading = false
                return
            }
            
            // Firebase認証
            let credential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )
            
            do {
                let authResult = try await Auth.auth().signIn(with: credential)
                
                // 新規ユーザーかチェック
                let isNewUser = authResult.additionalUserInfo?.isNewUser ?? false
                
                if isNewUser {
                    // 新規ユーザー: プロフィール設定が必要
                    let displayName = buildDisplayName(from: appleIDCredential.fullName) ?? "ユーザー"
                    await createNewUser(userId: authResult.user.uid, displayName: displayName)
                } else {
                    // 既存ユーザー: データを取得
                    await fetchUserData(userId: authResult.user.uid)
                }
                
                isSignedIn = true
                
            } catch {
                // セキュリティ上、詳細なエラー情報は表示しない
                print("Sign in error: \(error)")
                errorMessage = "サインインに失敗しました。しばらくしてから再度お試しください。"
            }
            
        case .failure(let error):
            let nsError = error as NSError
            if nsError.code == ASAuthorizationError.canceled.rawValue {
                // ユーザーがキャンセルした場合はエラーを表示しない
                errorMessage = nil
            } else {
                print("Apple Sign In error: \(error)")
                errorMessage = "サインインに失敗しました。しばらくしてから再度お試しください。"
            }
        }
        
        isLoading = false
    }
    
    // MARK: - User Data Management
    
    /// 新規ユーザーを作成
    private func createNewUser(userId: String, displayName: String) async {
        do {
            // E2EE鍵ペアを生成
            let publicKeyData = try E2EEService.shared.getOrCreateKeyPair()
            let publicKey = E2EEService.shared.encodePublicKey(publicKeyData)
            
            // デフォルトの絵文字
            let defaultEmojis = ["😊", "🌟", "🎉", "💫", "🌈", "🦋", "🌸", "🍀"]
            let randomEmoji = defaultEmojis.randomElement() ?? "😊"
            
            let user = LetterUser(
                id: userId,
                emoji: randomEmoji,
                displayName: displayName,
                publicKey: publicKey
            )
            
            // Firestoreに保存
            try await saveUserToFirestore(user)
            currentUser = user
            
        } catch {
            print("Create user error: \(error)")
            errorMessage = "ユーザー作成に失敗しました。しばらくしてから再度お試しください。"
        }
    }
    
    /// Firestoreからユーザーデータを取得
    func fetchUserData(userId: String) async {
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            
            if document.exists, let data = document.data() {
                currentUser = parseUserData(data: data, userId: userId)
                
                // lastActiveAtを更新
                try? await db.collection("users").document(userId).updateData([
                    "lastActiveAt": FieldValue.serverTimestamp()
                ])
            } else {
                // ドキュメントがない場合は新規作成
                await createNewUser(userId: userId, displayName: "ユーザー")
            }
        } catch {
            errorMessage = "ユーザーデータの取得に失敗しました"
        }
    }
    
    /// ユーザーデータをFirestoreに保存
    func saveUserToFirestore(_ user: LetterUser) async throws {
        let data: [String: Any] = [
            "emoji": user.emoji,
            "displayName": user.displayName,
            "publicKey": user.publicKey,
            "fcmToken": user.fcmToken as Any,
            "blockedUsers": user.blockedUsers,
            "createdAt": Timestamp(date: user.createdAt),
            "lastActiveAt": FieldValue.serverTimestamp()
        ]
        
        try await db.collection("users").document(user.id).setData(data, merge: true)
    }
    
    /// プロフィールを更新
    func updateProfile(emoji: String, displayName: String) async throws {
        guard var user = currentUser else { return }
        
        user.emoji = emoji
        user.displayName = displayName
        
        try await saveUserToFirestore(user)
        currentUser = user
    }
    
    // MARK: - Last Login Update
    
    /// 最終ログイン日時を更新
    /// アプリ起動時に呼び出す（最終ログイン配信の判定に使用）
    func updateLastLoginAt() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            try await db.collection("users").document(userId).updateData([
                "lastLoginAt": FieldValue.serverTimestamp()
            ])
            print("✅ lastLoginAt 更新完了")
        } catch {
            print("⚠️ lastLoginAt 更新エラー: \(error.localizedDescription)")
        }
    }
    
    // MARK: - FCM Token
    
    /// FCMトークンを保存
    func saveFCMToken(_ token: String) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            try await db.collection("users").document(userId).updateData([
                "fcmToken": token
            ])
            
            if var user = currentUser {
                user.fcmToken = token
                currentUser = user
            }
            
            print("✅ FCMトークン保存完了")
        } catch {
            print("⚠️ FCMトークン保存エラー: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Notification Settings
    
    /// 手紙通知設定をFirestoreに保存
    /// Cloud Functionsがプッシュ通知を送信する際に参照
    func updateLetterNotificationEnabled(_ enabled: Bool) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            try await db.collection("users").document(userId).updateData([
                "letterNotificationEnabled": enabled
            ])
            print("✅ 手紙通知設定を更新: \(enabled)")
        } catch {
            print("⚠️ 手紙通知設定更新エラー: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Block Management
    
    /// ユーザーをブロック
    func blockUser(_ userId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "ログインが必要です"])
        }
        
        try await db.collection("users").document(currentUserId).updateData([
            "blockedUsers": FieldValue.arrayUnion([userId])
        ])
        
        // ローカルも更新
        if var user = currentUser {
            if !user.blockedUsers.contains(userId) {
                user.blockedUsers.append(userId)
                currentUser = user
            }
        }
        
        print("✅ ユーザーをブロック: \(userId)")
    }
    
    /// ユーザーのブロックを解除
    func unblockUser(_ userId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "ログインが必要です"])
        }
        
        try await db.collection("users").document(currentUserId).updateData([
            "blockedUsers": FieldValue.arrayRemove([userId])
        ])
        
        // ローカルも更新
        if var user = currentUser {
            user.blockedUsers.removeAll { $0 == userId }
            currentUser = user
        }
        
        print("✅ ブロック解除: \(userId)")
    }
    
    /// ユーザーがブロックされているか確認
    func isBlocked(_ userId: String) -> Bool {
        return currentUser?.blockedUsers.contains(userId) ?? false
    }
    
    // MARK: - Sign Out
    
    /// サインアウト
    /// - Parameter deletingEncryptionKey: true なら E2EE 秘密鍵も Keychain から削除する。
    ///   共有端末で次の利用者に鍵を残さないための選択肢。鍵は iCloud キーチェーンで
    ///   同期されているため、削除は他のデバイスにも伝播し、未開封の手紙が二度と
    ///   復号できなくなる可能性がある。UI 側で必ず警告のうえユーザーに選ばせること。
    func signOut(deletingEncryptionKey: Bool = false) throws {
        // 鍵削除を先に行う: サインアウト成功後に鍵削除だけ失敗すると
        // 「削除したつもりで鍵が残る」状態になりユーザーに気づく手段がない
        if deletingEncryptionKey {
            try E2EEService.shared.deletePrivateKey()
        }
        try Auth.auth().signOut()
        isSignedIn = false
        currentUser = nil
    }
    
    // MARK: - Helper Methods
    
    /// Firestore データをパース
    private func parseUserData(data: [String: Any], userId: String) -> LetterUser {
        let emoji = data["emoji"] as? String ?? "😊"
        let displayName = data["displayName"] as? String ?? "ユーザー"
        let publicKey = data["publicKey"] as? String ?? ""
        let fcmToken = data["fcmToken"] as? String
        let blockedUsers = data["blockedUsers"] as? [String] ?? []
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let lastActiveAt = (data["lastActiveAt"] as? Timestamp)?.dateValue() ?? Date()
        
        var user = LetterUser(id: userId, emoji: emoji, displayName: displayName, publicKey: publicKey)
        user.fcmToken = fcmToken
        user.blockedUsers = blockedUsers
        return user
    }
    
    /// PersonNameComponentsから表示名を構築
    private func buildDisplayName(from nameComponents: PersonNameComponents?) -> String? {
        guard let nameComponents = nameComponents else { return nil }
        
        var parts: [String] = []
        if let familyName = nameComponents.familyName {
            parts.append(familyName)
        }
        if let givenName = nameComponents.givenName {
            parts.append(givenName)
        }
        
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
    
    /// ランダムなnonce文字列を生成
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            // ここで落とすとサインイン操作がアプリクラッシュになる。
            // SystemRandomNumberGenerator も Apple プラットフォームでは
            // 暗号学的に安全な乱数源(arc4random系)なので、nonce の強度を
            // 落とさずにフォールバックできる。
            var generator = SystemRandomNumberGenerator()
            randomBytes = (0..<length).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }
        
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        
        return String(nonce)
    }
    
    /// SHA256ハッシュ
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}
