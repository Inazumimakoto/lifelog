//
//  LetterOpeningView.swift
//  lifelog
//
//  Created by AI for Letter to the Future feature
//

import SwiftUI
import UIKit

// MARK: - メインビュー

struct LetterOpeningView: View {
    let letter: Letter
    var onOpen: () -> Void

    // 写真カルーセル用
    @State private var selectedPhotoIndex: Int = 0
    @State private var showFullscreenPhoto = false

    /// 手紙を書いてから経過した期間を文字列で返す
    private var timeSinceCreation: String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: letter.createdAt, to: Date())

        if let years = components.year, years > 0 {
            if let months = components.month, months > 0 {
                return "\(years)年\(months)ヶ月前のあなたから"
            }
            return "\(years)年前のあなたから"
        } else if let months = components.month, months > 0 {
            return "\(months)ヶ月前のあなたから"
        } else if let days = components.day, days > 0 {
            return "\(days)日前のあなたから"
        } else {
            return "今日のあなたから"
        }
    }

    var body: some View {
        EnvelopeOpeningView(
            accentColor: .orange,
            headerTitle: "📨 過去のあなたから手紙が届きました",
            headerSubtitle: letter.createdAt.jaFullDateString,
            recipientLabel: "To: 未来の自分へ",
            senderValue: letter.createdAt.jaShortDateString,
            arrivalValue: letter.deliveryDate.jaShortDateString,
            previewContent: { previewContent },
            expandedContent: { expandedContent },
            onOpenStart: {
                // 開封処理を実行
                onOpen()
            },
            onExpand: {}
        )
        .fullScreenCover(isPresented: $showFullscreenPhoto) {
            fullscreenPhotoViewer
        }
    }

    // MARK: - プレビュー（折りたたみ時の手紙カード）

    @ViewBuilder
    private var previewContent: some View {
        // 日付のみ
        Text(letter.createdAt.jaFullDateString)
            .font(.caption)
            .foregroundColor(.gray)

        // 本文
        Text(letter.content)
            .font(.subheadline)
            .foregroundColor(.black)
            .lineSpacing(4)
            .lineLimit(6)
            .multilineTextAlignment(.leading)
    }

    // MARK: - 拡張時の手紙カード本文

    @ViewBuilder
    private var expandedContent: some View {
        // ヘッダー: 経過時間を表示
        VStack(spacing: 4) {
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)

            Text(timeSinceCreation)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)

        // 見出し
        Text("Dear 未来の自分へ")
            .font(.system(size: 18, weight: .semibold, design: .serif))
            .foregroundColor(.brown)

        Rectangle()
            .fill(Color.brown.opacity(0.2))
            .frame(height: 1)

        // 本文
        Text(letter.content)
            .font(.body)
            .foregroundColor(.black)
            .lineSpacing(6)
            .multilineTextAlignment(.leading)

        // 写真カルーセル（写真がある場合のみ）
        if !letter.photoPaths.isEmpty {
            VStack(spacing: 12) {
                // セクションヘッダー
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                        .foregroundColor(.brown.opacity(0.6))
                    Text("添付写真")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.brown.opacity(0.8))
                    Spacer()
                    Text("\(letter.photoPaths.count)枚")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                // カルーセル
                TabView(selection: $selectedPhotoIndex) {
                    ForEach(Array(letter.photoPaths.enumerated()), id: \.offset) { index, path in
                        photoView(for: path)
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
                Text("\(letter.createdAt.jaFullDateString)のあなたより")
                    .font(.system(size: 12, design: .serif))
                    .foregroundColor(.gray)
            }
        }

        Spacer().frame(height: 60)
    }

    // MARK: - 写真ビュー

    @ViewBuilder
    private func photoView(for path: String) -> some View {
        // 相対パスをフルパスに変換
        let fullPath = resolvePhotoPath(path)

        if let uiImage = UIImage(contentsOfFile: fullPath) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipped()
        } else {
            // プレースホルダー
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 200)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(.gray.opacity(0.5))
                        Text("写真を読み込めません")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                )
        }
    }

    /// 相対パスまたは絶対パスをフルパスに解決する
    private func resolvePhotoPath(_ path: String) -> String {
        // 既に絶対パスの場合はそのまま返す（後方互換性）
        if path.hasPrefix("/") {
            return path
        }
        // 相対パスの場合はDocumentsディレクトリに結合
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return path
        }
        return documentsDir.appendingPathComponent(path).path
    }

    // MARK: - フルスクリーン写真ビューア

    private var fullscreenPhotoViewer: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedPhotoIndex) {
                ForEach(Array(letter.photoPaths.enumerated()), id: \.offset) { index, path in
                    fullscreenPhotoView(for: path)
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
                Text("\(selectedPhotoIndex + 1) / \(letter.photoPaths.count)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.bottom, 40)
            }
        }
    }

    @ViewBuilder
    private func fullscreenPhotoView(for path: String) -> some View {
        // 相対パスをフルパスに変換
        let fullPath = resolvePhotoPath(path)

        if let uiImage = UIImage(contentsOfFile: fullPath) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "photo")
                    .font(.system(size: 60))
                    .foregroundColor(.white.opacity(0.3))
                Text("写真を読み込めません")
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}

// MARK: - Letter Opening Wrapper（ストアの更新から独立）
struct LetterOpeningWrapper: View {
    let letter: Letter
    let onOpen: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LetterOpeningView(letter: letter, onOpen: onOpen)
    }
}
