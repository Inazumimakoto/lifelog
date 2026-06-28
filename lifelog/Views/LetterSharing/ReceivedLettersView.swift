//
//  ReceivedLettersView.swift
//  lifelog
//
//  大切な人への手紙 - 受信した手紙一覧
//

import SwiftUI
import UIKit
import os

/// 受信した手紙一覧画面
struct ReceivedLettersView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var letters: [LetterReceivingService.ReceivedLetter] = []  // Firestoreからの未開封のみ
    @State private var isLoading = true
    @State private var selectedLetter: LetterReceivingService.ReceivedLetter?  // 未開封用
    @State private var showingLetterDetail = false  // 開封アニメーション用
    @State private var selectedOpenedLetter: SharedLetter?  // 開封済み用（ローカルデータ）
    @State private var showingOpenedLetterDetail = false  // 開封済み詳細用
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("読み込み中...")
            } else if letters.isEmpty && store.sharedLetters.isEmpty {
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
        // 未開封の手紙 → 開封アニメーション
        .fullScreenCover(isPresented: $showingLetterDetail, onDismiss: {
            selectedLetter = nil
            // 開封後にリストを更新
            _Concurrency.Task {
                await loadLetters()
            }
        }) {
            Group {
                if let letter = selectedLetter {
                    SharedLetterOpeningView(letter: letter)
                } else {
                    // フォールバック（通常は表示されない）
                    Color(uiColor: UIColor(red: 0.1, green: 0.1, blue: 0.18, alpha: 1))
                        .ignoresSafeArea()
                }
            }
        }
        // 開封済みの手紙 → 通常表示
        .sheet(isPresented: $showingOpenedLetterDetail, onDismiss: {
            selectedOpenedLetter = nil
        }) {
            if let letter = selectedOpenedLetter {
                NavigationStack {
                    SharedLetterContentView(letter: letter)
                }
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
    
    @ViewBuilder
    private var letterListView: some View {
        let unreadLetters = letters.filter { $0.status == "delivered" }
        
        List {
            // 開封待ちセクション
            Section {
                if unreadLetters.isEmpty {
                    HStack {
                        Spacer()
                        Text("開封待ちの手紙はありません")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(unreadLetters) { letter in
                        Button(action: {
                            selectedLetter = letter
                        }) {
                            unreadLetterRow(letter)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Label("開封待ち", systemImage: "envelope.badge")
                    .font(.headline)
            }
            
            // 開封済みセクション
            Section {
                if store.sharedLetters.isEmpty {
                    HStack {
                        Spacer()
                        Text("開封済みの手紙はありません")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(store.sharedLetters) { letter in
                        Button(action: {
                            selectedOpenedLetter = letter  // 開封済み用（ローカル）
                        }) {
                            localLetterRow(letter)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())  // タップ領域を広げる
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteOpenedLetter(letter)
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Label("開封済み", systemImage: "envelope.open")
                    .font(.headline)
            }
        }
        .listStyle(.insetGrouped)
        .onChange(of: selectedLetter) { _, newLetter in
            if newLetter != nil {
                showingLetterDetail = true
            }
        }
        .onChange(of: selectedOpenedLetter) { _, newLetter in
            if newLetter != nil {
                showingOpenedLetterDetail = true
            }
        }
    }
    
    private func unreadLetterRow(_ letter: LetterReceivingService.ReceivedLetter) -> some View {
        HStack(spacing: 12) {
            // オレンジ封筒アイコン
            Image(systemName: "envelope.fill")
                .font(.title)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(letter.senderEmoji) \(letter.senderName)さんから")
                    .font(.headline)
                    .foregroundColor(.orange)
                
                Text("\(formatDate(letter.deliveredAt))に届きました")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("開封")
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(8)
        }
        .padding(.vertical, 8)
    }
    
    private func localLetterRow(_ letter: SharedLetter) -> some View {
        HStack(spacing: 12) {
            Text(letter.senderEmoji)
                .font(.title)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(letter.senderName)
                    .font(.headline)
                
                Text("開封日: \(formatDate(letter.openedAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
    
    private func loadLetters() async {
        isLoading = true
        do {
            letters = try await LetterReceivingService.shared.getReceivedLetters()
            
            // バッジを未開封数に更新
            let unreadCount = letters.filter { $0.status == "delivered" }.count
            try? await UNUserNotificationCenter.current().setBadgeCount(unreadCount)
        } catch {
            AppLogger.letters.error("手紙取得エラー: \(error.localizedDescription)")
        }
        isLoading = false
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MdHm")
        return formatter.string(from: date)
    }
    
    private func deleteOpenedLetter(_ letter: SharedLetter) {
        withAnimation {
            store.deleteSharedLetter(letter.id)
        }
    }
}

// MARK: - 共有手紙開封画面（共通の EnvelopeOpeningView を使用）

struct SharedLetterOpeningView: View {
    let letter: LetterReceivingService.ReceivedLetter
    @EnvironmentObject private var store: AppDataStore

    // 復号用
    @State private var isDecrypting = false
    @State private var decryptedLetter: LetterReceivingService.DecryptedLetter?
    @State private var errorMessage: String?

    // 写真用
    @State private var selectedPhotoIndex: Int = 0
    @State private var showFullscreenPhoto = false

    var body: some View {
        EnvelopeOpeningView(
            accentColor: .blue,
            headerTitle: "\(letter.senderEmoji) \(letter.senderName)さんから手紙が届きました",
            headerSubtitle: letter.deliveredAt.jaFullDateString,
            recipientLabel: "To: あなたへ",
            senderValue: letter.senderName,
            arrivalValue: letter.deliveredAt.jaShortDateString,
            previewContent: { previewContent },
            expandedContent: { expandedContent },
            onOpenStart: {},
            onExpand: {
                // カード拡大タイミングで復号を開始
                decryptLetter()
            }
        )
        .fullScreenCover(isPresented: $showFullscreenPhoto) {
            fullscreenPhotoViewer
        }
    }

    // MARK: - プレビュー（折りたたみ時の手紙カード）

    @ViewBuilder
    private var previewContent: some View {
        Text(letter.deliveredAt.jaFullDateString)
            .font(.caption)
            .foregroundColor(.gray)

        Text("\(letter.senderEmoji) \(letter.senderName)さんからの手紙")
            .font(.subheadline)
            .foregroundColor(.black)
            .lineLimit(6)
    }

    // MARK: - 拡張時の手紙カード本文（復号状態に応じて切り替え）

    @ViewBuilder
    private var expandedContent: some View {
        if isDecrypting {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("復号中...")
                    .font(.headline)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else if let decrypted = decryptedLetter {
            // ヘッダー
            VStack(spacing: 4) {
                Text(decrypted.senderEmoji)
                    .font(.system(size: 40))

                Text("\(decrypted.senderName)さんより")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            Text("Dear あなたへ")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundColor(.brown)

            Rectangle()
                .fill(Color.brown.opacity(0.2))
                .frame(height: 1)

            // 本文
            Text(decrypted.content)
                .font(.body)
                .foregroundColor(.black)
                .lineSpacing(6)

            // 写真
            if !decrypted.photos.isEmpty {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                            .foregroundColor(.brown.opacity(0.6))
                        Text("添付写真")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.brown.opacity(0.8))
                        Spacer()
                        Text("\(decrypted.photos.count)枚")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    TabView(selection: $selectedPhotoIndex) {
                        ForEach(Array(decrypted.photos.enumerated()), id: \.offset) { index, photo in
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 200)
                                .clipped()
                                .tag(index)
                                .onTapGesture {
                                    showFullscreenPhoto = true
                                }
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 8)
            }

            Spacer().frame(height: 16)

            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Rectangle()
                        .fill(Color.brown.opacity(0.2))
                        .frame(width: 100, height: 1)
                    Text("\(decrypted.deliveredAt.jaFullDateString)に届いた手紙")
                        .font(.system(size: 12, design: .serif))
                        .foregroundColor(.gray)
                }
            }

            Spacer().frame(height: 60)
        } else if let error = errorMessage {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundColor(.red)
                Text(error)
                    .font(.headline)
                    .foregroundColor(.red)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        }
    }

    // MARK: - フルスクリーン写真ビューア

    private var fullscreenPhotoViewer: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let decrypted = decryptedLetter {
                TabView(selection: $selectedPhotoIndex) {
                    ForEach(Array(decrypted.photos.enumerated()), id: \.offset) { index, photo in
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        showFullscreenPhoto = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding()
                    }
                }
                Spacer()

                if let decrypted = decryptedLetter {
                    Text("\(selectedPhotoIndex + 1) / \(decrypted.photos.count)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.bottom, 40)
                }
            }
        }
    }

    private func decryptLetter() {
        isDecrypting = true
        
        _Concurrency.Task {
            do {
                let decrypted = try await LetterReceivingService.shared.openLetter(letterId: letter.id)
                
                // ローカルに保存
                let photoPaths = await savePhotosLocally(decrypted.photos, letterId: letter.id)
                let sharedLetter = SharedLetter(
                    id: letter.id,
                    senderId: decrypted.senderId,
                    senderEmoji: decrypted.senderEmoji,
                    senderName: decrypted.senderName,
                    content: decrypted.content,
                    photoPaths: photoPaths,
                    deliveredAt: decrypted.deliveredAt,
                    openedAt: decrypted.openedAt ?? Date()
                )
                
                await MainActor.run {
                    store.addSharedLetter(sharedLetter)
                    decryptedLetter = decrypted
                    isDecrypting = false
                    HapticManager.success()
                }
                
                // Firestoreから削除
                try await LetterReceivingService.shared.deleteLetter(letterId: letter.id)
                AppLogger.letters.info("Firestoreから手紙を削除: \(letter.id)")
                
            } catch {
                await MainActor.run {
                    isDecrypting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func savePhotosLocally(_ photos: [UIImage], letterId: String) async -> [String] {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }
        
        let letterDir = documentsDir.appendingPathComponent("SharedLetterPhotos/\(letterId)")
        try? FileManager.default.createDirectory(at: letterDir, withIntermediateDirectories: true)
        
        var paths: [String] = []
        for (index, photo) in photos.enumerated() {
            let filename = "photo_\(index).jpg"
            let fileURL = letterDir.appendingPathComponent(filename)
            if let data = photo.jpegData(compressionQuality: 0.8) {
                try? data.write(to: fileURL)
                // 相対パスを保存
                paths.append("SharedLetterPhotos/\(letterId)/\(filename)")
            }
        }
        
        return paths
    }
}

// MARK: - 開封済み手紙の表示画面（ローカルデータ）

struct SharedLetterContentView: View {
    let letter: SharedLetter  // ローカル保存された手紙
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore
    
    @State private var loadedImages: [UIImage] = []
    @State private var selectedPhotoIndex: Int = 0
    @State private var showFullscreenPhoto = false
    
    // 通報・ブロック用
    @State private var showReportSheet = false
    @State private var showBlockConfirmation = false
    @State private var showBlockSuccessAfterReport = false
    @State private var isBlocking = false
    
    // 削除用
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // ヘッダー
                VStack(spacing: 8) {
                    Text(letter.senderEmoji)
                        .font(.system(size: 50))
                    
                    Text("\(letter.senderName)さんからの手紙")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Text(letter.openedAt.jaFullDateString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                
                Divider()
                
                // 本文
                Text(letter.content)
                    .font(.body)
                    .lineSpacing(6)
                
                // 写真カルーセル（写真がある場合のみ）
                if !loadedImages.isEmpty {
                    Divider()
                    
                    VStack(spacing: 12) {
                        // セクションヘッダー
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                                .foregroundColor(.blue)
                            Text("添付写真")
                                .font(.headline)
                            Spacer()
                            Text("\(loadedImages.count)枚")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        // カルーセル
                        TabView(selection: $selectedPhotoIndex) {
                            ForEach(loadedImages.indices, id: \.self) { index in
                                Image(uiImage: loadedImages[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 200)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .tag(index)
                                    .onTapGesture {
                                        showFullscreenPhoto = true
                                    }
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .automatic))
                        .frame(height: 220)
                    }
                }
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        .navigationTitle("手紙を読む")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        showReportSheet = true
                    } label: {
                        Label("通報", systemImage: "exclamationmark.triangle")
                    }
                    
                    Button(role: .destructive) {
                        showBlockConfirmation = true
                    } label: {
                        Label("ブロック", systemImage: "hand.raised.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            loadPhotos()
        }
        .fullScreenCover(isPresented: $showFullscreenPhoto) {
            fullscreenPhotoViewer
        }
        .sheet(isPresented: $showReportSheet) {
            ReportSheetView(
                userName: letter.senderName,
                userId: letter.senderId,
                letterId: letter.id,
                onReportComplete: {
                    showBlockSuccessAfterReport = true
                }
            )
        }
        .alert("ブロックしますか？", isPresented: $showBlockConfirmation) {
            Button("キャンセル", role: .cancel) { }
            Button("ブロック", role: .destructive) {
                blockUser()
            }
        } message: {
            Text("\(letter.senderName)さんからの手紙は今後届かなくなります。")
        }
        .alert("ブロックしますか？", isPresented: $showBlockSuccessAfterReport) {
            Button("いいえ", role: .cancel) { }
            Button("ブロックする", role: .destructive) {
                blockUser()
            }
        } message: {
            Text("通報を送信しました。このユーザーをブロックしますか？")
        }
        .alert("この手紙を削除しますか？", isPresented: $showDeleteConfirmation) {
            Button("キャンセル", role: .cancel) { }
            Button("削除", role: .destructive) {
                store.deleteSharedLetter(letter.id)
                dismiss()
            }
        } message: {
            Text("削除した手紙は復元できません。")
        }
    }
    
    private func blockUser() {
        isBlocking = true
        _Concurrency.Task {
            do {
                try await AuthService.shared.blockUser(letter.senderId)
                await MainActor.run {
                    isBlocking = false
                    HapticManager.success()
                }
            } catch {
                await MainActor.run {
                    isBlocking = false
                }
            }
        }
    }
    
    private func loadPhotos() {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        for path in letter.photoPaths {
            let fullPath = documentsDir.appendingPathComponent(path)
            if let data = FileManager.default.contents(atPath: fullPath.path),
               let image = UIImage(data: data) {
                loadedImages.append(image)
            }
        }
    }
    
    // MARK: - フルスクリーン写真ビューア
    
    private var fullscreenPhotoViewer: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            TabView(selection: $selectedPhotoIndex) {
                ForEach(loadedImages.indices, id: \.self) { index in
                    Image(uiImage: loadedImages[index])
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            
            // 閉じるボタン
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showFullscreenPhoto = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding()
                    }
                }
                Spacer()
                
                // ページ表示
                if !loadedImages.isEmpty {
                    Text("\(selectedPhotoIndex + 1) / \(loadedImages.count)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.bottom, 40)
                }
            }
        }
    }
}

// MARK: - 通報シート

struct ReportSheetView: View {
    let userName: String
    let userId: String
    let letterId: String?
    let onReportComplete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: ReportService.ReportReason?
    @StateObject private var detailsDraft = LongFormTextDraft(text: "")
    @State private var isSubmitting = false
    @State private var showSuccess = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(userName)さんを通報")
                        .font(.headline)
                } header: {
                    Text("通報対象")
                }
                
                Section {
                    ForEach(ReportService.ReportReason.allCases, id: \.self) { reason in
                        Button {
                            selectedReason = reason
                        } label: {
                            HStack {
                                Text(reason.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedReason == reason {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Text("通報理由")
                }
                
                Section {
                    ZStack(alignment: .topLeading) {
                        Text("詳細（任意）")
                            .foregroundStyle(.tertiary)
                            .opacity(detailsDraft.isEmpty ? 1 : 0)
                            .allowsHitTesting(false)
                        LongFormTextView(text: detailsDraft.text,
                                         textVersion: detailsDraft.version,
                                         onTextChange: { newValue in
                                             detailsDraft.updateFromEditor(newValue)
                                         })
                            .frame(minHeight: 72, alignment: .topLeading)
                    }
                } header: {
                    Text("詳細")
                }
            }
            .navigationTitle("通報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("送信") {
                        submitReport()
                    }
                    .disabled(selectedReason == nil || isSubmitting)
                }
            }
            .alert("通報を送信しました", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                    onReportComplete()
                }
            }
        }
    }
    
    private func submitReport() {
        guard let reason = selectedReason else { return }
        
        isSubmitting = true
        _Concurrency.Task {
            do {
                try await ReportService.shared.reportUser(
                    userId: userId,
                    reason: reason,
                    letterId: letterId,
                    details: detailsDraft.isEmpty ? nil : detailsDraft.text
                )
                await MainActor.run {
                    isSubmitting = false
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ReceivedLettersView()
    }
}
