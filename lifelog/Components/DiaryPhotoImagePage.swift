import SwiftUI

/// Show a persistent preview while loading the independent iCloud copy.
/// Only the selected page requests a high-resolution image (docs/diary-photo-icloud-sync.md).
struct DiaryPhotoImagePage: View {
    let path: String
    let isActive: Bool
    @Binding var chromeVisible: Bool
    @Binding var isZoomed: Bool

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var failed = false
    @State private var retryAttempt = 0

    var body: some View {
        ZStack {
            Color.black
            if let image {
                ZoomableImageScrollView(image: image, isZoomed: $isZoomed) {
                    withAnimation(.easeInOut(duration: 0.2)) { chromeVisible.toggle() }
                }
                .id(path)
            }
        }
        .overlay(alignment: .bottom) {
            if isActive && (isLoading || failed) {
                VStack(spacing: 12) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                        Text("photoStorage.viewer.loading")
                    } else {
                        Text("photoStorage.viewer.unavailable")
                        Button("photoStorage.viewer.retry") { retryAttempt += 1 }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding()
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 24)
                .padding(.bottom, 70)
            }
        }
        .task(id: "\(path):\(isActive):\(retryAttempt)") {
            image = nil
            isZoomed = false
            failed = false
            isLoading = isActive
            let preview = await PhotoStorage.loadThumbnail(at: path)
            guard !_Concurrency.Task.isCancelled else { return }
            image = preview
            guard isActive else { return }
            let fullImage = await PhotoStorage.loadFullImage(at: path)
            guard !_Concurrency.Task.isCancelled else { return }
            if let fullImage { image = fullImage }
            failed = fullImage == nil
            isLoading = false
        }
        .onDisappear {
            image = nil
            isZoomed = false
        }
    }
}
