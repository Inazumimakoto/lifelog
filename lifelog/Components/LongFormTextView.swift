//
//  LongFormTextView.swift
//  lifelog
//
//  Created by Codex on 2026/05/20.
//

import Combine
import SwiftUI
import UIKit

@MainActor
final class LongFormTextDraft: ObservableObject {
    private(set) var text: String
    @Published private(set) var isEmpty: Bool
    @Published private(set) var version: Int = 0

    init(text: String) {
        self.text = text
        self.isEmpty = text.isEmpty
    }

    func updateFromEditor(_ newText: String) {
        text = newText
        updateEmptyState(for: newText)
    }

    func replaceText(_ newText: String) {
        text = newText
        version &+= 1
        updateEmptyState(for: newText)
    }

    private func updateEmptyState(for text: String) {
        let newIsEmpty = text.isEmpty
        if isEmpty != newIsEmpty {
            isEmpty = newIsEmpty
        }
    }
}

struct LongFormTextView: UIViewRepresentable {
    let text: String
    let textVersion: Int
    let onTextChange: (String) -> Void

    var font: UIFont = .preferredFont(forTextStyle: .body)
    var keyboardDismissMode: UIScrollView.KeyboardDismissMode = .none
    var textContainerInset: UIEdgeInsets = .zero
    var adjustsForKeyboard: Bool = false

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = font
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.keyboardDismissMode = keyboardDismissMode
        textView.textContainerInset = textContainerInset
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.text = text
        textView.layoutManager.allowsNonContiguousLayout = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        context.coordinator.appliedTextVersion = textVersion
        context.coordinator.setKeyboardAvoidanceEnabled(adjustsForKeyboard, for: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onTextChange = onTextChange

        if textView.font?.isEqual(font) != true {
            textView.font = font
        }
        if textView.keyboardDismissMode != keyboardDismissMode {
            textView.keyboardDismissMode = keyboardDismissMode
        }
        if textView.textContainerInset != textContainerInset {
            textView.textContainerInset = textContainerInset
        }
        context.coordinator.setKeyboardAvoidanceEnabled(adjustsForKeyboard, for: textView)

        guard context.coordinator.appliedTextVersion != textVersion else { return }
        guard textView.markedTextRange == nil else { return }

        context.coordinator.appliedTextVersion = textVersion
        guard textView.text != text else { return }

        let selectedRange = textView.selectedRange
        let contentOffset = textView.contentOffset
        textView.text = text

        let length = (textView.text as NSString).length
        let location = min(selectedRange.location, length)
        let availableLength = max(0, length - location)
        textView.selectedRange = NSRange(location: location,
                                         length: min(selectedRange.length, availableLength))
        textView.setContentOffset(clampedContentOffset(contentOffset, in: textView), animated: false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: onTextChange)
    }

    private func clampedContentOffset(_ contentOffset: CGPoint, in textView: UITextView) -> CGPoint {
        let inset = textView.adjustedContentInset
        let minX = -inset.left
        let maxX = max(minX, textView.contentSize.width - textView.bounds.width + inset.right)
        let minY = -inset.top
        let maxY = max(minY, textView.contentSize.height - textView.bounds.height + inset.bottom)

        return CGPoint(x: min(max(contentOffset.x, minX), maxX),
                       y: min(max(contentOffset.y, minY), maxY))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onTextChange: (String) -> Void
        var appliedTextVersion: Int = 0
        private weak var textView: UITextView?
        private var keyboardObservers: [NSObjectProtocol] = []
        private var lastKeyboardFrame: CGRect?
        private var lastBottomInset: CGFloat = 0

        init(onTextChange: @escaping (String) -> Void) {
            self.onTextChange = onTextChange
        }

        deinit {
            stopKeyboardObserving(resetInsets: false)
        }

        func textViewDidChange(_ textView: UITextView) {
            onTextChange(textView.text)
        }

        func setKeyboardAvoidanceEnabled(_ enabled: Bool, for textView: UITextView) {
            let textViewDidChange = self.textView !== textView
            self.textView = textView

            guard enabled || keyboardObservers.isEmpty == false || lastBottomInset != 0 else { return }

            if enabled {
                if keyboardObservers.isEmpty {
                    startKeyboardObserving()
                } else if textViewDidChange {
                    updateKeyboardInset(animated: false, notification: nil)
                }
            } else {
                lastKeyboardFrame = nil
                stopKeyboardObserving(resetInsets: true)
            }
        }

        private func startKeyboardObserving() {
            guard keyboardObservers.isEmpty else { return }

            let center = NotificationCenter.default
            keyboardObservers = [
                center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification,
                                   object: nil,
                                   queue: .main) { [weak self] notification in
                    self?.updateKeyboardInset(animated: true, notification: notification)
                },
                center.addObserver(forName: UIResponder.keyboardWillHideNotification,
                                   object: nil,
                                   queue: .main) { [weak self] notification in
                    self?.lastKeyboardFrame = nil
                    self?.setKeyboardInset(0, animated: true, notification: notification)
                }
            ]
        }

        private func stopKeyboardObserving(resetInsets: Bool) {
            let center = NotificationCenter.default
            keyboardObservers.forEach { center.removeObserver($0) }
            keyboardObservers.removeAll()
            if resetInsets {
                setKeyboardInset(0, animated: false, notification: nil)
            }
        }

        private func updateKeyboardInset(animated: Bool, notification: Notification?) {
            let keyboardFrame: CGRect
            if let screenFrame = notification?.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardFrame = screenFrame
                lastKeyboardFrame = screenFrame
            } else if let lastKeyboardFrame {
                keyboardFrame = lastKeyboardFrame
            } else {
                return
            }

            guard let textView, let window = textView.window else { return }

            let windowFrame = window.convert(keyboardFrame, from: nil)
            let localFrame = textView.convert(windowFrame, from: window)
            let overlap = textView.bounds.intersection(localFrame).height
            setKeyboardInset(max(0, overlap + 12), animated: animated, notification: notification)
        }

        private func setKeyboardInset(_ bottomInset: CGFloat, animated: Bool, notification: Notification?) {
            guard let textView else { return }
            guard abs(lastBottomInset - bottomInset) > 0.5 else { return }

            lastBottomInset = bottomInset
            let contentOffset = textView.contentOffset

            let updates = {
                var contentInset = textView.contentInset
                contentInset.bottom = bottomInset
                textView.contentInset = contentInset

                var indicatorInsets = textView.verticalScrollIndicatorInsets
                indicatorInsets.bottom = bottomInset
                textView.verticalScrollIndicatorInsets = indicatorInsets

                textView.setContentOffset(contentOffset, animated: false)
            }

            guard animated else {
                updates()
                return
            }

            let duration = notification?.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
            let curve = notification?.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
            let options = UIView.AnimationOptions(rawValue: curve << 16)
            UIView.animate(withDuration: duration,
                           delay: 0,
                           options: [options, .beginFromCurrentState, .allowUserInteraction]) {
                updates()
            }
        }
    }
}
