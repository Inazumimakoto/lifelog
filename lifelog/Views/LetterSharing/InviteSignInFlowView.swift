//
//  InviteSignInFlowView.swift
//  lifelog
//
//  招待リンクからのサインインフロー
//

import SwiftUI

/// 招待リンク用サインインフロー
struct InviteSignInFlowView: View {
    @Environment(\.dismiss) private var dismiss
    private let authService = AuthService.shared
    @ObservedObject private var handler = DeepLinkHandler.shared
    @State private var showProfileSetup = false

    var body: some View {
        NavigationStack {
            LetterSignInContent(title: "友達からの招待",
                                subtitle: "大切な人への手紙を始めましょう",
                                onSignInComplete: completeSignIn,
                                onCancel: cancel)
            .navigationTitle("大切な人への手紙")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる", action: cancel)
                }
            }
            .sheet(isPresented: $showProfileSetup) {
                InviteProfileSetupView {
                    handler.onSignInCompleted()
                    dismiss()
                }
            }
        }
    }

    private func completeSignIn() {
        // Only the invite flow needs a profile before continuing the invitation.
        if authService.currentUser?.displayName.isEmpty != false {
            showProfileSetup = true
        } else {
            handler.onSignInCompleted()
            dismiss()
        }
    }

    private func cancel() {
        handler.clear()
        dismiss()
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
