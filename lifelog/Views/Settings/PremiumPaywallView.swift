//
//  PremiumPaywallView.swift
//  lifelog
//
//  Created by Codex on 2026/02/06.
//

import SwiftUI
import StoreKit

struct PremiumPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var monetization = MonetizationService.shared
    @State private var isPurchasing = false
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    featureList
                    productsSection
                    restoreSection
                }
                .padding()
            }
            .navigationTitle("プレミアム")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .task {
                await monetization.loadProductsIfNeeded(force: false)
            }
            .onChange(of: monetization.errorMessage) { _, newValue in
                if let newValue, newValue.isEmpty == false {
                    alertMessage = newValue
                }
            }
            .onChange(of: monetization.isPremiumUnlocked) { _, unlocked in
                if unlocked {
                    ToastManager.shared.show(emoji: "🎉", message: "プレミアムが有効になりました")
                    dismiss()
                }
            }
            .alert("お知らせ", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if $0 == false { alertMessage = nil } }
            )) {
                Button("OK") { }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("海外版プレミアム")
                .font(.title3.bold())
            Text("習慣の草表示、振り返り地図、手紙機能、登録上限の解除が使えるようになります。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 8) {
            premiumFeatureRow("習慣の草表示を解放")
            premiumFeatureRow("振り返りカレンダーの地図表示を解放")
            premiumFeatureRow("未来への手紙 / 大切な人への手紙を解放")
            premiumFeatureRow("習慣とカウントダウンの登録上限を解除")
        }
    }

    private func premiumFeatureRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private var productsSection: some View {
        if monetization.isJapanStorefront {
            PremiumLockCard(title: "日本ストアは無料です",
                            message: "日本ストアでは全機能を無料で利用できます。",
                            actionTitle: "閉じる",
                            action: { dismiss() })
        } else if monetization.isLoadingProducts && monetization.availableProducts.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                Text("プラン情報を読み込み中...")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
        } else if monetization.availableProducts.isEmpty {
            PremiumLockCard(title: "プラン情報を取得できませんでした",
                            message: "通信状況を確認して、しばらくしてから再試行してください。",
                            actionTitle: "再読み込み",
                            action: { _Concurrency.Task { await monetization.loadProductsIfNeeded(force: true) } })
        } else {
            VStack(spacing: 10) {
                ForEach(monetization.availableProducts, id: \.id) { product in
                    Button {
                        purchase(product)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(product.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(product.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            Text(product.displayPrice)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                        .padding()
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isPurchasing)
                }
            }
        }
    }

    private var restoreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                _Concurrency.Task {
                    isPurchasing = true
                    _ = await monetization.restorePurchases()
                    isPurchasing = false
                }
            } label: {
                HStack {
                    if isPurchasing {
                        ProgressView()
                    }
                    Text("購入を復元")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isPurchasing)
            Text("同じApple IDで購入済みの場合に利用してください。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private func purchase(_ product: Product) {
        _Concurrency.Task {
            isPurchasing = true
            let purchased = await monetization.purchase(product)
            isPurchasing = false
            if purchased == false && monetization.errorMessage == nil {
                alertMessage = "購入は完了しませんでした。"
            }
        }
    }
}

#Preview {
    PremiumPaywallView()
}
