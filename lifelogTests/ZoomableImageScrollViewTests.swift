import SwiftUI
import UIKit
import XCTest
@testable import lifelify

@MainActor
final class ZoomableImageScrollViewTests: XCTestCase {
    func testInitialLandscapePhoto_fitsViewport() {
        let fixture = Fixture(imageSize: CGSize(width: 512, height: 384))
        assertFitted(fixture, size: CGSize(width: 390, height: 292.5))
    }

    func testThumbnailReplacement_staysFittedWithoutUserInput() {
        let fixture = Fixture(imageSize: CGSize(width: 512, height: 384))
        fixture.coordinator.updateImage(makeImage(size: CGSize(width: 4032, height: 3024)))

        assertFitted(fixture, size: CGSize(width: 390, height: 292.5))
    }

    func testZoomOutAfterReplacement_restoresWholePhoto() async {
        let fixture = Fixture(imageSize: CGSize(width: 512, height: 384))
        fixture.coordinator.updateImage(makeImage(size: CGSize(width: 4032, height: 3024)))
        fixture.scrollView.setZoomScale(4, animated: false)
        fixture.scrollView.contentOffset = CGPoint(x: 350, y: 100)
        await flushZoomState()
        XCTAssertTrue(fixture.zoomState.value)

        fixture.scrollView.setZoomScale(1, animated: false)
        fixture.scrollView.layoutIfNeeded()
        await flushZoomState()

        assertFitted(fixture, size: CGSize(width: 390, height: 292.5))
        XCTAssertFalse(fixture.zoomState.value)
    }

    func testRoundedThumbnailReplacement_preservesZoomAndPan() {
        // Thumbnail pixel rounding changes the aspect ratio very slightly.
        let fixture = Fixture(imageSize: CGSize(width: 237, height: 512))
        fixture.scrollView.setZoomScale(2.5, animated: false)
        fixture.scrollView.contentOffset = CGPoint(x: 280, y: 550)
        let initialFrame = fixture.imageView.frame
        let initialOffset = fixture.scrollView.contentOffset
        let fullImage = makeImage(size: CGSize(width: 1170, height: 2532))

        fixture.coordinator.updateImage(fullImage)

        XCTAssertTrue(fixture.imageView.image === fullImage)
        XCTAssertEqual(fixture.scrollView.zoomScale, 2.5, accuracy: 0.001)
        XCTAssertEqual(fixture.imageView.frame, initialFrame)
        XCTAssertEqual(fixture.scrollView.contentOffset, initialOffset)
        // Releasing the full image on a neighbouring page also keeps its geometry.
        fixture.coordinator.updateImage(makeImage(size: CGSize(width: 237, height: 512)))
        XCTAssertEqual(fixture.imageView.frame, initialFrame)
        XCTAssertEqual(fixture.scrollView.contentOffset, initialOffset)
    }

    func testRotationOfFittedPhoto_keepsWholePhotoVisible() {
        let fixture = Fixture(imageSize: CGSize(width: 4032, height: 3024))
        fixture.resize(to: CGSize(width: 844, height: 390))
        assertFitted(fixture, size: CGSize(width: 520, height: 390))

        fixture.resize(to: CGSize(width: 390, height: 844))
        assertFitted(fixture, size: CGSize(width: 390, height: 292.5))
    }

    func testRotationOfZoomedPhoto_preservesMagnificationAndFocalPoint() {
        let fixture = Fixture(imageSize: CGSize(width: 4032, height: 3024))
        fixture.scrollView.setZoomScale(4, animated: false)
        fixture.scrollView.contentOffset = CGPoint(x: 550, y: 120)
        let initialCenter = fixture.normalizedVisibleCenter

        fixture.resize(to: CGSize(width: 844, height: 390))

        XCTAssertEqual(fixture.scrollView.zoomScale, 4, accuracy: 0.001)
        XCTAssertEqual(fixture.normalizedVisibleCenter.x, initialCenter.x, accuracy: 0.001)
        XCTAssertEqual(fixture.normalizedVisibleCenter.y, initialCenter.y, accuracy: 0.001)
        fixture.scrollView.setZoomScale(1, animated: false)
        fixture.scrollView.layoutIfNeeded()
        assertFitted(fixture, size: CGSize(width: 520, height: 390))
    }

    func testRotationNearPhotoEdge_clampsToVisibleContent() {
        let fixture = Fixture(imageSize: CGSize(width: 4032, height: 3024))
        fixture.scrollView.setZoomScale(2, animated: false)
        fixture.scrollView.contentOffset = CGPoint(x: 0, y: -fixture.scrollView.contentInset.top)

        fixture.resize(to: CGSize(width: 844, height: 390))

        XCTAssertEqual(fixture.scrollView.zoomScale, 2, accuracy: 0.001)
        XCTAssertEqual(fixture.scrollView.contentOffset.x, 0, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(fixture.scrollView.contentOffset.y, -fixture.scrollView.contentInset.top)
        XCTAssertLessThanOrEqual(fixture.scrollView.contentOffset.y,
                                fixture.scrollView.contentSize.height - fixture.scrollView.bounds.height + fixture.scrollView.contentInset.bottom)
    }

    func testRepeatedLayout_doesNotDriftOrResetZoom() {
        let fixture = Fixture(imageSize: CGSize(width: 3024, height: 4032))
        fixture.scrollView.setZoomScale(3, animated: false)
        fixture.scrollView.contentOffset = CGPoint(x: 260, y: 420)
        let originalFrame = fixture.imageView.frame
        let originalOffset = fixture.scrollView.contentOffset

        for _ in 0..<10 { fixture.coordinator.containerDidLayout() }

        XCTAssertEqual(fixture.imageView.frame, originalFrame)
        XCTAssertEqual(fixture.scrollView.contentOffset, originalOffset)
        XCTAssertEqual(fixture.scrollView.zoomScale, 3, accuracy: 0.001)
    }

    func testBindingChangesBeforePublication_updatesCurrentPageOnly() async {
        let fixture = Fixture(imageSize: CGSize(width: 512, height: 384))
        let currentPage = ZoomState()
        fixture.scrollView.setZoomScale(2.5, animated: false)
        fixture.coordinator.updateZoomBinding(currentPage.binding)

        await flushZoomState()

        XCTAssertFalse(fixture.zoomState.value)
        XCTAssertTrue(currentPage.value)
        fixture.scrollView.setZoomScale(1, animated: false)
        await flushZoomState()
        XCTAssertFalse(currentPage.value)
    }

    func testImageLoadsBeforeViewportBecomesAvailable_fitsOnFirstLayout() {
        let fixture = Fixture(imageSize: CGSize(width: 512, height: 384), viewport: .zero)
        fixture.coordinator.updateImage(makeImage(size: CGSize(width: 4032, height: 3024)))

        fixture.resize(to: CGSize(width: 390, height: 844))

        assertFitted(fixture, size: CGSize(width: 390, height: 292.5))
    }

    func testHostedViewer_imageUpdateKeepsScrollViewAndDoubleTapReturnsToFit() async throws {
        let state = HostedPhotoState(image: makeImage(size: CGSize(width: 512, height: 384)))
        let controller = UIHostingController(rootView: HostedPhoto(state: state))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        controller.view.layoutIfNeeded()
        await flushZoomState()
        let scrollView = try XCTUnwrap(findScrollView(in: controller.view))
        let coordinator = try XCTUnwrap(scrollView.delegate as? ZoomableImageScrollView.Coordinator)
        let imageView = try XCTUnwrap(coordinator.imageView)
        let doubleTap = try XCTUnwrap(scrollView.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }
            .first { $0.numberOfTapsRequired == 2 })
        XCTAssertGreaterThan(scrollView.bounds.width, 0)

        coordinator.handleDoubleTap(doubleTap)
        try await waitForZoom(2.5, in: scrollView)
        let previousFrame = imageView.frame
        let previousOffset = scrollView.contentOffset
        state.image = makeImage(size: CGSize(width: 4032, height: 3024))
        // Allow SwiftUI to deliver updateUIView, including the zoom binding update.
        for _ in 0..<3 {
            await flushZoomState()
            controller.view.layoutIfNeeded()
        }

        XCTAssertTrue(findScrollView(in: controller.view) === scrollView)
        XCTAssertTrue(imageView.image === state.image)
        XCTAssertEqual(imageView.frame, previousFrame)
        XCTAssertEqual(scrollView.contentOffset, previousOffset)
        XCTAssertTrue(state.isZoomed)

        coordinator.handleDoubleTap(doubleTap)
        try await waitForZoom(1, in: scrollView)
        await flushZoomState()
        XCTAssertLessThanOrEqual(imageView.frame.width, scrollView.bounds.width + 0.5)
        XCTAssertLessThanOrEqual(imageView.frame.height, scrollView.bounds.height + 0.5)
        XCTAssertEqual(scrollView.contentOffset.x, -scrollView.contentInset.left, accuracy: 0.5)
        XCTAssertEqual(scrollView.contentOffset.y, -scrollView.contentInset.top, accuracy: 0.5)
        XCTAssertFalse(state.isZoomed)
    }

    private func assertFitted(_ fixture: Fixture, size: CGSize, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(fixture.scrollView.zoomScale, 1, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(fixture.imageView.frame.width, size.width, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(fixture.imageView.frame.height, size.height, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(fixture.scrollView.contentOffset.x, -fixture.scrollView.contentInset.left, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(fixture.scrollView.contentOffset.y, -fixture.scrollView.contentInset.top, accuracy: 0.5, file: file, line: line)
    }

    private func flushZoomState() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func waitForZoom(_ scale: CGFloat, in scrollView: UIScrollView) async throws {
        for _ in 0..<100 {
            if abs(scrollView.zoomScale - scale) < 0.001 && !scrollView.isZooming { return }
            try await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Zoom did not settle at \(scale); actual \(scrollView.zoomScale)")
    }

    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for subview in view.subviews {
            if let scrollView = findScrollView(in: subview) { return scrollView }
        }
        return nil
    }

    @MainActor
    private final class HostedPhotoState: ObservableObject {
        @Published var image: UIImage
        @Published var isZoomed = false
        init(image: UIImage) { self.image = image }
    }

    private struct HostedPhoto: View {
        @ObservedObject var state: HostedPhotoState
        var body: some View {
            ZoomableImageScrollView(image: state.image, isZoomed: $state.isZoomed, onSingleTap: {})
                .id("test-photo.jpg")
        }
    }

    @MainActor
    private final class ZoomState {
        var value = false
        var binding: Binding<Bool> {
            Binding(get: { self.value }, set: { self.value = $0 })
        }
    }

    @MainActor
    private final class Fixture {
        let scrollView: UIScrollView
        let imageView: UIImageView
        let zoomState = ZoomState()
        let coordinator: ZoomableImageScrollView.Coordinator

        init(imageSize: CGSize, viewport: CGSize = CGSize(width: 390, height: 844)) {
            scrollView = UIScrollView(frame: CGRect(origin: .zero, size: viewport))
            imageView = UIImageView(image: ZoomableImageScrollViewTests.makeImage(size: imageSize))
            imageView.contentMode = .scaleAspectFit
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.addSubview(imageView)
            coordinator = ZoomableImageScrollView.Coordinator(
                isZoomed: zoomState.binding, onSingleTap: {}, doubleTapZoomFactor: 2.5, maximumZoomFactor: 6
            )
            scrollView.delegate = coordinator
            coordinator.scrollView = scrollView
            coordinator.imageView = imageView
            coordinator.requestLayout(resetZoom: true)
        }

        var normalizedVisibleCenter: CGPoint {
            let center = imageView.convert(CGPoint(x: scrollView.bounds.midX, y: scrollView.bounds.midY), from: scrollView)
            return CGPoint(x: center.x / imageView.bounds.width, y: center.y / imageView.bounds.height)
        }

        func resize(to size: CGSize) {
            scrollView.frame = CGRect(origin: .zero, size: size)
            coordinator.containerDidLayout()
        }
    }

    private func makeImage(size: CGSize) -> UIImage { Self.makeImage(size: size) }

    private static func makeImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
