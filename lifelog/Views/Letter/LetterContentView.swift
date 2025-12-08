//
//  LetterContentView.swift
//  lifelog
//
//  Created by AI for Letter to the Future feature
//

import SwiftUI

struct LetterContentView: View {
    let letter: Letter
    @State private var loadedImages: [UIImage] = []
    @State private var selectedPhotoIndex: Int = 0
    @State private var showFullscreenPhoto = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // ヘッダー
                VStack(spacing: 8) {
                    Image(systemName: "envelope.open.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    
                    Text("過去のあなたからの手紙")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Text(letter.createdAt.jaFullDateString)
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
                                .foregroundColor(.orange)
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
        .task {
            loadPhotos()
        }
        .fullScreenCover(isPresented: $showFullscreenPhoto) {
            fullscreenPhotoViewer
        }
    }
    
    private func loadPhotos() {
        for path in letter.photoPaths {
            if let data = FileManager.default.contents(atPath: path),
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
                Text("\(selectedPhotoIndex + 1) / \(loadedImages.count)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.bottom, 40)
            }
        }
    }
}

extension Date {
    var jaFullDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: self)
    }
    
    var jaShortDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/M/d"
        return formatter.string(from: self)
    }
}
