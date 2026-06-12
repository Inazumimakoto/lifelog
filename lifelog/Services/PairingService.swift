//
//  PairingService.swift
//  lifelog
//
//  友達ペアリング管理サービス
//

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

/// 友達ペアリング管理サービス
class PairingService: ObservableObject {
    
    static let shared = PairingService()
    
    // MARK: - Published Properties
    
    @Published var friends: [Friend] = []
    @Published var pendingRequests: [FriendRequest] = []
    @Published var sentRequests: [FriendRequest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private let db = Firestore.firestore()
    private var friendsListener: ListenerRegistration?
    private var pendingListener: ListenerRegistration?
    private var sentListener: ListenerRegistration?
    
    // MARK: - Models
    
    struct Friend: Identifiable, Codable {
        let id: String
        let odic: String            // 相手のユーザーID
        let friendEmoji: String
        let friendName: String
        let friendPublicKey: String
        let createdAt: Date
        var pendingLetterCount: Int // こちらから送った未開封数
        
        init(id: String, odic: String, friendEmoji: String, friendName: String, friendPublicKey: String, createdAt: Date = Date(), pendingLetterCount: Int = 0) {
            self.id = id
            self.odic = odic
            self.friendEmoji = friendEmoji
            self.friendName = friendName
            self.friendPublicKey = friendPublicKey
            self.createdAt = createdAt
            self.pendingLetterCount = pendingLetterCount
        }
    }
    
    struct FriendRequest: Identifiable, Codable {
        let id: String
        let fromUserId: String
        let fromUserEmoji: String
        let fromUserName: String
        let fromUserPublicKey: String
        let toUserId: String
        let status: RequestStatus
        let createdAt: Date
        
        enum RequestStatus: String, Codable {
            case pending = "pending"
            case accepted = "accepted"
            case rejected = "rejected"
        }
    }
    
    struct InviteLink: Identifiable, Codable {
        let id: String
        let userId: String
        let userEmoji: String
        let userName: String
        let userPublicKey: String
        let expiresAt: Date
        let createdAt: Date
        
        var isExpired: Bool {
            Date() > expiresAt
        }
        
        var shareURL: URL? {
            URL(string: "https://lifelog-1bed0.web.app/invite/\(id)")
        }
    }
    
    private init() {}
    
    // MARK: - Invite Link
    
    /// 招待リンクを生成（24時間有効）
    func createInviteLink() async throws -> InviteLink {
        guard let currentUser = Auth.auth().currentUser,
              let userData = AuthService.shared.currentUser else {
            throw PairingError.notAuthenticated
        }
        
        let linkId = UUID().uuidString.lowercased()
        let now = Date()
        let expiresAt = now.addingTimeInterval(24 * 60 * 60) // 24時間後
        
        let inviteLink = InviteLink(
            id: linkId,
            userId: currentUser.uid,
            userEmoji: userData.emoji,
            userName: userData.displayName,
            userPublicKey: userData.publicKey,
            expiresAt: expiresAt,
            createdAt: now
        )
        
        let data: [String: Any] = [
            "userId": inviteLink.userId,
            "userEmoji": inviteLink.userEmoji,
            "userName": inviteLink.userName,
            "userPublicKey": inviteLink.userPublicKey,
            "expiresAt": Timestamp(date: inviteLink.expiresAt),
            "createdAt": Timestamp(date: inviteLink.createdAt)
        ]
        
        try await db.collection("inviteLinks").document(linkId).setData(data)
        
        return inviteLink
    }
    
    /// 招待リンクを取得
    func getInviteLink(id: String) async throws -> InviteLink? {
        let document = try await db.collection("inviteLinks").document(id).getDocument()
        
        guard document.exists, let data = document.data() else {
            return nil
        }
        
        let expiresAt = (data["expiresAt"] as? Timestamp)?.dateValue() ?? Date()
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        
        return InviteLink(
            id: id,
            userId: data["userId"] as? String ?? "",
            userEmoji: data["userEmoji"] as? String ?? "😊",
            userName: data["userName"] as? String ?? "ユーザー",
            userPublicKey: data["userPublicKey"] as? String ?? "",
            expiresAt: expiresAt,
            createdAt: createdAt
        )
    }
    
    // MARK: - Friend Requests
    
    /// 友達リクエストを送信（招待リンクから）
    func sendFriendRequest(inviteLinkId: String) async throws {
        guard let currentUser = Auth.auth().currentUser,
              let userData = AuthService.shared.currentUser else {
            throw PairingError.notAuthenticated
        }
        
        // 招待リンクを取得
        guard let inviteLink = try await getInviteLink(id: inviteLinkId) else {
            throw PairingError.inviteLinkNotFound
        }
        
        // 有効期限チェック
        if inviteLink.isExpired {
            throw PairingError.inviteLinkExpired
        }
        
        // 自分自身への招待チェック
        if inviteLink.userId == currentUser.uid {
            throw PairingError.cannotAddSelf
        }
        
        // 既に友達かチェック
        let existingFriend = try await db.collection("pairings")
            .whereField("userId", isEqualTo: currentUser.uid)
            .whereField("friendId", isEqualTo: inviteLink.userId)
            .getDocuments()
        
        if !existingFriend.documents.isEmpty {
            throw PairingError.alreadyFriends
        }
        
        // 既にリクエスト送信済みかチェック
        let existingRequest = try await db.collection("friendRequests")
            .whereField("fromUserId", isEqualTo: currentUser.uid)
            .whereField("toUserId", isEqualTo: inviteLink.userId)
            .whereField("status", isEqualTo: "pending")
            .getDocuments()
        
        if !existingRequest.documents.isEmpty {
            throw PairingError.requestAlreadySent
        }
        
        // リクエストを作成
        let requestId = UUID().uuidString
        let request = FriendRequest(
            id: requestId,
            fromUserId: currentUser.uid,
            fromUserEmoji: userData.emoji,
            fromUserName: userData.displayName,
            fromUserPublicKey: userData.publicKey,
            toUserId: inviteLink.userId,
            status: .pending,
            createdAt: Date()
        )
        
        let data: [String: Any] = [
            "fromUserId": request.fromUserId,
            "fromUserEmoji": request.fromUserEmoji,
            "fromUserName": request.fromUserName,
            "fromUserPublicKey": request.fromUserPublicKey,
            "toUserId": request.toUserId,
            "status": request.status.rawValue,
            "createdAt": Timestamp(date: request.createdAt)
        ]
        
        try await db.collection("friendRequests").document(requestId).setData(data)
    }
    
    /// 招待リンクから即時友達追加。
    /// pairings はルール上クライアントから書けないため、source ==
    /// "inviteLink" の friendRequest を作成し、Cloud Functions
    /// (onFriendRequestCreated) がリンクを検証して双方向ペアリングを
    /// 作成するのを待つ。公開鍵はサーバーが users コレクションの正本
    /// から取得する(偽の鍵を注入する攻撃への対策)。
    func addFriendFromInvite(inviteLinkId: String) async throws {
        guard let currentUser = Auth.auth().currentUser,
              let userData = AuthService.shared.currentUser else {
            throw PairingError.notAuthenticated
        }

        // 招待リンクを取得
        guard let inviteLink = try await getInviteLink(id: inviteLinkId) else {
            throw PairingError.inviteLinkNotFound
        }

        // 有効期限チェック
        if inviteLink.isExpired {
            throw PairingError.inviteLinkExpired
        }

        // 自分自身への招待チェック
        if inviteLink.userId == currentUser.uid {
            throw PairingError.cannotAddSelf
        }

        // 既に友達かチェック
        let existingFriend = try await db.collection("pairings")
            .whereField("userId", isEqualTo: currentUser.uid)
            .whereField("friendId", isEqualTo: inviteLink.userId)
            .getDocuments()

        if !existingFriend.documents.isEmpty {
            throw PairingError.alreadyFriends
        }

        let requestId = UUID().uuidString
        let data: [String: Any] = [
            "fromUserId": currentUser.uid,
            "fromUserEmoji": userData.emoji,
            "fromUserName": userData.displayName,
            "fromUserPublicKey": userData.publicKey,
            "toUserId": inviteLink.userId,
            "status": FriendRequest.RequestStatus.pending.rawValue,
            "source": "inviteLink",
            "inviteLinkId": inviteLinkId,
            "createdAt": Timestamp(date: Date())
        ]

        try await db.collection("friendRequests").document(requestId).setData(data)
        try await waitForRequestResolution(requestId: requestId)
    }

    /// サーバー(Cloud Functions)が friendRequest を処理して status を
    /// accepted / rejected にするのを待つ。accepted はペアリング作成後に
    /// 付くため、戻った時点で友達追加は完了している。
    private func waitForRequestResolution(requestId: String, timeoutSeconds: Int = 15) async throws {
        let ref = db.collection("friendRequests").document(requestId)
        for _ in 0..<(timeoutSeconds * 2) {
            try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
            let doc = try await ref.getDocument()
            switch doc.data()?["status"] as? String {
            case FriendRequest.RequestStatus.accepted.rawValue:
                return
            case FriendRequest.RequestStatus.rejected.rawValue:
                throw Self.pairingError(forRejectReason: doc.data()?["rejectReason"] as? String)
            default:
                continue
            }
        }
        throw PairingError.serverTimeout
    }

    /// サーバーが返した拒否理由をクライアントのエラーに対応付ける
    private static func pairingError(forRejectReason reason: String?) -> PairingError {
        switch reason {
        case "inviteLinkNotFound": return .inviteLinkNotFound
        case "inviteLinkExpired": return .inviteLinkExpired
        case "cannotAddSelf": return .cannotAddSelf
        default: return .pairingFailed
        }
    }

    /// 自分側の pairings 行がサーバーによって作成されるのを待つ
    private func waitForPairing(friendId: String, timeoutSeconds: Int = 15) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw PairingError.notAuthenticated
        }
        for _ in 0..<(timeoutSeconds * 2) {
            try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
            let docs = try await db.collection("pairings")
                .whereField("userId", isEqualTo: currentUser.uid)
                .whereField("friendId", isEqualTo: friendId)
                .limit(to: 1)
                .getDocuments()
            if !docs.documents.isEmpty {
                return
            }
        }
        throw PairingError.serverTimeout
    }
    
    /// 友達リクエストを承認。
    /// ペアリング作成はサーバー(onFriendRequestAccepted)が行うため、
    /// クライアントは status の更新と、自分側の行ができるのを待つだけ。
    func acceptFriendRequest(_ request: FriendRequest) async throws {
        guard Auth.auth().currentUser != nil else {
            throw PairingError.notAuthenticated
        }

        try await db.collection("friendRequests").document(request.id).updateData([
            "status": FriendRequest.RequestStatus.accepted.rawValue
        ])

        try await waitForPairing(friendId: request.fromUserId)
    }
    
    /// 友達リクエストを拒否
    func rejectFriendRequest(_ request: FriendRequest) async throws {
        try await db.collection("friendRequests").document(request.id).updateData([
            "status": "rejected"
        ])
    }
    
    // MARK: - Friends Management
    
    /// 友達一覧を取得開始
    func startListeningToFriends() {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        friendsListener = db.collection("pairings")
            .whereField("userId", isEqualTo: currentUser.uid)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                self?.friends = documents.compactMap { doc -> Friend? in
                    let data = doc.data()
                    return Friend(
                        id: doc.documentID,
                        odic: data["friendId"] as? String ?? "",
                        friendEmoji: data["friendEmoji"] as? String ?? "😊",
                        friendName: data["friendName"] as? String ?? "ユーザー",
                        friendPublicKey: data["friendPublicKey"] as? String ?? "",
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                        pendingLetterCount: data["pendingLetterCount"] as? Int ?? 0
                    )
                }
            }
    }
    
    /// 受信した友達リクエストを取得開始
    func startListeningToPendingRequests() {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        pendingListener = db.collection("friendRequests")
            .whereField("toUserId", isEqualTo: currentUser.uid)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                self?.pendingRequests = documents.compactMap { doc -> FriendRequest? in
                    let data = doc.data()
                    return FriendRequest(
                        id: doc.documentID,
                        fromUserId: data["fromUserId"] as? String ?? "",
                        fromUserEmoji: data["fromUserEmoji"] as? String ?? "😊",
                        fromUserName: data["fromUserName"] as? String ?? "ユーザー",
                        fromUserPublicKey: data["fromUserPublicKey"] as? String ?? "",
                        toUserId: data["toUserId"] as? String ?? "",
                        status: FriendRequest.RequestStatus(rawValue: data["status"] as? String ?? "pending") ?? .pending,
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    )
                }
            }
    }
    
    /// 送信した友達リクエストを取得開始
    func startListeningToSentRequests() {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        sentListener = db.collection("friendRequests")
            .whereField("fromUserId", isEqualTo: currentUser.uid)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                self?.sentRequests = documents.compactMap { doc -> FriendRequest? in
                    let data = doc.data()
                    return FriendRequest(
                        id: doc.documentID,
                        fromUserId: data["fromUserId"] as? String ?? "",
                        fromUserEmoji: data["fromUserEmoji"] as? String ?? "😊",
                        fromUserName: data["fromUserName"] as? String ?? "ユーザー",
                        fromUserPublicKey: data["fromUserPublicKey"] as? String ?? "",
                        toUserId: data["toUserId"] as? String ?? "",
                        status: FriendRequest.RequestStatus(rawValue: data["status"] as? String ?? "pending") ?? .pending,
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    )
                }
            }
    }
    
    /// リスナーを停止
    func stopListening() {
        friendsListener?.remove()
        pendingListener?.remove()
        sentListener?.remove()
    }
    
    /// 友達を削除。
    /// ルール上、削除できるのは自分側の行のみ。相手側(鏡像)の行は
    /// Cloud Functions (onPairingDeleted) が削除する。
    func removeFriend(_ friend: Friend) async throws {
        guard Auth.auth().currentUser != nil else {
            throw PairingError.notAuthenticated
        }

        try await db.collection("pairings").document(friend.id).delete()
    }
    
    // MARK: - Errors
    
    enum PairingError: Error, LocalizedError {
        case notAuthenticated
        case inviteLinkNotFound
        case inviteLinkExpired
        case cannotAddSelf
        case alreadyFriends
        case requestAlreadySent
        case serverTimeout
        case pairingFailed

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "ログインが必要です"
            case .inviteLinkNotFound:
                return "招待リンクが見つかりません"
            case .inviteLinkExpired:
                return "招待リンクの有効期限が切れています"
            case .cannotAddSelf:
                return "自分自身を友達に追加することはできません"
            case .alreadyFriends:
                return "既に友達です"
            case .requestAlreadySent:
                return "既にリクエストを送信済みです"
            case .serverTimeout:
                return "サーバーの応答がありません。通信環境を確認してもう一度お試しください"
            case .pairingFailed:
                return "友達追加に失敗しました。しばらくしてからもう一度お試しください"
            }
        }
    }
}
