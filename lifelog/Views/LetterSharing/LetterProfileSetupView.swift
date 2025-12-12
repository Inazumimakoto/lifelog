//
//  LetterProfileSetupView.swift
//  lifelog
//
//  プロフィール設定画面（絵文字 + 表示名）
//

import SwiftUI

/// プロフィール設定画面
struct LetterProfileSetupView: View {
    @ObservedObject private var authService = AuthService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedEmoji: String = "😊"
    @State private var displayName: String = ""
    @State private var showingEmojiPicker = false
    @State private var isSaving = false
    
    var isEditMode: Bool = false
    var onComplete: (() -> Void)?
    
    // 人気の絵文字
    private let popularEmojis = [
        "😊", "😄", "🥰", "😎", "🤗", "😇", "🌟", "⭐️",
        "💫", "✨", "🌈", "🦋", "🌸", "🌺", "🍀", "🌻",
        "🎉", "🎊", "💝", "💖", "💕", "❤️", "🧡", "💛",
        "💚", "💙", "💜", "🖤", "🤍", "🤎", "🐱", "🐶",
        "🐰", "🦊", "🐻", "🐼", "🦁", "🐯", "🐨", "🐸"
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                
                // タイトル
                VStack(spacing: 8) {
                    Text(isEditMode ? "プロフィール編集" : "プロフィール設定")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("友達に表示される名前とアイコンを設定してください")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // 絵文字アイコン
                Button(action: { showingEmojiPicker = true }) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                        
                        Text(selectedEmoji)
                            .font(.system(size: 60))
                        
                        // 編集アイコン
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "pencil.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                    .background(Circle().fill(.white))
                            }
                        }
                        .frame(width: 120, height: 120)
                    }
                }
                .buttonStyle(.plain)
                
                // 表示名入力
                VStack(alignment: .leading, spacing: 8) {
                    Text("表示名")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("表示名を入力", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                // 保存ボタン
                Button(action: saveProfile) {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text(isEditMode ? "保存" : "始める")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        displayName.isEmpty ? Color.gray : Color.blue
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(displayName.isEmpty || isSaving)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isEditMode {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") {
                            dismiss()
                        }
                    }
                }
            }
            .sheet(isPresented: $showingEmojiPicker) {
                emojiPickerSheet
            }
            .onAppear {
                if let user = authService.currentUser {
                    selectedEmoji = user.emoji
                    displayName = user.displayName
                }
            }
        }
    }
    
    // 絵文字選択シート
    private var emojiPickerSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                    ForEach(popularEmojis, id: \.self) { emoji in
                        Button(action: {
                            selectedEmoji = emoji
                            showingEmojiPicker = false
                        }) {
                            Text(emoji)
                                .font(.largeTitle)
                                .frame(width: 44, height: 44)
                                .background(
                                    selectedEmoji == emoji
                                        ? Color.blue.opacity(0.2)
                                        : Color.clear
                                )
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("アイコンを選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        showingEmojiPicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    // プロフィールを保存
    private func saveProfile() {
        guard !displayName.isEmpty else { return }
        
        isSaving = true
        
        _Concurrency.Task {
            do {
                try await authService.updateProfile(emoji: selectedEmoji, displayName: displayName)
                
                await MainActor.run {
                    isSaving = false
                    onComplete?()
                    if isEditMode {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                }
            }
        }
    }
}

#Preview {
    LetterProfileSetupView()
}
