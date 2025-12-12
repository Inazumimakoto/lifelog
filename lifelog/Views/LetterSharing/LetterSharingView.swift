//
//  LetterSharingView.swift
//  lifelog
//
//  大切な人への手紙機能 メイン画面
//

import SwiftUI

/// 大切な人への手紙機能のメイン画面
/// 認証状態に応じてサインイン画面またはメイン機能を表示
struct LetterSharingView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var pairingService = PairingService.shared
    @ObservedObject private var deepLinkHandler = DeepLinkHandler.shared
    @State private var showingProfileSetup = false
    @State private var showingProfileEdit = false
    @State private var showingSignOutConfirmation = false
    @State private var showingE2EEInfo = false
    @State private var showingRequests = false
    @State private var showingRemoveFriendConfirmation = false
    @State private var friendToRemove: PairingService.Friend?
    @State private var showingShareSheet = false
    @State private var inviteURL: URL?
    @State private var isGeneratingInvite = false
    @State private var showingLetterEditor = false
    @State private var preselectedFriend: PairingService.Friend?
    
    var body: some View {
        NavigationStack {
            Group {
                if !authService.isSignedIn {
                    // 未ログイン: サインイン画面
                    LetterSignInView(onSignInComplete: {
                        // 新規ユーザーはプロフィール設定を表示
                        if authService.currentUser != nil {
                            showingProfileSetup = true
                        }
                    })
                } else if authService.currentUser == nil {
                    // ログイン済みだがユーザーデータなし: ローディング
                    ProgressView("読み込み中...")
                } else {
                    // ログイン済み: メイン機能
                    letterMainContent
                }
            }
            .navigationTitle("大切な人への手紙")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if authService.isSignedIn {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button(action: { showingProfileEdit = true }) {
                                Label("プロフィール編集", systemImage: "person.circle")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                showingSignOutConfirmation = true
                            } label: {
                                Label("サインアウト", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        } label: {
                            if let user = authService.currentUser {
                                Text(user.emoji)
                                    .font(.title2)
                            } else {
                                Image(systemName: "person.circle")
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingProfileSetup) {
                LetterProfileSetupView(isEditMode: false) {
                    showingProfileSetup = false
                }
                .interactiveDismissDisabled()
            }
            .sheet(isPresented: $showingProfileEdit) {
                LetterProfileSetupView(isEditMode: true)
            }
            .alert("サインアウト", isPresented: $showingSignOutConfirmation) {
                Button("キャンセル", role: .cancel) { }
                Button("サインアウト", role: .destructive) {
                    try? authService.signOut()
                }
            } message: {
                Text("再度サインインすればデータは復元されます")
            }
            .alert("E2EE（エンドツーエンド暗号化）", isPresented: $showingE2EEInfo) {
                Button("OK") { }
            } message: {
                Text("手紙の内容はあなたと相手だけが読めます。\n\n運営を含め、第三者が手紙を読むことは技術的に不可能です。")
            }
        }
    }
    
    // メイン機能コンテンツ
    private var letterMainContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // ユーザー情報カード
                if let user = authService.currentUser {
                    userInfoCard(user: user)
                }
                
                // アクションボタン
                VStack(spacing: 16) {
                    // 友達を招待（タップで即座に共有シート表示）
                    Button(action: generateAndShareInvite) {
                        HStack(spacing: 16) {
                            ZStack {
                                Image(systemName: "person.badge.plus")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 50, height: 50)
                                    .background(Color.blue)
                                    .cornerRadius(12)
                                
                                if isGeneratingInvite {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("友達を招待")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("リンクを送って友達を追加")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(isGeneratingInvite)
                    
                    // 手紙を書く
                    Button(action: {
                        preselectedFriend = nil
                        showingLetterEditor = true
                    }) {
                        actionButton(
                            icon: "square.and.pencil",
                            title: "手紙を書く",
                            subtitle: "大切な人に手紙を送る",
                            color: .purple
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // 受信した手紙
                    NavigationLink {
                        // TODO: 受信手紙一覧
                        Text("受信した手紙（Phase 6で実装）")
                    } label: {
                        actionButton(
                            icon: "envelope.open.fill",
                            title: "受信した手紙",
                            subtitle: "届いた手紙を見る",
                            color: .green
                        )
                    }
                }
                .padding(.horizontal)
                
                // 友達リスト
                friendsSection
                
                // デバッグセクション（リリースビルドでは非表示）
                #if DEBUG
                debugSection
                #endif
            }
            .padding(.vertical)
        }
        .onAppear {
            pairingService.startListeningToFriends()
            pairingService.startListeningToPendingRequests()
        }
        .onDisappear {
            pairingService.stopListening()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = inviteURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showingRequests) {
            FriendRequestsView()
        }
        .sheet(isPresented: $showingLetterEditor) {
            SharedLetterEditorView(preselectedFriend: preselectedFriend)
        }
        .sheet(isPresented: $deepLinkHandler.showInviteConfirmation) {
            InviteConfirmationView()
        }
        .alert("友達を削除", isPresented: $showingRemoveFriendConfirmation) {
            Button("キャンセル", role: .cancel) { }
            Button("削除", role: .destructive) {
                if let friend = friendToRemove {
                    removeFriend(friend)
                }
            }
        } message: {
            if let friend = friendToRemove {
                Text("\(friend.friendName)さんを友達から削除しますか？\n\n相手もあなたを友達から削除されます。")
            }
        }
    }
    
    // 招待リンクを生成して共有シートを表示
    private func generateAndShareInvite() {
        isGeneratingInvite = true
        
        _Concurrency.Task {
            do {
                let link = try await pairingService.createInviteLink()
                await MainActor.run {
                    inviteURL = link.shareURL
                    isGeneratingInvite = false
                    showingShareSheet = true
                }
            } catch {
                await MainActor.run {
                    isGeneratingInvite = false
                }
            }
        }
    }
    
    private func removeFriend(_ friend: PairingService.Friend) {
        // テストデータ（test-で始まる）はローカルから削除
        if friend.odic.hasPrefix("test-") {
            pairingService.friends.removeAll { $0.id == friend.id }
        } else {
            _Concurrency.Task {
                try? await pairingService.removeFriend(friend)
            }
        }
    }
    
    // ユーザー情報カード
    private func userInfoCard(user: AuthService.LetterUser) -> some View {
        HStack(spacing: 16) {
            // 名前とアイコン（タップでプロフィール編集）
            Button(action: { showingProfileEdit = true }) {
                HStack(spacing: 12) {
                    Text(user.emoji)
                        .font(.system(size: 44))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("タップで編集")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // E2EEバッジ（タップで説明表示）
            Button(action: { showingE2EEInfo = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                    Text("E2EE")
                        .font(.caption)
                    Image(systemName: "info.circle")
                        .font(.caption2)
                }
                .foregroundColor(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.15))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .padding(.horizontal)
    }
    
    // アクションボタン
    private func actionButton(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(color)
                .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
    
    // 友達セクション
    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ヘッダー
            HStack {
                Text("友達")
                    .font(.headline)
                
                Spacer()
                
                // リクエストバッジ
                if !pairingService.pendingRequests.isEmpty {
                    Button(action: { showingRequests = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "bell.fill")
                            Text("\(pairingService.pendingRequests.count)")
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal)
            
            if pairingService.friends.isEmpty {
                // 空の状態
                VStack(spacing: 16) {
                    Image(systemName: "person.2.fill")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    
                    Text("まだ友達がいません")
                        .foregroundColor(.secondary)
                    
                    Text("「友達を招待」から友達を追加しましょう")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Color(.systemGray6))
                .cornerRadius(16)
                .padding(.horizontal)
            } else {
                // 友達一覧
                VStack(spacing: 8) {
                    ForEach(pairingService.friends) { friend in
                        friendRow(friend)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // 友達行
    private func friendRow(_ friend: PairingService.Friend) -> some View {
        HStack(spacing: 12) {
            Text(friend.friendEmoji)
                .font(.largeTitle)
            
            Text(friend.friendName)
                .font(.headline)
            
            Spacer()
            
            // 手紙を書くボタン
            Button(action: {
                preselectedFriend = friend
                showingLetterEditor = true
            }) {
                Image(systemName: "square.and.pencil")
                    .foregroundColor(.purple)
            }
            .buttonStyle(.plain)
            
            // 削除ボタン
            Button(action: {
                friendToRemove = friend
                showingRemoveFriendConfirmation = true
            }) {
                Image(systemName: "person.badge.minus")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }
    
    // MARK: - Debug Section (Release builds will not include this)
    
    #if DEBUG
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🛠 デバッグ")
                    .font(.headline)
                    .foregroundColor(.orange)
                
                Spacer()
                
                Text("リリース時は非表示")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            VStack(spacing: 8) {
                // テスト友達を追加
                Button(action: addTestFriend) {
                    HStack {
                        Image(systemName: "person.fill.badge.plus")
                            .foregroundColor(.green)
                        Text("テスト友達を追加")
                        Spacer()
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                // テストリクエストを追加
                Button(action: addTestRequest) {
                    HStack {
                        Image(systemName: "bell.badge.fill")
                            .foregroundColor(.blue)
                        Text("テスト友達リクエストを追加")
                        Spacer()
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                // データをクリア
                Button(action: clearTestData) {
                    HStack {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.red)
                        Text("テストデータをクリア")
                        Spacer()
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                // 招待リンク受信テスト
                Button(action: testDeepLink) {
                    HStack {
                        Image(systemName: "link")
                            .foregroundColor(.purple)
                        Text("招待リンク受信をテスト")
                        Spacer()
                    }
                    .padding()
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(16)
        .padding(.horizontal)
    }
    
    private func addTestFriend() {
        guard let currentUser = authService.currentUser else { return }
        
        let testFriend = PairingService.Friend(
            id: UUID().uuidString,
            odic: "test-user-\(Int.random(in: 1000...9999))",
            friendEmoji: ["🐶", "🐱", "🐰", "🦊", "🐻", "🐼"].randomElement()!,
            friendName: ["太郎", "花子", "健太", "美咲", "翔太", "さくら"].randomElement()!,
            friendPublicKey: "test-public-key",
            pendingLetterCount: Int.random(in: 0...3)
        )
        
        // ローカルに追加（Firestoreには保存しない）
        pairingService.friends.append(testFriend)
    }
    
    private func addTestRequest() {
        let testRequest = PairingService.FriendRequest(
            id: UUID().uuidString,
            fromUserId: "test-user-\(Int.random(in: 1000...9999))",
            fromUserEmoji: ["🐶", "🐱", "🐰", "🦊", "🐻", "🐼"].randomElement()!,
            fromUserName: ["太郎", "花子", "健太", "美咲", "翔太", "さくら"].randomElement()!,
            fromUserPublicKey: "test-public-key",
            toUserId: authService.currentUser?.id ?? "",
            status: .pending,
            createdAt: Date()
        )
        
        // ローカルに追加（Firestoreには保存しない）
        pairingService.pendingRequests.append(testRequest)
    }
    
    private func clearTestData() {
        pairingService.friends.removeAll()
        pairingService.pendingRequests.removeAll()
    }
    
    private func testDeepLink() {
        // テスト用の招待リンクデータを設定
        let testLink = PairingService.InviteLink(
            id: "test-invite-\(Int.random(in: 1000...9999))",
            userId: "test-user-\(Int.random(in: 1000...9999))",
            userEmoji: ["🐶", "🐱", "🐰", "🦊", "🐻", "🐼"].randomElement()!,
            userName: ["太郎", "花子", "健太", "美咲", "翔太", "さくら"].randomElement()!,
            userPublicKey: "test-public-key",
            expiresAt: Date().addingTimeInterval(24 * 60 * 60),
            createdAt: Date()
        )
        
        deepLinkHandler.inviteLinkData = testLink
        deepLinkHandler.pendingInviteLinkId = testLink.id
        deepLinkHandler.showInviteConfirmation = true
    }
    #endif
}

#Preview {
    LetterSharingView()
}
