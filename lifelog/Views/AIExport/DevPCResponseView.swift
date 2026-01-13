//
//  DevPCResponseView.swift
//  lifelog
//
//  開発者のPCからの回答を表示するシート
//  おお！回答！使い捨て！
//

import SwiftUI

struct DevPCResponseView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var service: DevPCLLMService
    
    let prompt: String
    let onDismiss: (() -> Void)?
    
    @State private var hasStarted = false
    @State private var showThinking = false
    
    init(prompt: String, service: DevPCLLMService = .shared, onDismiss: (() -> Void)? = nil) {
        self.prompt = prompt
        self.service = service
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // ステータスヘッダー
                    statusHeader
                    
                    // 思考過程（<think>タグの内容）
                    if !service.thinkingText.isEmpty {
                        thinkingSection
                    }
                    
                    // メイン回答
                    if !service.responseText.isEmpty {
                        responseSection
                    }
                    
                    // エラー表示
                    if let error = service.errorMessage {
                        errorSection(error)
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding()
            }
            .navigationTitle("🤖 開発者のPC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        service.cancel()
                        onDismiss?()
                        dismiss()
                    }
                }
                
                if !service.responseText.isEmpty && !service.isLoading {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            UIPasteboard.general.string = service.responseText
                            HapticManager.success()
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                footerInfo
            }
        }
        .task {
            if !hasStarted {
                hasStarted = true
                await service.fetchGlobalUsage()
                await service.ask(prompt: prompt)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var statusHeader: some View {
        HStack(spacing: 12) {
            if service.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                Text("おお！考え中！贅沢！")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else if service.errorMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("おお！問題！発生！")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else if !service.responseText.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("おお！回答！使い捨て！")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }
    
    private var thinkingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showThinking.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(.purple)
                    Text("思考過程")
                        .font(.subheadline.bold())
                    Spacer()
                    Image(systemName: showThinking ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundStyle(.primary)
            }
            
            if showThinking {
                Text(service.thinkingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private var responseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "text.bubble.fill")
                    .foregroundStyle(.blue)
                Text("回答")
                    .font(.subheadline.bold())
                Spacer()
            }
            
            Text(service.responseText)
                .font(.body)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private func errorSection(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.headline)
            }
            
            Text("開発者のPCが起動しているか確認してください。\nそれでもダメなら...また後で！")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var footerInfo: some View {
        VStack(spacing: 8) {
            Divider()
            
            HStack(spacing: 16) {
                Label("Powered by 開発者の電気代", systemImage: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if service.globalUsageCount > 0 {
                    Text("🌍 世界で\(service.globalUsageCount)回、開発者を泣かせました")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack {
                Image(systemName: "trash")
                    .font(.caption2)
                Text("この結果は保存されません")
                    .font(.caption2)
                
                Spacer()
                
                Text("残り \(service.remainingUsesThisWeek) 回/週")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        service.remainingUsesThisWeek > 0 ? Color.green.opacity(0.2) : Color.red.opacity(0.2),
                        in: Capsule()
                    )
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

#Preview {
    DevPCResponseView(prompt: "テスト")
}
