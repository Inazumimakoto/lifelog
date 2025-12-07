//
//  DiaryPhotoViewerView.swift
//  lifelog
//
//  Created by Codex on 2025/11/16.
//

import SwiftUI

struct DiaryPhotoViewerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: DiaryViewModel
    @State private var currentIndex: Int
    @State private var showDeleteAlert = false
    @State private var chromeVisible = true

    init(viewModel: DiaryViewModel, initialIndex: Int) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        let clampedIndex = max(0, min(initialIndex, max(0, viewModel.entry.photoPaths.count - 1)))
        _currentIndex = State(initialValue: clampedIndex)
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if viewModel.entry.photoPaths.isEmpty == false {
                TabView(selection: $currentIndex) {
                    ForEach(Array(viewModel.entry.photoPaths.enumerated()), id: \.offset) { index, path in
                        if let image = PhotoStorage.loadImage(at: path) {
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black)
                                .tag(index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        chromeVisible.toggle()
                                    }
                                }
                        } else {
                            Color.black.tag(index)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                    Spacer()
                    favoriteButton
                    Button {
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                }
                .padding([.top, .horizontal], 16)
                .opacity(chromeVisible ? 1 : 0)
                .allowsHitTesting(chromeVisible)
                Spacer()
            }
        }
        .onChange(of: viewModel.entry.photoPaths) { paths in
            guard let lastIndex = paths.indices.last else {
                dismiss()
                return
            }
            if currentIndex > lastIndex {
                currentIndex = lastIndex
            }
        }
        .alert("この写真を削除しますか？", isPresented: $showDeleteAlert) {
            Button("削除", role: .destructive) {
                deleteCurrentPhoto()
            }
            Button("キャンセル", role: .cancel) { }
        }
    }

    private var favoriteButton: some View {
        let currentPath = viewModel.entry.photoPaths.indices.contains(currentIndex) ? viewModel.entry.photoPaths[currentIndex] : nil
        let isFavorite = currentPath != nil && viewModel.entry.favoritePhotoPath == currentPath

        return Button {
            guard viewModel.entry.photoPaths.indices.contains(currentIndex) else { return }
            viewModel.setFavoritePhoto(at: currentIndex)
            HapticManager.light()
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.title2)
                .foregroundStyle(isFavorite ? Color.yellow : Color.white)
                .padding(12)
                .background(.black.opacity(0.5), in: Circle())
                .symbolEffect(.bounce, value: isFavorite)
        }
        .buttonStyle(.plain)
        .disabled(currentPath == nil)
    }

    private func deleteCurrentPhoto() {
        guard viewModel.entry.photoPaths.indices.contains(currentIndex) else {
            dismiss()
            return
        }
        viewModel.deletePhoto(at: IndexSet(integer: currentIndex))
        let remaining = viewModel.entry.photoPaths.count
        if remaining == 0 {
            dismiss()
        } else {
            currentIndex = min(currentIndex, remaining - 1)
        }
    }
}
