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
                
                // 写真があれば表示
                if !loadedImages.isEmpty {
                    Divider()
                    
                    Text("添付写真")
                        .font(.headline)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(loadedImages.indices, id: \.self) { index in
                            Image(uiImage: loadedImages[index])
                                .resizable()
                                .scaledToFill()
                                .frame(height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
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
    }
    
    private func loadPhotos() {
        for path in letter.photoPaths {
            if let data = FileManager.default.contents(atPath: path),
               let image = UIImage(data: data) {
                loadedImages.append(image)
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
