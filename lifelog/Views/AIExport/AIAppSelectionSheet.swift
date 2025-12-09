//
//  AIAppSelectionSheet.swift
//  lifelog
//
//  Created by Codex on 2025/12/09.
//

import SwiftUI
import UIKit

// MARK: - AIアプリモデル

struct AIAppInfo: Identifiable {
    let id = UUID()
    let name: String
    let tagline: String
    let color: Color
    let emoji: String
    let urlScheme: String
    let appStoreID: String
    
    var appStoreURL: URL? {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)")
    }
    
    var schemeURL: URL? {
        URL(string: urlScheme)
    }
}

// MARK: - AIアプリ一覧

extension AIAppInfo {
    static let allApps: [AIAppInfo] = [
        AIAppInfo(
            name: "ChatGPT",
            tagline: "みんな使ってる定番",
            color: Color(red: 0.16, green: 0.65, blue: 0.53), // OpenAI Green
            emoji: "🟢",
            urlScheme: "chatgpt://",
            appStoreID: "6448311069"
        ),
        AIAppInfo(
            name: "Gemini",
            tagline: "大量データの分析向き",
            color: Color(red: 0.26, green: 0.52, blue: 0.96), // Google Blue
            emoji: "🔵",
            urlScheme: "googlegemini://",
            appStoreID: "6477141669"
        ),
        AIAppInfo(
            name: "Claude",
            tagline: "じっくり相談したい人向き",
            color: Color(red: 0.85, green: 0.47, blue: 0.34), // Anthropic Brown/Orange
            emoji: "🟤",
            urlScheme: "claude://",
            appStoreID: "6473753684"
        ),
        AIAppInfo(
            name: "Grok",
            tagline: "率直な意見がほしい人向き",
            color: Color.black,
            emoji: "⚫",
            urlScheme: "twitter://", // X(Twitter)アプリを開く
            appStoreID: "333903271" // X(Twitter)のApp Store ID
        ),
        AIAppInfo(
            name: "Poe",
            tagline: "いろんなAIを試したい人向き",
            color: Color(red: 0.6, green: 0.4, blue: 0.8), // Poe Purple
            emoji: "🟣",
            urlScheme: "https://poe.com", // Webサイトを開く（アプリがあれば遷移）
            appStoreID: "1640745955"
        )
    ]
}

// MARK: - AIアプリ選択シート

struct AIAppSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // 成功バナー
            successBanner
            
            // AIアプリセクション
            VStack(alignment: .leading, spacing: 12) {
                Text("AIアプリを開く")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                
                // 横スクロールのAIカード
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(AIAppInfo.allApps) { app in
                            AIAppCard(app: app)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            
            Spacer()
            
            // 閉じるボタン
            Button("閉じる") {
                dismiss()
            }
            .font(.body.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - 成功バナー
    
    private var successBanner: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                
                Text("コピー完了！")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            
            Text("AIアプリを開いて貼り付けてください")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // 一時チャット推奨
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("「一時チャット」や「新しいチャット」での利用がおすすめです")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.1))
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - AIアプリカード

private struct AIAppCard: View {
    let app: AIAppInfo
    
    var body: some View {
        Button {
            openApp()
        } label: {
            HStack(spacing: 12) {
                // テキスト
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(app.tagline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer(minLength: 0)
                
                // 矢印
                Image(systemName: "arrow.up.forward")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(width: 220)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.tertiarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
    
    private func openApp() {
        HapticManager.light()
        
        // まずアプリを開こうとする。開けなければApp Storeへ
        if let url = app.schemeURL {
            UIApplication.shared.open(url, options: [:]) { success in
                if !success, let appStoreURL = app.appStoreURL {
                    UIApplication.shared.open(appStoreURL)
                }
            }
        } else if let url = app.appStoreURL {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Preview

#Preview {
    AIAppSelectionSheet()
}
