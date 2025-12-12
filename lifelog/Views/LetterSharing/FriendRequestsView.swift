//
//  FriendRequestsView.swift
//  lifelog
//
//  友達リクエスト一覧画面（承認/拒否）
//

import SwiftUI

/// 友達リクエスト一覧画面
struct FriendRequestsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var pairingService = PairingService.shared
    
    @State private var processingRequestId: String?
    
    var body: some View {
        NavigationStack {
            Group {
                if pairingService.pendingRequests.isEmpty {
                    emptyStateView
                } else {
                    requestListView
                }
            }
            .navigationTitle("友達リクエスト")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                pairingService.startListeningToPendingRequests()
            }
            .onDisappear {
                pairingService.stopListening()
            }
            .onChange(of: pairingService.pendingRequests.count) { oldCount, newCount in
                // リクエストがあったがなくなった場合は自動で閉じる
                if oldCount > 0 && newCount == 0 {
                    dismiss()
                }
            }
        }
    }
    
    // 空の状態
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("友達リクエストはありません")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
    
    // リクエスト一覧
    private var requestListView: some View {
        List {
            ForEach(pairingService.pendingRequests) { request in
                requestRow(request)
            }
        }
        .listStyle(.insetGrouped)
    }
    
    // リクエスト行
    private func requestRow(_ request: PairingService.FriendRequest) -> some View {
        HStack(spacing: 12) {
            // アイコン
            Text(request.fromUserEmoji)
                .font(.largeTitle)
            
            // 名前
            VStack(alignment: .leading, spacing: 2) {
                Text(request.fromUserName)
                    .font(.headline)
                Text(formatDate(request.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // アクションボタン
            if processingRequestId == request.id {
                ProgressView()
            } else {
                HStack(spacing: 8) {
                    // 拒否ボタン
                    Button(action: { rejectRequest(request) }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    
                    // 承認ボタン
                    Button(action: { acceptRequest(request) }) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func acceptRequest(_ request: PairingService.FriendRequest) {
        processingRequestId = request.id
        
        // テストデータ（test-で始まる）はローカルで処理
        if request.fromUserId.hasPrefix("test-") {
            // テスト友達を追加
            let testFriend = PairingService.Friend(
                id: UUID().uuidString,
                odic: request.fromUserId,
                friendEmoji: request.fromUserEmoji,
                friendName: request.fromUserName,
                friendPublicKey: request.fromUserPublicKey,
                pendingLetterCount: 0
            )
            pairingService.friends.append(testFriend)
            
            // リクエストを削除
            pairingService.pendingRequests.removeAll { $0.id == request.id }
            processingRequestId = nil
        } else {
            _Concurrency.Task {
                do {
                    try await pairingService.acceptFriendRequest(request)
                    await MainActor.run {
                        processingRequestId = nil
                    }
                } catch {
                    await MainActor.run {
                        processingRequestId = nil
                    }
                }
            }
        }
    }
    
    private func rejectRequest(_ request: PairingService.FriendRequest) {
        processingRequestId = request.id
        
        // テストデータ（test-で始まる）はローカルで処理
        if request.fromUserId.hasPrefix("test-") {
            pairingService.pendingRequests.removeAll { $0.id == request.id }
            processingRequestId = nil
        } else {
            _Concurrency.Task {
                do {
                    try await pairingService.rejectFriendRequest(request)
                    await MainActor.run {
                        processingRequestId = nil
                    }
                } catch {
                    await MainActor.run {
                        processingRequestId = nil
                    }
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    FriendRequestsView()
}
