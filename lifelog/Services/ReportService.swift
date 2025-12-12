//
//  ReportService.swift
//  lifelog
//
//  通報機能サービス
//

import Foundation
import FirebaseFirestore

/// 通報機能を提供するサービス
class ReportService {
    static let shared = ReportService()
    
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// 通報理由
    enum ReportReason: String, CaseIterable {
        case spam = "spam"
        case harassment = "harassment"
        case inappropriate = "inappropriate"
        case other = "other"
        
        var displayName: String {
            switch self {
            case .spam: return "スパム・迷惑行為"
            case .harassment: return "嫌がらせ・誹謗中傷"
            case .inappropriate: return "不適切なコンテンツ"
            case .other: return "その他"
            }
        }
    }
    
    /// ユーザーを通報
    /// - Parameters:
    ///   - userId: 通報対象のユーザーID
    ///   - reason: 通報理由
    ///   - letterId: 関連する手紙ID（任意）
    ///   - details: 詳細（任意）
    func reportUser(
        userId: String,
        reason: ReportReason,
        letterId: String? = nil,
        details: String? = nil
    ) async throws {
        guard let reporterId = AuthService.shared.currentUser?.id else {
            throw NSError(domain: "ReportService", code: -1, userInfo: [NSLocalizedDescriptionKey: "ログインが必要です"])
        }
        
        var reportData: [String: Any] = [
            "reporterId": reporterId,
            "reportedUserId": userId,
            "reason": reason.rawValue,
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        if let letterId = letterId {
            reportData["letterId"] = letterId
        }
        
        if let details = details {
            reportData["details"] = details
        }
        
        try await db.collection("reports").addDocument(data: reportData)
        
        print("✅ 通報を送信: \(userId) (理由: \(reason.rawValue))")
    }
}
