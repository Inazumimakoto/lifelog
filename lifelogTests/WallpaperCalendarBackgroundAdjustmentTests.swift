import XCTest
@testable import lifelify

@MainActor
final class WallpaperCalendarBackgroundAdjustmentTests: XCTestCase {
    private let canvasSize = CGSize(width: 400, height: 800)
    private let accuracy = 0.000_001

    func testLandscapePhoto_minimumScaleShowsEntirePhoto() {
        assertMinimumScaleFits(imageSize: CGSize(width: 1_600, height: 900), expectedScale: 0.28125)
    }

    func testPortraitPhoto_minimumScaleShowsEntirePhoto() {
        assertMinimumScaleFits(imageSize: CGSize(width: 900, height: 1_600), expectedScale: 8.0 / 9)
    }

    func testPanoramaPhoto_minimumScaleAllowsSmallerThanFixedHalfScale() {
        assertMinimumScaleFits(imageSize: CGSize(width: 16_000, height: 1_000), expectedScale: 0.03125)
    }

    func testMatchingAspectRatio_minimumScaleRemainsOne() {
        assertMinimumScaleFits(imageSize: CGSize(width: 800, height: 1_600), expectedScale: 1)
    }

    func testUndersizedPhoto_allowsDraggingOnBothAxes() {
        let imageSize = CGSize(width: 1_600, height: 900)
        let adjustment = WallpaperCalendarBackgroundAdjustment(
            scale: WallpaperCalendarBackgroundAdjustment.minimumScale(for: imageSize, canvasSize: canvasSize),
            offsetX: 0.2,
            offsetY: 0.05
        )

        XCTAssertEqual(adjustment.clamped(for: imageSize, canvasSize: canvasSize), adjustment)
        let rect = adjustment.imageRect(for: imageSize, in: CGRect(origin: .zero, size: canvasSize))
        XCTAssertEqual(rect.midX, canvasSize.width * 0.7, accuracy: accuracy)
        XCTAssertEqual(rect.midY, canvasSize.height * 0.55, accuracy: accuracy)
    }

    func testExtremeDrag_keepsMostOfPhotoOrCanvasVisible() {
        let canvas = CGRect(origin: .zero, size: canvasSize)
        for imageSize in [CGSize(width: 1_600, height: 900), CGSize(width: 900, height: 1_600), CGSize(width: 16_000, height: 1_000)] {
            let minimumScale = WallpaperCalendarBackgroundAdjustment.minimumScale(for: imageSize, canvasSize: canvasSize)
            for scale in [minimumScale, 1, WallpaperCalendarBackgroundAdjustment.maxScale] {
                for direction in [-1.0, 1.0] {
                    let adjustment = WallpaperCalendarBackgroundAdjustment(
                        scale: scale,
                        offsetX: direction * 1_000_000,
                        offsetY: direction * 1_000_000
                    )
                    let rect = adjustment.imageRect(for: imageSize, in: canvas)
                    let intersection = rect.intersection(canvas)

                    XCTAssertGreaterThanOrEqual(intersection.width + accuracy, min(rect.width, canvas.width) * 0.75)
                    XCTAssertGreaterThanOrEqual(intersection.height + accuracy, min(rect.height, canvas.height) * 0.75)
                }
            }
        }
    }

    func testPreviouslyValidAdjustment_keepsScaleAndPosition() {
        let adjustment = WallpaperCalendarBackgroundAdjustment(scale: 1.7, offsetX: 0.25, offsetY: 0.05)

        XCTAssertEqual(adjustment.clamped(for: CGSize(width: 1_600, height: 900), canvasSize: canvasSize), adjustment)
        XCTAssertEqual(WallpaperCalendarBackgroundAdjustment.defaultValue.scale, 1)
    }

    func testScaleOutsideAllowedRange_clampsToFitAndMaximum() {
        let imageSize = CGSize(width: 1_600, height: 900)
        let minimumScale = WallpaperCalendarBackgroundAdjustment.minimumScale(for: imageSize, canvasSize: canvasSize)
        let tooSmall = WallpaperCalendarBackgroundAdjustment(scale: -1).clamped(for: imageSize, canvasSize: canvasSize)
        let tooLarge = WallpaperCalendarBackgroundAdjustment(scale: 100).clamped(for: imageSize, canvasSize: canvasSize)

        XCTAssertEqual(tooSmall.scale, minimumScale, accuracy: accuracy)
        XCTAssertEqual(tooLarge.scale, WallpaperCalendarBackgroundAdjustment.maxScale)
    }

    func testImageRect_preservesCanvasOriginAndNormalizedOffsets() {
        let imageSize = CGSize(width: 1_600, height: 900)
        let canvas = CGRect(origin: CGPoint(x: 30, y: 50), size: canvasSize)
        let adjustment = WallpaperCalendarBackgroundAdjustment(scale: 1, offsetX: 0.2, offsetY: -0.1)
        let rect = adjustment.imageRect(for: imageSize, in: canvas)

        XCTAssertEqual(rect.width, 1_600 * (800.0 / 900), accuracy: accuracy)
        XCTAssertEqual(rect.height, 800, accuracy: accuracy)
        XCTAssertEqual(rect.midX - canvas.midX, 0.2 * canvas.width, accuracy: accuracy)
        XCTAssertEqual(rect.midY - canvas.midY, -0.1 * canvas.height, accuracy: accuracy)
    }

    func testInvalidSizes_returnSafeDefaultsAndRectangles() {
        let canvas = CGRect(origin: .zero, size: canvasSize)
        for imageSize in [CGSize.zero, CGSize(width: -1, height: 900), CGSize(width: CGFloat.infinity, height: 900), CGSize(width: CGFloat.nan, height: 900)] {
            XCTAssertEqual(WallpaperCalendarBackgroundAdjustment.minimumScale(for: imageSize, canvasSize: canvasSize), 1)
            XCTAssertEqual(
                WallpaperCalendarBackgroundAdjustment(scale: 2, offsetX: 1, offsetY: 1).clamped(for: imageSize, canvasSize: canvasSize),
                WallpaperCalendarBackgroundAdjustment(scale: 2)
            )
            XCTAssertEqual(WallpaperCalendarBackgroundAdjustment.defaultValue.imageRect(for: imageSize, in: canvas), canvas)
        }

        for invalidCanvas in [CGRect.zero, CGRect(x: CGFloat.nan, y: 0, width: 400, height: 800), CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 800)] {
            XCTAssertEqual(
                WallpaperCalendarBackgroundAdjustment.defaultValue.imageRect(for: CGSize(width: 1_600, height: 900), in: invalidCanvas),
                .zero
            )
        }
    }

    func testNonfiniteAdjustment_returnsFiniteCenteredValues() {
        let imageSize = CGSize(width: 1_600, height: 900)
        for scale in [Double.nan, .infinity, -.infinity] {
            let adjustment = WallpaperCalendarBackgroundAdjustment(scale: scale, offsetX: .nan, offsetY: .infinity)
                .clamped(for: imageSize, canvasSize: canvasSize)

            XCTAssertEqual(adjustment, .defaultValue)
            let rect = adjustment.imageRect(for: imageSize, in: CGRect(origin: .zero, size: canvasSize))
            XCTAssertTrue(rect.minX.isFinite && rect.minY.isFinite && rect.maxX.isFinite && rect.maxY.isFinite)
        }
    }

    func testZoomedOutAdjustment_codableRoundTripPreservesPosition() throws {
        let adjustment = WallpaperCalendarBackgroundAdjustment(scale: 0.28125, offsetX: 0.2, offsetY: -0.05)
        let data = try JSONEncoder().encode(adjustment)

        XCTAssertEqual(try JSONDecoder().decode(WallpaperCalendarBackgroundAdjustment.self, from: data), adjustment)
    }

    private func assertMinimumScaleFits(imageSize: CGSize, expectedScale: Double,
                                        file: StaticString = #filePath, line: UInt = #line) {
        let scale = WallpaperCalendarBackgroundAdjustment.minimumScale(for: imageSize, canvasSize: canvasSize)
        let canvas = CGRect(origin: .zero, size: canvasSize)
        let rect = WallpaperCalendarBackgroundAdjustment(scale: scale).imageRect(for: imageSize, in: canvas)

        XCTAssertEqual(scale, expectedScale, accuracy: accuracy, file: file, line: line)
        XCTAssertLessThanOrEqual(rect.width, canvas.width + accuracy, file: file, line: line)
        XCTAssertLessThanOrEqual(rect.height, canvas.height + accuracy, file: file, line: line)
        XCTAssertTrue(abs(rect.width - canvas.width) < accuracy || abs(rect.height - canvas.height) < accuracy,
                      file: file, line: line)
        XCTAssertEqual(rect.midX, canvas.midX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(rect.midY, canvas.midY, accuracy: accuracy, file: file, line: line)
    }
}
