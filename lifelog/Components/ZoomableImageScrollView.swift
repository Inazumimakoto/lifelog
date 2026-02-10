//
//  ZoomableImageScrollView.swift
//  lifelog
//
//  Created by Codex on 2026/02/10.
//

import SwiftUI
import UIKit

struct ZoomableImageScrollView: UIViewRepresentable {
    let image: UIImage
    @Binding var isZoomed: Bool
    var onSingleTap: () -> Void
    var doubleTapZoomFactor: CGFloat = 2.5
    var maximumZoomFactor: CGFloat = 6

    func makeCoordinator() -> Coordinator {
        Coordinator(isZoomed: $isZoomed,
                    onSingleTap: onSingleTap,
                    doubleTapZoomFactor: doubleTapZoomFactor,
                    maximumZoomFactor: maximumZoomFactor)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = LayoutAwareZoomScrollView()
        scrollView.backgroundColor = .clear
        scrollView.delegate = context.coordinator
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView(image: image)
        imageView.backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)

        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView
        scrollView.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.containerDidLayout()
        }

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        context.coordinator.requestLayout(resetZoom: true)

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.doubleTapZoomFactor = doubleTapZoomFactor
        context.coordinator.maximumZoomFactor = maximumZoomFactor

        guard let imageView = context.coordinator.imageView else { return }
        let imageChanged = imageView.image !== image
        if imageChanged {
            imageView.image = image
        }

        context.coordinator.requestLayout(resetZoom: imageChanged)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        @Binding private var isZoomed: Bool
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        var onSingleTap: () -> Void
        var doubleTapZoomFactor: CGFloat
        var maximumZoomFactor: CGFloat
        private var lastBoundsSize: CGSize = .zero
        private var pendingResetZoom = true

        init(isZoomed: Binding<Bool>,
             onSingleTap: @escaping () -> Void,
             doubleTapZoomFactor: CGFloat,
             maximumZoomFactor: CGFloat) {
            _isZoomed = isZoomed
            self.onSingleTap = onSingleTap
            self.doubleTapZoomFactor = doubleTapZoomFactor
            self.maximumZoomFactor = maximumZoomFactor
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImageIfNeeded()
            updateZoomState()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            centerImageIfNeeded()
            updateZoomState()
        }

        func requestLayout(resetZoom: Bool) {
            if resetZoom {
                pendingResetZoom = true
            }
            configureLayoutIfPossible()
        }

        func containerDidLayout() {
            configureLayoutIfPossible()
        }

        @objc func handleSingleTap() {
            onSingleTap()
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView, let imageView else { return }

            let minimumScale = scrollView.minimumZoomScale
            if scrollView.zoomScale > minimumScale + 0.01 {
                scrollView.setZoomScale(minimumScale, animated: true)
                return
            }

            let targetScale = min(scrollView.maximumZoomScale, minimumScale * doubleTapZoomFactor)
            let tapPoint = gesture.location(in: imageView)
            let rect = zoomRect(for: targetScale, center: tapPoint, in: scrollView)
            scrollView.zoom(to: rect, animated: true)
        }

        private func configureLayoutIfPossible() {
            guard let scrollView, let imageView, let image = imageView.image else { return }
            let boundsSize = scrollView.bounds.size
            guard boundsSize.width > 0,
                  boundsSize.height > 0,
                  image.size.width > 0,
                  image.size.height > 0 else { return }

            let boundsChanged = boundsSize != lastBoundsSize
            guard pendingResetZoom || boundsChanged else { return }

            imageView.frame = CGRect(origin: .zero, size: image.size)
            scrollView.contentSize = image.size

            let xScale = boundsSize.width / image.size.width
            let yScale = boundsSize.height / image.size.height
            let minimumScale = min(xScale, yScale)
            let maximumScale = max(minimumScale * maximumZoomFactor, minimumScale + 0.01)
            lastBoundsSize = boundsSize

            scrollView.minimumZoomScale = minimumScale
            scrollView.maximumZoomScale = maximumScale

            if pendingResetZoom {
                scrollView.zoomScale = minimumScale
                pendingResetZoom = false
            } else {
                let clamped = min(max(scrollView.zoomScale, minimumScale), maximumScale)
                if abs(clamped - scrollView.zoomScale) > 0.0001 {
                    scrollView.zoomScale = clamped
                }
            }

            centerImageIfNeeded()
            updateZoomState()
        }

        private func centerImageIfNeeded() {
            guard let scrollView, let imageView else { return }
            let contentWidth = imageView.frame.width
            let contentHeight = imageView.frame.height
            let insetX = max((scrollView.bounds.width - contentWidth) / 2, 0)
            let insetY = max((scrollView.bounds.height - contentHeight) / 2, 0)
            scrollView.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
        }

        private func updateZoomState() {
            guard let scrollView else { return }
            isZoomed = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
        }

        private func zoomRect(for scale: CGFloat, center: CGPoint, in scrollView: UIScrollView) -> CGRect {
            let size = scrollView.bounds.size
            let width = size.width / scale
            let height = size.height / scale
            return CGRect(x: center.x - width / 2,
                          y: center.y - height / 2,
                          width: width,
                          height: height)
        }
    }
}

private final class LayoutAwareZoomScrollView: UIScrollView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
