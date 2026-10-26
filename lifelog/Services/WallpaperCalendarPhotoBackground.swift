import CoreImage
import UIKit

/// Shared photo composition for the editor and the exported wallpaper.
/// See docs/requirements.md §4.11: extend edge colors instead of repeating the subject.
@MainActor
final class WallpaperCalendarPhotoBackground {
    let layer = CALayer()

    private let photo: PreparedPhoto
    private let backgroundLayers: [CALayer]
    private let foregroundLayer = CALayer()
    private let horizontalMask = CAGradientLayer()
    private let verticalMask = CAGradientLayer()

    private static let imageContext = CIContext(options: [.cacheIntermediates: false])
    private static let preparedPhotos: NSCache<UIImage, PreparedPhoto> = {
        let cache = NSCache<UIImage, PreparedPhoto>()
        cache.countLimit = 2
        cache.totalCostLimit = 32 * 1_024 * 1_024
        return cache
    }()

    init(image: UIImage) {
        if let cached = Self.preparedPhotos.object(forKey: image) {
            photo = cached
        } else {
            photo = Self.prepare(image)
            let cost = photo.original.map { $0.bytesPerRow * $0.height } ?? 0
            Self.preparedPhotos.setObject(photo, forKey: image, cost: cost)
        }

        layer.masksToBounds = true
        layer.backgroundColor = UIColor.black.cgColor
        backgroundLayers = photo.tiles.map { tile in
            let tileLayer = CALayer()
            tileLayer.contents = tile
            tileLayer.contentsGravity = .resize
            tileLayer.magnificationFilter = .linear
            tileLayer.allowsEdgeAntialiasing = false
            return tileLayer
        }
        backgroundLayers.forEach { layer.addSublayer($0) }

        foregroundLayer.contents = photo.original
        foregroundLayer.contentsGravity = .resize
        foregroundLayer.minificationFilter = .trilinear
        layer.addSublayer(foregroundLayer)

        horizontalMask.startPoint = CGPoint(x: 0, y: 0.5)
        horizontalMask.endPoint = CGPoint(x: 1, y: 0.5)
        verticalMask.startPoint = CGPoint(x: 0.5, y: 0)
        verticalMask.endPoint = CGPoint(x: 0.5, y: 1)
        horizontalMask.mask = verticalMask
    }

    // ARC only releases image/layer references here; no main-actor UI work is needed.
    // Avoid the back-deployed isolated-deinit executor hop in synchronous callers.
    nonisolated deinit {}

    /// Pinching changes only layer frames and masks. The blurred pixels are prepared once.
    func update(size: CGSize,
                adjustment: WallpaperCalendarBackgroundAdjustment,
                contentsScale: CGFloat) {
        guard size.width > 0, size.height > 0 else { return }
        let canvas = CGRect(origin: .zero, size: size)
        let imageRect = adjustment.imageRect(for: photo.size, in: canvas)
        let outerRect = canvas.union(imageRect)
        let xs = [outerRect.minX, imageRect.minX, imageRect.maxX, outerRect.maxX]
        let ys = [outerRect.minY, imageRect.minY, imageRect.maxY, outerRect.maxY]
        let pixelScale = contentsScale.isFinite && contentsScale > 0 ? contentsScale : 1

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = canvas
        layer.contentsScale = pixelScale
        for row in 0..<3 {
            for column in 0..<3 {
                let tileLayer = backgroundLayers[row * 3 + column]
                let tileRect = CGRect(
                    x: xs[column], y: ys[row],
                    width: xs[column + 1] - xs[column],
                    height: ys[row + 1] - ys[row]
                )
                tileLayer.isHidden = tileRect.isEmpty
                // Neighboring tiles must overlap at pixel boundaries. Otherwise
                // offline layer rendering can expose the black backing at their joins.
                tileLayer.frame = coveredPixelRect(tileRect, scale: pixelScale)
                tileLayer.contentsScale = pixelScale
            }
        }

        foregroundLayer.frame = imageRect
        foregroundLayer.contentsScale = pixelScale
        updateFeatherMask(imageRect: imageRect, canvas: canvas)
        CATransaction.commit()
    }

    private func coveredPixelRect(_ rect: CGRect, scale: CGFloat) -> CGRect {
        guard !rect.isEmpty else { return rect }
        let minX = floor(rect.minX * scale) - 1
        let minY = floor(rect.minY * scale) - 1
        let maxX = ceil(rect.maxX * scale) + 1
        let maxY = ceil(rect.maxY * scale) + 1
        return CGRect(x: minX / scale, y: minY / scale,
                      width: (maxX - minX) / scale, height: (maxY - minY) / scale)
    }

    private func updateFeatherMask(imageRect: CGRect, canvas: CGRect) {
        let exposedLeft = imageRect.minX > canvas.minX
        let exposedRight = imageRect.maxX < canvas.maxX
        let exposedTop = imageRect.minY > canvas.minY
        let exposedBottom = imageRect.maxY < canvas.maxY
        guard exposedLeft || exposedRight || exposedTop || exposedBottom else {
            foregroundLayer.mask = nil
            return
        }

        // Give exposed edges a broad, eased transition while keeping the center sharp.
        let feather = min(canvas.width * 0.16, min(imageRect.width, imageRect.height) * 0.30)
        // Grow each fade with its visible margin so zooming through full coverage
        // does not suddenly switch a wide blur band on or off.
        let leftFraction = min(feather, max(0, imageRect.minX - canvas.minX) * 2) / imageRect.width
        let rightFraction = min(feather, max(0, canvas.maxX - imageRect.maxX) * 2) / imageRect.width
        let topFraction = min(feather, max(0, imageRect.minY - canvas.minY) * 2) / imageRect.height
        let bottomFraction = min(feather, max(0, canvas.maxY - imageRect.maxY) * 2) / imageRect.height
        let maskBounds = CGRect(origin: .zero, size: imageRect.size)
        horizontalMask.frame = maskBounds
        verticalMask.frame = maskBounds
        configureMask(horizontalMask, startFraction: leftFraction, endFraction: rightFraction)
        configureMask(verticalMask, startFraction: topFraction, endFraction: bottomFraction)
        foregroundLayer.mask = horizontalMask
    }

    private func configureMask(_ mask: CAGradientLayer,
                               startFraction: CGFloat,
                               endFraction: CGFloat) {
        let stops: [CGFloat] = [0, 0.2, 0.4, 0.6, 0.8, 1]
        let opacity = stops.map { $0 * $0 * (3 - 2 * $0) }
        let startColors = opacity.map { UIColor.black.withAlphaComponent(startFraction > 0 ? $0 : 1).cgColor }
        let endColors = opacity.reversed().map { UIColor.black.withAlphaComponent(endFraction > 0 ? $0 : 1).cgColor }
        mask.colors = startColors + endColors
        mask.locations = stops.map { NSNumber(value: Double($0 * startFraction)) }
            + stops.reversed().map { NSNumber(value: Double(1 - $0 * endFraction)) }
    }

    private static func prepare(_ image: UIImage) -> PreparedPhoto {
        let original = uprightImage(image)
        guard let originalPixels = original.cgImage else {
            return PreparedPhoto(size: original.size, original: nil, tiles: Array(repeating: nil, count: 9))
        }

        // A small texture is sufficient for a strongly blurred background. Edge rows,
        // columns and corners stretch independently, so no second subject is introduced.
        let input = CIImage(cgImage: originalPixels)
        let ratio = min(1, 512 / max(input.extent.width, input.extent.height))
        let transform = CGAffineTransform(scaleX: ratio, y: ratio)
        let extent = input.extent.applying(transform).integral
        // Extend before downsampling as well as blurring, so edge interpolation
        // never samples transparent pixels that turn black in the opaque JPEG.
        let reduced = input.clampedToExtent().transformed(by: transform)
        let blurred = reduced.applyingFilter(
            "CIGaussianBlur", parameters: [kCIInputRadiusKey: max(2, min(extent.width, extent.height) * 0.14)]
        )
        let backgroundPixels = imageContext.createCGImage(blurred, from: extent) ?? originalPixels
        let width = backgroundPixels.width
        let height = backgroundPixels.height
        let columns = [(0, 1), (0, width), (width - 1, 1)]
        let rows = [(0, 1), (0, height), (height - 1, 1)]
        let tiles = rows.flatMap { y, tileHeight in
            columns.map { x, tileWidth in
                backgroundPixels.cropping(to: CGRect(x: x, y: y, width: tileWidth, height: tileHeight))
            }
        }
        return PreparedPhoto(size: original.size, original: originalPixels, tiles: tiles)
    }

    private static func uprightImage(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up, image.cgImage != nil { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private final class PreparedPhoto: NSObject {
        let size: CGSize
        let original: CGImage?
        let tiles: [CGImage?]

        init(size: CGSize, original: CGImage?, tiles: [CGImage?]) {
            self.size = size
            self.original = original
            self.tiles = tiles
        }

        nonisolated deinit {}
    }
}
