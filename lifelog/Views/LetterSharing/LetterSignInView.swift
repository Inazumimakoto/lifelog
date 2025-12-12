//
//  LetterSignInView.swift
//  lifelog
//
//  Sign in with Apple ログイン画面
//

import SwiftUI
import AuthenticationServices

/// Sign in with Apple ログイン画面
struct LetterSignInView: View {
    @ObservedObject private var authService = AuthService.shared
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("letterSharingGuidelinesAccepted") private var guidelinesAccepted = false
    @State private var showingGuidelinesAlert = false
    @State private var pendingSignInResult: Result<ASAuthorization, Error>?
    
    var onSignInComplete: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // ヘッダー
            VStack(spacing: 16) {
                // アイコン
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
                
                Text("大切な人への手紙")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("友達と手紙を送り合おう")
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
    }
    
    private func proceedWithSignIn(result: Result<ASAuthorization, Error>) {
        _Concurrency.Task {
            await authService.handleAppleSignIn(result: result)
            if authService.isSignedIn {
                onSignInComplete?()
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

#Preview {
    LetterSignInView()
}
