//
//  DeepLinkHandler.swift
//  lifelog
//
//  Universal Links (Deep Link) ハンドラー
//

import Foundation
import Combine
import SwiftUI
import FirebaseAuth

/// Deep Link ハンドラー
class DeepLinkHandler: ObservableObject {
    
    static let shared = DeepLinkHandler()
    
    // MARK: - Published Properties
    
    @Published var pendingInviteLinkId: String?
    @Published var showInviteConfirmation = false
    @Published var showSignInFlow = false  // サインイン画面を表示
    @Published var showAddedSuccess = false  // 追加成功ダイアログ
    @Published var addedFriendName: String?  // 追加した友達の名前
    @Published var inviteLinkData: PairingService.InviteLink?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private init() {}
    
    // MARK: - Handle URL
    
    /// URLを処理
    func handleURL(_ url: URL) {
        print("Handling URL: \(url)")
        
        // パスを解析: /invite/{linkId}
        let pathComponents = url.pathComponents
        
        guard pathComponents.count >= 2,
              pathComponents[1] == "invite",
              pathComponents.count >= 3 else {
            print("Invalid URL path")
            return
        }
        
        let linkId = pathComponents[2]
        print("Extracted invite link ID: \(linkId)")
        
        pendingInviteLinkId = linkId
        
        // 招待リンクの詳細を取得
        fetchInviteLinkData(linkId: linkId)
    }
    
    /// 招待リンクデータを取得
    private func fetchInviteLinkData(linkId: String) {
        // ログインチェック（Firebase Authを直接チェック - 非同期ロード待ち問題を回避）
        guard Auth.auth().currentUser != nil else {
            // 未ログイン: サインイン画面を表示（招待IDは保持したまま）
            showSignInFlow = true
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        _Concurrency.Task {
            do {
                let link = try await PairingService.shared.getInviteLink(id: linkId)
                
                await MainActor.run {
                    isLoading = false
                    
                    if let link = link {
                        if link.isExpired {
                            errorMessage = "この招待リンクは有効期限が切れています"
                        } else if link.userId == AuthService.shared.currentUser?.id {
                            errorMessage = "自分自身を友達に追加することはできません"
                        } else {
                            inviteLinkData = link
                            showInviteConfirmation = true
                        }
                    } else {
                        errorMessage = "招待リンクが見つかりません"
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    /// 即時友達追加
    func addFriend() {
        guard let linkId = pendingInviteLinkId else { return }
        
        isLoading = true
        
        _Concurrency.Task {
            do {
                try await PairingService.shared.addFriendFromInvite(inviteLinkId: linkId)
                
                await MainActor.run {
                    isLoading = false
                    showInviteConfirmation = false
                    addedFriendName = inviteLinkData?.userName
                    pendingInviteLinkId = nil
                    inviteLinkData = nil
                    // 成功ダイアログを表示
                    showAddedSuccess = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    /// サインイン完了後に呼び出し（招待処理を続行）
    func onSignInCompleted() {
        showSignInFlow = false
        
        // 保留中の招待リンクがあれば処理を再開
        if let linkId = pendingInviteLinkId {
            fetchInviteLinkData(linkId: linkId)
        }
    }
    
    /// クリア
    func clear() {
        pendingInviteLinkId = nil
        showInviteConfirmation = false
        showSignInFlow = false
        showAddedSuccess = false
        addedFriendName = nil
        inviteLinkData = nil
        errorMessage = nil
    }
}

// MARK: - Invite Confirmation View

/// 招待確認ダイアログ
struct InviteConfirmationView: View {
    @ObservedObject private var handler = DeepLinkHandler.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                
                if let link = handler.inviteLinkData {
                    // 招待者情報
                    VStack(spacing: 16) {
                        Text(link.userEmoji)
                            .font(.system(size: 80))
                        
                        Text(link.userName)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("さんからの招待")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // E2EE説明
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.green)
                        Text("E2EE暗号化で安全に通信できます")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                }
                
                Spacer()
                
                // エラーメッセージ
                if let error = handler.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                // アクションボタン
                VStack(spacing: 12) {
                    Button(action: handler.addFriend) {
                        HStack {
                            if handler.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "person.badge.plus")
                                Text("友達に追加する")
                            }
                        }
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(handler.isLoading)
                    
                    Button("キャンセル") {
                        handler.clear()
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .navigationTitle("友達を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        handler.clear()
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    InviteConfirmationView()
}
