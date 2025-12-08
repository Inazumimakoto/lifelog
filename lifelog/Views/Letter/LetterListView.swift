//
//  LetterListView.swift
//  lifelog
//
//  Created by AI for Letter to the Future feature
//

import SwiftUI

struct LetterListView: View {
    @EnvironmentObject var store: AppDataStore
    @State private var showEditor = false
    @State private var editingLetter: Letter?
    @State private var letterToOpen: Letter?
    @State private var showLetterOpening = false
    @State private var hasOpenedEnvelope = false
    
    private var draftLetters: [Letter] {
        store.letters.filter { $0.status == .draft }
    }
    
    private var sealedLetters: [Letter] {
        store.letters.filter { $0.status == .sealed }
            .sorted { $0.deliveryDate < $1.deliveryDate }
    }
    
    private var openedLetters: [Letter] {
        store.letters.filter { $0.status == .opened }
            .sorted { ($0.openedAt ?? Date()) > ($1.openedAt ?? Date()) }
    }
    
    var body: some View {
        List {
            if draftLetters.isEmpty && sealedLetters.isEmpty && openedLetters.isEmpty {
                emptyState
            }
            
            if !draftLetters.isEmpty {
                Section("下書き") {
                    ForEach(draftLetters) { letter in
                        letterRow(letter)
                    }
                    .onDelete { offsets in
                        deleteDraftLetters(at: offsets)
                    }
                }
            }
            
            if !sealedLetters.isEmpty {
                Section("送信済み（開封待ち）") {
                    ForEach(sealedLetters) { letter in
                        sealedRow(letter)
                    }
                    .onDelete { offsets in
                        deleteSealedLetters(at: offsets)
                    }
                }
            }
            
            if !openedLetters.isEmpty {
                Section("開封済み") {
                    ForEach(openedLetters) { letter in
                        openedRow(letter)
                    }
                    .onDelete { offsets in
                        deleteOpenedLetters(at: offsets)
                    }
                }
            }
        }
        .navigationTitle("未来への手紙")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingLetter = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
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
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("手紙はまだありません")
                .font(.headline)
            Text("右上の＋ボタンから未来の自分に手紙を書きましょう")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }
    
    private func letterRow(_ letter: Letter) -> some View {
        Button {
            editingLetter = letter
            showEditor = true
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(letter.content.isEmpty ? "（内容なし）" : letter.content)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Text("作成日: \(letter.createdAt.jaMonthDayString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func sealedRow(_ letter: Letter) -> some View {
        HStack {
            Image(systemName: "envelope.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                if letter.isDeliverable {
                    Text("📬 開封可能")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.orange)
                } else {
                    Text("🔒 封印中")
                        .font(.subheadline.weight(.semibold))
                }
                Text(deliveryDescription(for: letter))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            
            if letter.isDeliverable {
                Button("開封") {
                    letterToOpen = letter
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .font(.caption)
            }
        }
        .onChange(of: letterToOpen) { _, newLetter in
            if newLetter != nil {
                showLetterOpening = true
            }
        }
    }
    
    /// 配達情報の表示テキスト（完全ランダムは非表示、それ以外は条件に応じて表示）
    private func deliveryDescription(for letter: Letter) -> String {
        if letter.deliveryType == .fixed {
            // 固定: 日時を表示
            return "開封予定: \(letter.deliveryDate.jaDateTimeString)"
        }
        
        // ランダムの場合
        guard let settings = letter.randomSettings else {
            // 設定がない場合（完全ランダム）
            return "いつか届きます ✨"
        }
        
        var parts: [String] = []
        
        // 期間指定がある場合
        if settings.useDateRange, let start = settings.startDate, let end = settings.endDate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = "M/d"
            parts.append("\(formatter.string(from: start))〜\(formatter.string(from: end))")
        }
        
        // 時間帯指定がある場合
        if settings.useTimeRange {
            parts.append("\(settings.startHour):\(String(format: "%02d", settings.startMinute))〜\(settings.endHour):\(String(format: "%02d", settings.endMinute))")
        }
        
        if parts.isEmpty {
            // 何も指定していない（完全ランダム）
            return "いつか届きます ✨"
        }
        
        return "開封予定: \(parts.joined(separator: " "))のどこか"
    }
    
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
    
    private func deleteDraftLetters(at offsets: IndexSet) {
        for index in offsets {
            let letter = draftLetters[index]
            store.deleteLetter(letter.id)
        }
    }
    
    private func deleteOpenedLetters(at offsets: IndexSet) {
        for index in offsets {
            let letter = openedLetters[index]
            store.deleteLetter(letter.id)
        }
    }
    
    private func deleteSealedLetters(at offsets: IndexSet) {
        for index in offsets {
            let letter = sealedLetters[index]
            store.deleteLetter(letter.id)
        }
    }
}

// Date extension for Japanese formatting
extension Date {
    var jaDateTimeString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日 H:mm"
        return formatter.string(from: self)
    }
}
