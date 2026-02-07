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
    @State private var verticalDragOffset: CGFloat = 0
    private let dismissDragThreshold: CGFloat = 140

    init(viewModel: DiaryViewModel, initialIndex: Int) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        let clampedIndex = max(0, min(initialIndex, max(0, viewModel.entry.photoPaths.count - 1)))
        _currentIndex = State(initialValue: clampedIndex)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            ZStack {
                if viewModel.entry.photoPaths.isEmpty == false {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(viewModel.entry.photoPaths.enumerated()), id: \.offset) { index, path in
                            FullImagePage(path: path, chromeVisible: $chromeVisible)
                                .tag(index)
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
            .offset(y: verticalDragOffset)
        }
        .simultaneousGesture(verticalDismissGesture)
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

    private var backgroundOpacity: Double {
        let progress = min(max(verticalDragOffset / dismissDragThreshold, 0), 1)
        return 1 - (progress * 0.45)
    }

    private var verticalDismissGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                let vertical = value.translation.height
                let horizontal = value.translation.width
                guard vertical > 0, abs(vertical) > abs(horizontal) else { return }
                verticalDragOffset = min(vertical, 360)
            }
            .onEnded { value in
                let vertical = value.translation.height
                let horizontal = value.translation.width

                guard vertical > 0, abs(vertical) > abs(horizontal) else {
                    resetVerticalDragOffset()
                    return
                }

                if vertical >= dismissDragThreshold {
                    dismiss()
                } else {
                    resetVerticalDragOffset()
                }
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

    private func resetVerticalDragOffset() {
        guard verticalDragOffset != 0 else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            verticalDragOffset = 0
        }
    }
}

// 非同期でフルサイズ画像を読み込むページ
private struct FullImagePage: View {
    let path: String
    @Binding var chromeVisible: Bool
    
    @State private var image: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else {
                Color.black
            }
        }
        .background(Color.black)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                chromeVisible.toggle()
            }
        }
        .task {
            image = await PhotoStorage.loadFullImage(at: path)
            isLoading = false
        }
    }
}
