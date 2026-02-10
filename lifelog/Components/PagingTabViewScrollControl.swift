//
//  PagingTabViewScrollControl.swift
//  lifelog
//
//  Created by Codex on 2026/02/10.
//

import SwiftUI
import UIKit

/// Controls page-style TabView scrolling by toggling the underlying paging scroll view.
struct PagingTabViewScrollControl: UIViewRepresentable {
    let isScrollEnabled: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            updatePagingScrollView(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            updatePagingScrollView(from: uiView)
        }
    }

    private func updatePagingScrollView(from anchorView: UIView) {
        guard let hostView = anchorView.superview else { return }
        guard let pagingScrollView = findPagingScrollView(in: hostView) else { return }
        guard pagingScrollView.isScrollEnabled != isScrollEnabled else { return }
        pagingScrollView.isScrollEnabled = isScrollEnabled
    }

    private func findPagingScrollView(in root: UIView) -> UIScrollView? {
        if let scrollView = root as? UIScrollView, scrollView.isPagingEnabled {
            return scrollView
        }
        for subview in root.subviews {
            if let found = findPagingScrollView(in: subview) {
                return found
            }
        }
        return nil
    }
}
