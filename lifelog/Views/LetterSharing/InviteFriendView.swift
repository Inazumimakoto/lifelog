//
//  InviteFriendView.swift
//  lifelog
//
//  友達招待画面
//

import SwiftUI

/// 友達招待画面
struct InviteFriendView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var pairingService = PairingService.shared
    
    @State private var inviteLink: PairingService.InviteLink?
    @State private var isGenerating = false
    @State private var showingShareSheet = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                
                // アイコン
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                }
                
                // 説明
                VStack(spacing: 12) {
                    Text("友達を招待")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("招待リンクを送って友達を追加しましょう")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
                
                // 招待リンク情報
                if let link = inviteLink {
                    VStack(spacing: 16) {
                        // 有効期限
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.secondary)
                            Text("有効期限: \(formatExpiry(link.expiresAt))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // 共有ボタン
                        Button(action: { showingShareSheet = true }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("招待リンクを送る")
                            }
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        
                        // 新しいリンクを生成
                        Button(action: generateNewLink) {
                            Text("新しいリンクを生成")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 32)
                } else {
                    // リンク生成ボタン
                    Button(action: generateNewLink) {
                        HStack {
                            if isGenerating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "link.badge.plus")
                                Text("招待リンクを生成")
                            }
                        }
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isGenerating)
                    .padding(.horizontal, 32)
                }
                
                // エラーメッセージ
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // 注意書き
                Text("招待リンクは24時間有効です")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 32)
            }
            .navigationTitle("友達を招待")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = inviteLink?.shareURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }
    
    private func generateNewLink() {
        isGenerating = true
        errorMessage = nil
        
        _Concurrency.Task {
            do {
                let link = try await pairingService.createInviteLink()
                await MainActor.run {
                    inviteLink = link
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }
    
    private func formatExpiry(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    InviteFriendView()
}
