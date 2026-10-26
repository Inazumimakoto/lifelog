import UIKit
import XCTest
@testable import lifelify

@MainActor
final class WallpaperCalendarPhotoBackgroundTests: XCTestCase {
    private let canvasSize = CGSize(width: 160, height: 320)

    func testZoomedOutLandscapePhoto_extendsEdgesWithoutRepeatingCenterSubject() throws {
        let source = landscapePhoto()
        let output = render(source, adjustment: fittedAdjustment(for: source))
        let pixels = try PixelBuffer(output)

        // Blur can mix adjacent colors, but each margin must retain its own edge's color.
        assertDominantEdgeColor(pixels.color(x: 80, y: 12), channel: .red)
        assertDominantEdgeColor(pixels.color(x: 80, y: 86), channel: .red)
        assertDominantEdgeColor(pixels.color(x: 80, y: 236), channel: .blue)
        assertDominantEdgeColor(pixels.color(x: 80, y: 307), channel: .blue)
        assertColor(pixels.color(x: 80, y: 160), equals: .magenta)
        assertColor(pixels.color(x: 50, y: 160), equals: .green)
        assertOpaque(pixels)
        attach(output, name: "Landscape photo fitted with extended edges")
    }

    func testZoomedOutPortraitPhoto_fillsBothSideMarginsWithTheirRespectiveEdges() throws {
        let source = makeImage(size: CGSize(width: 40, height: 160)) { rect in
            UIColor.green.setFill()
            UIRectFill(rect)
            UIColor.red.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 10, height: 160))
            UIColor.blue.setFill()
            UIRectFill(CGRect(x: 30, y: 0, width: 10, height: 160))
            UIColor.magenta.setFill()
            UIRectFill(CGRect(x: 15, y: 60, width: 10, height: 40))
        }
        let output = render(source, adjustment: fittedAdjustment(for: source))
        let pixels = try PixelBuffer(output)

        assertDominantEdgeColor(pixels.color(x: 8, y: 160), channel: .red)
        assertDominantEdgeColor(pixels.color(x: 151, y: 160), channel: .blue)
        assertColor(pixels.color(x: 80, y: 160), equals: .magenta)
        assertOpaque(pixels)
        attach(output, name: "Portrait photo fitted with extended sides")
    }

    func testDraggingExistingComposition_movesSharpPhotoAndItsEdgeFillTogether() throws {
        let source = landscapePhoto()
        let background = WallpaperCalendarPhotoBackground(image: source)
        var adjustment = fittedAdjustment(for: source)
        background.update(size: canvasSize, adjustment: adjustment, contentsScale: 1)
        let before = try PixelBuffer(renderLayer(background.layer, size: canvasSize))

        adjustment.offsetX = 0.15
        adjustment.offsetY = 0.05
        background.update(size: canvasSize, adjustment: adjustment, contentsScale: 1)
        let output = renderLayer(background.layer, size: canvasSize)
        let after = try PixelBuffer(output)

        assertColor(before.color(x: 80, y: 166), equals: .magenta)
        assertColor(after.color(x: 80, y: 166), equals: .green)
        assertColor(after.color(x: 104, y: 176), equals: .magenta)
        assertDominantEdgeColor(after.color(x: 104, y: 20), channel: .red)
        assertDominantEdgeColor(after.color(x: 104, y: 300), channel: .blue)
        assertOpaque(after)
        attach(output, name: "Fitted photo after horizontal and vertical drag")
    }

    func testCoveringPhoto_preservesOriginalPixelsIncludingItsEdges() throws {
        let source = landscapePhoto()
        let output = render(source, adjustment: .defaultValue, size: source.size)
        let actual = try PixelBuffer(output)
        let expected = try PixelBuffer(source)

        for y in stride(from: 0, to: actual.height, by: 3) {
            for x in stride(from: 0, to: actual.width, by: 3) {
                assertColor(actual.color(x: x, y: y), equals: expected.color(x: x, y: y), tolerance: 0.015)
            }
        }
    }

    func testReturningFromFitToCover_removesEdgeFeatherFromOriginalPhoto() throws {
        let source = landscapePhoto()
        let background = WallpaperCalendarPhotoBackground(image: source)
        background.update(size: canvasSize, adjustment: fittedAdjustment(for: source), contentsScale: 1)
        background.update(size: source.size, adjustment: .defaultValue, contentsScale: 1)
        let actual = try PixelBuffer(renderLayer(background.layer, size: source.size))
        let expected = try PixelBuffer(source)

        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 80, y: 0), CGPoint(x: 159, y: 79), CGPoint(x: 80, y: 79)] {
            assertColor(actual.color(x: Int(point.x), y: Int(point.y)),
                        equals: expected.color(x: Int(point.x), y: Int(point.y)))
        }
    }

    func testOrientedPhoto_matchesUIKitPhotoOrientation() throws {
        let source = landscapePhoto()
        let pixels = try XCTUnwrap(source.cgImage)
        for orientation in [UIImage.Orientation.right, .left, .down, .upMirrored] {
            let oriented = UIImage(cgImage: pixels, scale: 1, orientation: orientation)
            let reference = makeImage(size: oriented.size) { rect in oriented.draw(in: rect) }
            let actual = try PixelBuffer(render(oriented, adjustment: .defaultValue, size: oriented.size))
            let expected = try PixelBuffer(reference)

            for y in stride(from: 5, to: actual.height, by: 10) {
                for x in stride(from: 5, to: actual.width, by: 10) {
                    assertColor(actual.color(x: x, y: y), equals: expected.color(x: x, y: y), tolerance: 0.015)
                }
            }
        }
    }

    func testEditorPhotoView_matchesExportCompositionAfterAdjustmentChanges() throws {
        let source = landscapePhoto()
        let (window, view) = makeHostedPhotoView(size: canvasSize)
        defer { removeHostedPhotoView(window) }
        view.update(image: source, adjustment: .defaultValue)
        var adjustment = fittedAdjustment(for: source)
        adjustment.offsetX = -0.1
        adjustment.offsetY = 0.04
        view.update(image: source, adjustment: adjustment)
        view.layoutIfNeeded()

        let scale = window.screen.scale
        let preview = try PixelBuffer(renderLayer(view.layer, size: canvasSize, scale: scale))
        let exported = try PixelBuffer(render(source, adjustment: adjustment, scale: scale))
        for y in stride(from: 2, to: preview.height, by: 11) {
            for x in stride(from: 2, to: preview.width, by: 11) {
                let actual = preview.color(x: x, y: y)
                let expected = exported.color(x: x, y: y)
                guard !colorsMatch(actual, expected, tolerance: 0.015) else { continue }
                XCTFail("Editor/export mismatch at (\(x), \(y)): \(actual), expected \(expected)")
                return
            }
        }
    }

    func testFractionalPhotoPlacement_atRetinaScalesLeavesNoDarkSeams() throws {
        let size = CGSize(width: 163, height: 327)
        for sourceSize in [CGSize(width: 173, height: 91), CGSize(width: 71, height: 193)] {
            let source = makeImage(size: sourceSize) { rect in
                UIColor.white.setFill()
                UIRectFill(rect)
            }
            let minimumScale = WallpaperCalendarBackgroundAdjustment.minimumScale(for: source.size, canvasSize: size)
            let background = WallpaperCalendarPhotoBackground(image: source)
            let (window, view) = makeHostedPhotoView(size: size)
            defer { removeHostedPhotoView(window) }
            let adjustments = [
                WallpaperCalendarBackgroundAdjustment(scale: minimumScale * 1.13, offsetX: 0.073, offsetY: 0.031),
                WallpaperCalendarBackgroundAdjustment(scale: minimumScale * 1.07, offsetX: -0.109, offsetY: -0.047),
                WallpaperCalendarBackgroundAdjustment(scale: minimumScale * 1.29, offsetX: 0.151, offsetY: -0.019)
            ]

            for scale in [CGFloat(2), CGFloat(3)] {
                for adjustment in adjustments {
                    background.update(size: size, adjustment: adjustment, contentsScale: scale)
                    view.update(image: source, adjustment: adjustment)
                    view.layoutIfNeeded()
                    for (name, layer) in [("export composition", background.layer), ("editor view", view.layer)] {
                        let pixels = try PixelBuffer(renderLayer(layer, size: size, scale: scale))
                        XCTAssertEqual(pixels.width, Int(size.width * scale))
                        XCTAssertEqual(pixels.height, Int(size.height * scale))
                        assertUniformWhite(pixels, description: "\(name), \(sourceSize), scale \(scale), \(adjustment)")
                    }
                }
            }
        }
    }

    func testExportedJPEG_outerEdgesMatchEditorWithoutDarkLines() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suite = "WallpaperCalendarPhotoBackgroundTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let fileManager = IsolatedFileManager(rootURL: directory)
        let store = WallpaperCalendarSettingsStore(defaults: defaults, fileManager: fileManager)
        let source = makeImage(size: CGSize(width: 173, height: 91)) { rect in
            UIColor.white.setFill()
            UIRectFill(rect)
        }
        _ = try store.saveBackgroundImageData(XCTUnwrap(source.pngData()))
        let size = CGSize(width: 163, height: 327)
        let adjustment = WallpaperCalendarBackgroundAdjustment(
            scale: WallpaperCalendarBackgroundAdjustment.minimumScale(for: source.size, canvasSize: size) * 1.13,
            offsetX: 0.073, offsetY: 0.031
        )
        _ = store.update { $0.backgroundAdjustment = adjustment }
        let renderer = WallpaperCalendarRenderer(settingsStore: store,
                                                  dataProvider: WallpaperCalendarDataProvider(),
                                                  fileManager: fileManager)
        let (window, view) = makeHostedPhotoView(size: size)
        defer { removeHostedPhotoView(window) }
        view.update(image: source, adjustment: adjustment)
        view.layoutIfNeeded()

        // Freeze both editor snapshots before exercising the independent export path.
        let scales = [CGFloat(2), CGFloat(3)]
        let editorImages = scales.map { renderLayer(view.layer, size: size, scale: $0) }
        for (scale, editorImage) in zip(scales, editorImages) {
            assertOpaque(try PixelBuffer(editorImage))
            let previewImage = makeImage(size: size, scale: scale) { rect in
                editorImage.draw(in: rect)
                UIColor.black.withAlphaComponent(0.18).setFill()
                UIBezierPath(rect: rect).fill()
            }
            let url = try renderer.render(force: true, now: Date(timeIntervalSince1970: 946_684_800),
                                          screenSize: size, scale: scale)
            let exported = try PixelBuffer(XCTUnwrap(UIImage(contentsOfFile: url.path)))
            let preview = try PixelBuffer(previewImage)
            XCTAssertEqual(exported.width, preview.width)
            XCTAssertEqual(exported.height, preview.height)
            // Calendar content starts at least 26pt from the sides. Check side and
            // top borders, including all corners, through the actual JPEG writer/decoder.
            let border = Int(8 * scale)
            for y in 0..<exported.height {
                for x in 0..<exported.width where x < border || x >= exported.width - border || y < border {
                    let actual = exported.color(x: x, y: y)
                    let expected = preview.color(x: x, y: y)
                    guard !colorsMatch(actual, expected, tolerance: 0.04) else { continue }
                    XCTFail("JPEG/editor mismatch at (\(x), \(y)), scale \(scale): \(actual), expected \(expected)")
                    return
                }
            }
        }
    }

    private func landscapePhoto() -> UIImage {
        makeImage(size: CGSize(width: 160, height: 80)) { rect in
            UIColor.green.setFill()
            UIRectFill(rect)
            UIColor.red.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 160, height: 16))
            UIColor.blue.setFill()
            UIRectFill(CGRect(x: 0, y: 64, width: 160, height: 16))
            UIColor.magenta.setFill()
            UIRectFill(CGRect(x: 64, y: 30, width: 32, height: 20))
        }
    }

    private func fittedAdjustment(for image: UIImage) -> WallpaperCalendarBackgroundAdjustment {
        WallpaperCalendarBackgroundAdjustment(
            scale: WallpaperCalendarBackgroundAdjustment.minimumScale(for: image.size, canvasSize: canvasSize)
        )
    }

    private func makeHostedPhotoView(size: CGSize) -> (UIWindow, WallpaperCalendarPhotoBackgroundView.PhotoView) {
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        let controller = UIViewController()
        controller.view = UIView(frame: window.bounds)
        window.rootViewController = controller
        let view = WallpaperCalendarPhotoBackgroundView.PhotoView(frame: CGRect(origin: .zero, size: size))
        controller.view.addSubview(view)
        // UIKit-backed layers need a visible hierarchy before an offscreen render.
        // This window never becomes key, and each test removes it on completion.
        window.isHidden = false
        window.layoutIfNeeded()
        view.layoutIfNeeded()
        return (window, view)
    }

    private func removeHostedPhotoView(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
    }

    private func render(_ image: UIImage,
                        adjustment: WallpaperCalendarBackgroundAdjustment,
                        size: CGSize? = nil,
                        scale: CGFloat = 1) -> UIImage {
        let size = size ?? canvasSize
        let background = WallpaperCalendarPhotoBackground(image: image)
        background.update(size: size, adjustment: adjustment, contentsScale: scale)
        return renderLayer(background.layer, size: size, scale: scale)
    }

    private func renderLayer(_ layer: CALayer, size: CGSize, scale: CGFloat = 1) -> UIImage {
        layer.layoutIfNeeded()
        layer.displayIfNeeded()
        return makeImage(size: size, scale: scale) { _ in
            if let context = UIGraphicsGetCurrentContext() { layer.render(in: context) }
        }
    }

    private func makeImage(size: CGSize, scale: CGFloat = 1, draw: (CGRect) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(CGRect(origin: .zero, size: size))
        }
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertOpaque(_ pixels: PixelBuffer, file: StaticString = #filePath, line: UInt = #line) {
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                guard pixels.color(x: x, y: y).alpha < 0.99 else { continue }
                XCTFail("Transparent background pixel at (\(x), \(y))", file: file, line: line)
                return
            }
        }
    }

    private func assertUniformWhite(_ pixels: PixelBuffer,
                                    description: String,
                                    file: StaticString = #filePath,
                                    line: UInt = #line) {
        // White over the composition's black base exposes both transparent holes
        // and black antialiasing seams, including the outermost canvas pixels.
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let color = pixels.color(x: x, y: y)
                guard color.red < 0.99 || color.green < 0.99 || color.blue < 0.99 || color.alpha < 0.99 else { continue }
                XCTFail("Dark or transparent seam at (\(x), \(y)): \(color), \(description)", file: file, line: line)
                return
            }
        }
    }

    private enum EdgeColor {
        case red
        case blue
    }

    private func assertDominantEdgeColor(_ color: PixelColor,
                                         channel: EdgeColor,
                                         file: StaticString = #filePath,
                                         line: UInt = #line) {
        let dominant = channel == .red ? color.red : color.blue
        let other = max(color.green, channel == .red ? color.blue : color.red)
        XCTAssertGreaterThan(dominant, 0.7, "Edge color was lost", file: file, line: line)
        XCTAssertGreaterThan(dominant - other, 0.3, "Wrong edge color or repeated subject", file: file, line: line)
        XCTAssertGreaterThanOrEqual(color.alpha, 0.99, file: file, line: line)
    }

    private func assertColor(_ actual: PixelColor,
                             equals expected: UIColor,
                             tolerance: Double = 0.025,
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        expected.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        assertColor(actual, equals: PixelColor(red: red, green: green, blue: blue, alpha: alpha),
                    tolerance: tolerance, file: file, line: line)
    }

    private func assertColor(_ actual: PixelColor,
                             equals expected: PixelColor,
                             tolerance: Double = 0.025,
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        XCTAssertEqual(actual.red, expected.red, accuracy: tolerance, "Red", file: file, line: line)
        XCTAssertEqual(actual.green, expected.green, accuracy: tolerance, "Green", file: file, line: line)
        XCTAssertEqual(actual.blue, expected.blue, accuracy: tolerance, "Blue", file: file, line: line)
        XCTAssertEqual(actual.alpha, expected.alpha, accuracy: tolerance, "Alpha", file: file, line: line)
    }

    private func colorsMatch(_ actual: PixelColor, _ expected: PixelColor, tolerance: Double) -> Bool {
        abs(actual.red - expected.red) <= tolerance &&
            abs(actual.green - expected.green) <= tolerance &&
            abs(actual.blue - expected.blue) <= tolerance &&
            abs(actual.alpha - expected.alpha) <= tolerance
    }

    private struct PixelColor {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
            self.red = Double(red)
            self.green = Double(green)
            self.blue = Double(blue)
            self.alpha = Double(alpha)
        }
    }

    private struct PixelBuffer {
        let width: Int
        let height: Int
        private let data: [UInt8]

        init(_ image: UIImage) throws {
            let cgImage = try XCTUnwrap(image.cgImage)
            let width = cgImage.width
            let height = cgImage.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            try pixels.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            self.width = width
            self.height = height
            data = pixels
        }

        func color(x: Int, y: Int) -> PixelColor {
            let offset = (y * width + x) * 4
            return PixelColor(red: CGFloat(data[offset]) / 255,
                              green: CGFloat(data[offset + 1]) / 255,
                              blue: CGFloat(data[offset + 2]) / 255,
                              alpha: CGFloat(data[offset + 3]) / 255)
        }
    }

    private final class IsolatedFileManager: FileManager, @unchecked Sendable {
        private let rootURL: URL

        init(rootURL: URL) {
            self.rootURL = rootURL
            super.init()
        }

        override func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? {
            rootURL
        }
    }
}
