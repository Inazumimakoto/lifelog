//
//  MemoTextView.swift
//  lifelog
//
//  Created by Codex on 2026/05/14.
//

import SwiftUI
import UIKit

struct MemoTextView: UIViewRepresentable {
    let initialText: String
    let onTextChange: (String) -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.contentInsetAdjustmentBehavior = .never
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.text = initialText
        textView.layoutManager.allowsNonContiguousLayout = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        context.coordinator.startKeyboardObserving(for: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onTextChange = onTextChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: onTextChange)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onTextChange: (String) -> Void
        private weak var textView: UITextView?
        private var keyboardObservers: [NSObjectProtocol] = []
        private var lastBottomInset: CGFloat = 0

        init(onTextChange: @escaping (String) -> Void) {
            self.onTextChange = onTextChange
        }

        deinit {
            stopKeyboardObserving()
        }

        func textViewDidChange(_ textView: UITextView) {
            onTextChange(textView.text)
        }

        func startKeyboardObserving(for textView: UITextView) {
            self.textView = textView
            guard keyboardObservers.isEmpty else { return }

            let center = NotificationCenter.default
            keyboardObservers = [
                center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification,
                                   object: nil,
                                   queue: .main) { [weak self] notification in
                    self?.updateKeyboardInset(notification: notification)
                },
                center.addObserver(forName: UIResponder.keyboardWillHideNotification,
                                   object: nil,
                                   queue: .main) { [weak self] _ in
                    self?.setBottomInset(0)
                }
            ]
        }

        private func stopKeyboardObserving() {
            let center = NotificationCenter.default
            keyboardObservers.forEach { center.removeObserver($0) }
            keyboardObservers.removeAll()
        }

        private func updateKeyboardInset(notification: Notification) {
            guard let textView, let window = textView.window else { return }
            guard let screenFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }

            let windowFrame = window.convert(screenFrame, from: nil)
            let localFrame = textView.convert(windowFrame, from: window)
            let overlap = textView.bounds.intersection(localFrame).height
            setBottomInset(max(0, overlap + 12))
        }

        private func setBottomInset(_ bottomInset: CGFloat) {
            guard let textView else { return }
            guard abs(lastBottomInset - bottomInset) > 0.5 else { return }

            lastBottomInset = bottomInset
            let contentOffset = textView.contentOffset

            var contentInset = textView.contentInset
            contentInset.bottom = bottomInset
            textView.contentInset = contentInset

            var indicatorInsets = textView.verticalScrollIndicatorInsets
            indicatorInsets.bottom = bottomInset
            textView.verticalScrollIndicatorInsets = indicatorInsets

            textView.setContentOffset(contentOffset, animated: false)
        }
    }
}
