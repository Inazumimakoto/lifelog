import SwiftUI
import UIKit

struct WallpaperCalendarPhotoBackgroundView: UIViewRepresentable {
    let image: UIImage
    let adjustment: WallpaperCalendarBackgroundAdjustment

    func makeUIView(context: Context) -> PhotoView {
        PhotoView()
    }

    func updateUIView(_ uiView: PhotoView, context: Context) {
        uiView.update(image: image, adjustment: adjustment)
    }

    final class PhotoView: UIView {
        private var sourceImage: UIImage?
        private var background: WallpaperCalendarPhotoBackground?
        private var adjustment = WallpaperCalendarBackgroundAdjustment.defaultValue

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            clipsToBounds = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        nonisolated deinit {}

        func update(image: UIImage, adjustment: WallpaperCalendarBackgroundAdjustment) {
            if sourceImage !== image {
                background?.layer.removeFromSuperlayer()
                sourceImage = image
                let background = WallpaperCalendarPhotoBackground(image: image)
                self.background = background
                layer.addSublayer(background.layer)
            }
            self.adjustment = adjustment
            updateBackground()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            updateBackground()
        }

        private func updateBackground() {
            background?.update(
                size: bounds.size,
                adjustment: adjustment,
                contentsScale: window?.screen.scale ?? traitCollection.displayScale
            )
        }
    }
}
