//
//  ReceivedLettersView.swift
//  lifelog
//
//  大切な人への手紙 - 受信した手紙一覧
//

import SwiftUI

/// 受信した手紙一覧画面
struct ReceivedLettersView: View {
    @State private var letters: [LetterReceivingService.ReceivedLetter] = []
    @State private var isLoading = true
    @State private var selectedLetter: LetterReceivingService.ReceivedLetter?
    @State private var showingLetterDetail = false
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("読み込み中...")
            } else if letters.isEmpty {
                emptyStateView
            } else {
                letterListView
            }
        }
        .navigationTitle("受信した手紙")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadLetters()
        }
        .refreshable {
            await loadLetters()
        }
        .sheet(isPresented: $showingLetterDetail) {
            if let letter = selectedLetter {
                SharedLetterOpeningView(letter: letter)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.open")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("手紙はまだ届いていません")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("大切な人からの手紙を待ちましょう")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var letterListView: some View {
        List {
            ForEach(letters) { letter in
                Button(action: {
                    selectedLetter = letter
                    showingLetterDetail = true
                }) {
                    letterRow(letter)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private func letterRow(_ letter: LetterReceivingService.ReceivedLetter) -> some View {
        HStack(spacing: 12) {
            // 送信者アイコン
            Text(letter.senderEmoji)
                .font(.largeTitle)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(letter.senderName)
                    .font(.headline)
                
                Text(formatDate(letter.deliveredAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 未開封バッジ
            if letter.status == "delivered" {
                Circle()
                    .fill(.blue)
                    .frame(width: 10, height: 10)
            }
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
    
    private func loadLetters() async {
        isLoading = true
        do {
            letters = try await LetterReceivingService.shared.getReceivedLetters()
        } catch {
            print("手紙取得エラー: \(error.localizedDescription)")
        }
        isLoading = false
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日 H:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Shared Letter Opening View

/// 大切な人からの手紙開封画面
struct SharedLetterOpeningView: View {
    @Environment(\.dismiss) private var dismiss
    let letter: LetterReceivingService.ReceivedLetter
    
    @State private var isOpening = false
    @State private var decryptedLetter: LetterReceivingService.DecryptedLetter?
    @State private var errorMessage: String?
    @State private var showContent = false
    
    var body: some View {
        NavigationStack {
            Group {
                if isOpening {
                    openingAnimation
                } else if let decrypted = decryptedLetter {
                    letterContentView(decrypted)
                } else {
                    sealedLetterView
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // 封印された手紙
    private var sealedLetterView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // 送信者情報
            VStack(spacing: 16) {
                Text(letter.senderEmoji)
                    .font(.system(size: 80))
                
                Text("\(letter.senderName)さんからの手紙")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(formatDate(letter.deliveredAt))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // E2EE説明
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundColor(.green)
                Text("E2EE暗号化で保護されています")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)
            
            Spacer()
            
            // エラーメッセージ
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            
            // 開封ボタン
            Button(action: openLetter) {
                HStack {
                    Image(systemName: "envelope.open.fill")
                    Text("開封する")
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }
    
    // 開封アニメーション
    private var openingAnimation: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("復号中...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
    
    // 手紙の内容
    private func letterContentView(_ decrypted: LetterReceivingService.DecryptedLetter) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // ヘッダー
                HStack(spacing: 12) {
                    Text(decrypted.senderEmoji)
                        .font(.largeTitle)
                    
                    VStack(alignment: .leading) {
                        Text("\(decrypted.senderName)さんより")
                            .font(.headline)
                        
                        Text(formatDate(decrypted.deliveredAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
                
                // 本文
                Text(decrypted.content)
                    .font(.body)
                    .lineSpacing(8)
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
                
                // 写真
                if !decrypted.photos.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("📷 写真")
                            .font(.headline)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(decrypted.photos.indices, id: \.self) { index in
                                Image(uiImage: decrypted.photos[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
    
    private func openLetter() {
        isOpening = true
        errorMessage = nil
        
        _Concurrency.Task {
            do {
                let decrypted = try await LetterReceivingService.shared.openLetter(letterId: letter.id)
                
                await MainActor.run {
                    decryptedLetter = decrypted
                    isOpening = false
                    HapticManager.success()
                }
            } catch {
                await MainActor.run {
                    isOpening = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月d日 H:mm"
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        ReceivedLettersView()
    }
}
