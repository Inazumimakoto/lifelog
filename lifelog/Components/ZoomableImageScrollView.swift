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
        context.coordinator.updateZoomBinding($isZoomed)
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.doubleTapZoomFactor = doubleTapZoomFactor
        context.coordinator.maximumZoomFactor = maximumZoomFactor

        context.coordinator.updateImage(image)
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
        private var isConfiguringLayout = false
        private var zoomStateUpdatePending = false

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
            guard !isConfiguringLayout else { return }
            centerImageIfNeeded()
            updateZoomState()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            guard !isConfiguringLayout else { return }
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

        func updateZoomBinding(_ binding: Binding<Bool>) {
            _isZoomed = binding
            updateZoomState()
        }

        func updateImage(_ image: UIImage) {
            if imageView?.image !== image {
                imageView?.image = image
            }
            // The caller keys this view by photo path. A preview/full-image swap
            // changes pixels only, including thumbnail aspect-ratio rounding.
            requestLayout(resetZoom: false)
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
            guard !isConfiguringLayout else { return }
            guard let scrollView, let imageView, let image = imageView.image else { return }
            let boundsSize = scrollView.bounds.size
            guard boundsSize.width > 0,
                  boundsSize.height > 0,
                  image.size.width > 0,
                  image.size.height > 0 else { return }

            let boundsChanged = boundsSize != lastBoundsSize
            let maximumScale = max(1, maximumZoomFactor)
            guard pendingResetZoom || boundsChanged || scrollView.maximumZoomScale != maximumScale else { return }

            let resetZoom = pendingResetZoom || lastBoundsSize == .zero
            let relativeZoom = resetZoom ? 1 : min(max(scrollView.zoomScale, 1), maximumScale)
            let focalPoint = resetZoom ? CGPoint(x: 0.5, y: 0.5) : normalizedVisibleCenter()

            isConfiguringLayout = true
            lastBoundsSize = boundsSize
            pendingResetZoom = false

            // One zoom unit always means the whole photo fits (docs/ui-guidelines.md).
            // Never assign a frame while UIScrollView has a zoom transform applied.
            UIView.performWithoutAnimation {
                scrollView.minimumZoomScale = 1
                scrollView.maximumZoomScale = maximumScale
                scrollView.setZoomScale(1, animated: false)
                scrollView.contentInset = .zero

                let fitScale = min(boundsSize.width / image.size.width, boundsSize.height / image.size.height)
                let fittedSize = CGSize(width: image.size.width * fitScale, height: image.size.height * fitScale)
                imageView.bounds = CGRect(origin: .zero, size: fittedSize)
                imageView.center = CGPoint(x: fittedSize.width / 2, y: fittedSize.height / 2)
                scrollView.contentSize = fittedSize
                scrollView.setZoomScale(relativeZoom, animated: false)
                centerImageIfNeeded()
                restoreVisibleCenter(focalPoint)
            }

            isConfiguringLayout = false
            updateZoomState()
        }

        private func normalizedVisibleCenter() -> CGPoint {
            guard let scrollView, let imageView,
                  imageView.bounds.width > 0, imageView.bounds.height > 0 else {
                return CGPoint(x: 0.5, y: 0.5)
            }
            // At this point bounds may already have changed for rotation.
            let previousCenter = CGPoint(x: scrollView.contentOffset.x + lastBoundsSize.width / 2,
                                         y: scrollView.contentOffset.y + lastBoundsSize.height / 2)
            let imagePoint = imageView.convert(previousCenter, from: scrollView)
            return CGPoint(x: min(max(imagePoint.x / imageView.bounds.width, 0), 1),
                           y: min(max(imagePoint.y / imageView.bounds.height, 0), 1))
        }

        private func restoreVisibleCenter(_ focalPoint: CGPoint) {
            guard let scrollView, let imageView else { return }
            let imagePoint = CGPoint(x: imageView.bounds.width * focalPoint.x,
                                     y: imageView.bounds.height * focalPoint.y)
            let contentPoint = imageView.convert(imagePoint, to: scrollView)
            let desiredOffset = CGPoint(x: contentPoint.x - scrollView.bounds.width / 2,
                                        y: contentPoint.y - scrollView.bounds.height / 2)
            let minimumX = -scrollView.contentInset.left
            let minimumY = -scrollView.contentInset.top
            let maximumX = max(minimumX, scrollView.contentSize.width - scrollView.bounds.width + scrollView.contentInset.right)
            let maximumY = max(minimumY, scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom)
            scrollView.contentOffset = CGPoint(x: min(max(desiredOffset.x, minimumX), maximumX),
                                               y: min(max(desiredOffset.y, minimumY), maximumY))
        }

        private func centerImageIfNeeded() {
            guard let scrollView, let imageView else { return }
            let contentWidth = imageView.frame.width
            let contentHeight = imageView.frame.height
            let insetX = max((scrollView.bounds.width - contentWidth) / 2, 0)
            let insetY = max((scrollView.bounds.height - contentHeight) / 2, 0)
            let insets = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
            if scrollView.contentInset != insets {
                scrollView.contentInset = insets
            }
        }

        private func updateZoomState() {
            guard !isConfiguringLayout, !zoomStateUpdatePending else { return }
            zoomStateUpdatePending = true
            // UIKit layout can run during updateUIView. Publish only the latest
            // state on the next turn, using the current page's refreshed binding.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.zoomStateUpdatePending = false
                guard let scrollView = self.scrollView else { return }
                let zoomed = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
                if self.isZoomed != zoomed {
                    self.isZoomed = zoomed
                }
            }
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
