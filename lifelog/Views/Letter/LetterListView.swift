//
//  LetterListView.swift
//  lifelog
//
//  Created by AI for Letter to the Future feature
//

import SwiftUI

struct LetterListView: View {
    @EnvironmentObject var store: AppDataStore
    @ObservedObject private var monetization = MonetizationService.shared
    @State private var showEditor = false
    @State private var editingLetter: Letter?
    @State private var letterToOpen: Letter?
    @State private var showLetterOpening = false
    @State private var hasOpenedEnvelope = false
    @State private var showWelcome = false
    @State private var showPaywall = false
    
    @AppStorage("hasSeenLetterWelcome") private var hasSeenWelcome = false
    
    /// 配達日を過ぎた未開封の手紙（開封待ち）
    private var deliverableLetters: [Letter] {
        store.letters.filter { $0.status == .sealed && $0.isDeliverable }
            .sorted { $0.deliveryDate < $1.deliveryDate }
    }
    
    /// 開封済みの手紙
    private var openedLetters: [Letter] {
        store.letters.filter { $0.status == .opened }
            .sorted { ($0.openedAt ?? Date()) > ($1.openedAt ?? Date()) }
    }
    
    var body: some View {
        Group {
            if monetization.canUseLetters {
                List {
                    // 新規作成CTA（一番上）
                    Section {
                        Button {
                            editingLetter = nil
                            showEditor = true
                        } label: {
                            HStack {
                                Image(systemName: "pencil.and.outline")
                                    .font(.title2)
                                    .foregroundStyle(.orange)
                                Text("新しい手紙を書く")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    // 開封待ち（配達日を過ぎた未開封）
                    if !deliverableLetters.isEmpty {
                        Section {
                            ForEach(deliverableLetters) { letter in
                                deliverableRow(letter)
                            }
                        } header: {
                            Label("開封待ち", systemImage: "envelope.badge")
                        }
                    }
                    
                    // 開封済み
                    if !openedLetters.isEmpty {
                        Section {
                            ForEach(openedLetters) { letter in
                                openedRow(letter)
                            }
                            .onDelete { offsets in
                                deleteOpenedLetters(at: offsets)
                            }
                        } header: {
                            Label("開封済み", systemImage: "envelope.open")
                        }
                    }
                    
                    // 空の状態（何もない場合）
                    if deliverableLetters.isEmpty && openedLetters.isEmpty {
                        emptyState
                    }
                }
            } else {
                ScrollView {
                    PremiumLockCard(title: String(localized: "未来への手紙"),
                                    message: monetization.lettersMessage(),
                                    actionTitle: String(localized: "プランを見る")) {
                        showPaywall = true
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("未来への手紙")
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView()
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                LetterEditorView(letter: editingLetter)
            }
        }
        .fullScreenCover(isPresented: $showLetterOpening, onDismiss: {
            // 画面を閉じたタイミングで、かつ封筒を開封済みの場合のみステータスを更新
            if let letter = letterToOpen, hasOpenedEnvelope {
                withAnimation {
                    store.openLetter(letter.id)
                }
            }
            letterToOpen = nil
            hasOpenedEnvelope = false
        }) {
            Group {
                if let letter = letterToOpen {
                    LetterOpeningView(letter: letter) {
                        // アニメーション完了（封筒開封）時にフラグを立てる
                        hasOpenedEnvelope = true
                    }
                } else {
                    // フォールバック
                    Color(uiColor: UIColor(red: 0.1, green: 0.1, blue: 0.18, alpha: 1))
                        .ignoresSafeArea()
                }
            }
        }
        .onAppear {
            guard monetization.canUseLetters else { return }
            if !hasSeenWelcome {
                showWelcome = true
                hasSeenWelcome = true
            }
        }
        .alert("ようこそ！🤫", isPresented: $showWelcome) {
            Button("はじめる") { }
        } message: {
            Text("「未来への手紙」はひみつの機能です。\n\n未来の自分に手紙を書いて、指定した日に届けることができます。タイムカプセルのように、書いたことを忘れた頃に届くサプライズをお楽しみください！")
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope.open")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("まだ手紙がありません")
                .font(.headline)
            Text("上のボタンから未来の自分に手紙を書いてみましょう！")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }
    /// 開封待ちの手紙行
    private func deliverableRow(_ letter: Letter) -> some View {
        HStack {
            Image(systemName: "envelope.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("📬 開封可能")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.orange)
                Text(deliveredDescription(for: letter))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            
            Button("開封") {
                letterToOpen = letter
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .font(.caption)
        }
        .onChange(of: letterToOpen) { _, newLetter in
            if newLetter != nil {
                showLetterOpening = true
            }
        }
    }
    
    /// 届いた日時の表示
    private func deliveredDescription(for letter: Letter) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return String(localized: "\(formatter.string(from: letter.deliveryDate))に届きました")
    }
    
    /// 開封済みの手紙行
    private func openedRow(_ letter: Letter) -> some View {
        NavigationLink {
            LetterContentView(letter: letter)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(letter.content.isEmpty ? "（内容なし）" : letter.content)
                    .lineLimit(2)
                if let openedAt = letter.openedAt {
                    Text("開封日: \(openedAt.jaMonthDayString)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func deleteOpenedLetters(at offsets: IndexSet) {
        for index in offsets {
            let letter = openedLetters[index]
            store.deleteLetter(letter.id)
        }
    }
}

// Date extension for Japanese formatting
extension Date {
    var jaDateTimeString: String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MdHm")
        return formatter.string(from: self)
    }
}
