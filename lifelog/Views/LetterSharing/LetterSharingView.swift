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
    @State private var showingProfileSetup = false
    @State private var showingProfileEdit = false
    @State private var showingSignOutConfirmation = false
    @State private var showingE2EEInfo = false
    
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
                    // 友達を招待
                    NavigationLink {
                        // TODO: 友達招待画面
                        Text("友達を招待（Phase 4で実装）")
                    } label: {
                        actionButton(
                            icon: "person.badge.plus",
                            title: "友達を招待",
                            subtitle: "リンクを送って友達を追加",
                            color: .blue
                        )
                    }
                    
                    // 手紙を書く
                    NavigationLink {
                        // TODO: 手紙作成画面
                        Text("手紙を書く（Phase 5で実装）")
                    } label: {
                        actionButton(
                            icon: "square.and.pencil",
                            title: "手紙を書く",
                            subtitle: "大切な人に手紙を送る",
                            color: .purple
                        )
                    }
                    
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
                
                // 友達リスト（プレースホルダー）
                friendsSection
            }
            .padding(.vertical)
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
            Text("友達")
                .font(.headline)
                .padding(.horizontal)
            
            // プレースホルダー
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
        }
    }
}

#Preview {
    LetterSharingView()
}
