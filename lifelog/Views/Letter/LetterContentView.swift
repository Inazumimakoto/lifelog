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
                    
                    LetterPhotoCarousel(images: loadedImages,
                                        selectedIndex: $selectedPhotoIndex,
                                        accentColor: .orange) {
                        showFullscreenPhoto = true
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
            let fullPath = LetterPhotoFiles.resolvePath(path)
            if let data = FileManager.default.contents(atPath: fullPath),
               let image = UIImage(data: data) {
                loadedImages.append(image)
            }
        }
    }
    
    // MARK: - フルスクリーン写真ビューア
    
    private var fullscreenPhotoViewer: some View {
        FullscreenPhotoGallery(photoCount: loadedImages.count,
                               selectedIndex: $selectedPhotoIndex,
                               onClose: { showFullscreenPhoto = false }) { index in
            Image(uiImage: loadedImages[index])
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension Date {
    var jaFullDateString: String {
        jaYearMonthDayString
    }
    
    var jaShortDateString: String {
        jaYearMonthDayString
    }
}
