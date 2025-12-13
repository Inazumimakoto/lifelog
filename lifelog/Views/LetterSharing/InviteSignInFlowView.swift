//
//  InviteSignInFlowView.swift
//  lifelog
//
//  招待リンクからのサインインフロー
//

import SwiftUI
import AuthenticationServices

/// 招待リンク用サインインフロー
struct InviteSignInFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var handler = DeepLinkHandler.shared
    
    @AppStorage("letterSharingGuidelinesAccepted") private var guidelinesAccepted = false
    @State private var showingGuidelinesAlert = false
    @State private var pendingSignInResult: Result<ASAuthorization, Error>?
    @State private var showProfileSetup = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                
                // ヘッダー（LetterSignInViewと同じデザイン）
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.purple, Color.blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white)
                    }
                    
                    Text("友達からの招待")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("大切な人への手紙を始めましょう")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 機能説明
                VStack(alignment: .leading, spacing: 16) {
                    featureRow(icon: "lock.shield.fill", text: "運営も読めない暗号化(E2EE)")
                    featureRow(icon: "eye.slash.fill", text: "あなたと相手だけが読める")
                    featureRow(icon: "clock.fill", text: "日時を指定して届ける")
                    featureRow(icon: "sparkles", text: "サプライズで届く手紙")
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Sign in with Apple ボタン
                VStack(spacing: 16) {
                    SignInWithAppleButton(
                        onRequest: { request in
                            let appleRequest = authService.createAppleSignInRequest()
                            request.requestedScopes = appleRequest.requestedScopes
                            request.nonce = appleRequest.nonce
                        },
                        onCompletion: { result in
                            // 初回はガイドライン確認を表示
                            if !guidelinesAccepted {
                                pendingSignInResult = result
                                showingGuidelinesAlert = true
                            } else {
                                proceedWithSignIn(result: result)
                            }
                        }
                    )
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 50)
                    .padding(.horizontal, 32)
                    
                    // キャンセル
                    Button("キャンセル") {
                        handler.clear()
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                    
                    // エラーメッセージ
                    if let error = authService.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                
                // 注意書き
                VStack(spacing: 4) {
                    Text("💡 メールアドレスは使用しないので「非公開」がおすすめ")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("⚠️ 嫌がらせや犯罪目的での利用は禁止です")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("サインインすると利用規約に同意したことになります")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle("大切な人への手紙")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        handler.clear()
                        dismiss()
                    }
                }
            }
            .overlay {
                if authService.isLoading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
            .alert("ご利用にあたって", isPresented: $showingGuidelinesAlert) {
                Button("同意して続ける") {
                    guidelinesAccepted = true
                    if let result = pendingSignInResult {
                        proceedWithSignIn(result: result)
                    }
                }
                Button("キャンセル", role: .cancel) {
                    pendingSignInResult = nil
                }
            } message: {
                Text("この機能を嫌がらせや犯罪目的で利用することは固く禁止されています。\n\n違反が確認された場合、アカウント停止や法的措置を取る場合があります。")
            }
            .fullScreenCover(isPresented: $showProfileSetup) {
                InviteProfileSetupView {
                    // プロフィール設定完了
                    handler.onSignInCompleted()
                    dismiss()
                }
            }
        }
    }
    
    private func proceedWithSignIn(result: Result<ASAuthorization, Error>) {
        _Concurrency.Task {
            await authService.handleAppleSignIn(result: result)
            
            await MainActor.run {
                if authService.isSignedIn {
                    // プロフィール未設定ならセットアップ画面へ
                    if authService.currentUser?.displayName.isEmpty != false {
                        showProfileSetup = true
                    } else {
                        // 既にプロフィール設定済み → 招待処理続行
                        handler.onSignInCompleted()
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            Text(text)
                .font(.subheadline)
        }
    }
}

/// 招待フロー用プロフィール設定
struct InviteProfileSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var authService = AuthService.shared
    
    let onComplete: () -> Void
    
    @State private var displayName = ""
    @State private var selectedEmoji = "😊"
    @State private var isSaving = false
    
    private let emojiOptions = ["😊", "😎", "🥳", "🤗", "😇", "🌟", "🎉", "💫", "🌈", "🦋", "🐱", "🐶"]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                
                // 絵文字選択
                VStack(spacing: 16) {
                    Text(selectedEmoji)
                        .font(.system(size: 80))
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(emojiOptions, id: \.self) { emoji in
                                Text(emoji)
                                    .font(.system(size: 32))
                                    .padding(8)
                                    .background(
                                        selectedEmoji == emoji ? Color.blue.opacity(0.2) : Color.clear
                                    )
                                    .cornerRadius(12)
                                    .onTapGesture {
                                        selectedEmoji = emoji
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                // 名前入力
                VStack(alignment: .leading, spacing: 8) {
                    Text("表示名")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("ニックネームを入力", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // 保存ボタン
                Button {
                    saveProfile()
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("始める")
                        }
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(displayName.isEmpty ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(displayName.isEmpty || isSaving)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .navigationTitle("プロフィール設定")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func saveProfile() {
        isSaving = true
        
        _Concurrency.Task {
            try? await authService.updateProfile(emoji: selectedEmoji, displayName: displayName)
            
            await MainActor.run {
                isSaving = false
                onComplete()
            }
        }
    }
}
