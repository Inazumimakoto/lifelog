//
//  StableTextEditor.swift
//  lifelog
//
//  Created by Codex on 2026/05/13.
//

import SwiftUI
import UIKit

struct StableTextEditor: UIViewRepresentable {
    @Binding var text: String

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
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        context.coordinator.setKeyboardAvoidanceEnabled(adjustsForKeyboard, for: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        textView.font = font
        textView.keyboardDismissMode = keyboardDismissMode
        textView.textContainerInset = textContainerInset
        context.coordinator.setKeyboardAvoidanceEnabled(adjustsForKeyboard, for: textView)

        guard textView.text != text else { return }

        // Avoid replacing the backing text while an IME marked range is active.
        // Resetting UITextView.text during composition commits/cancels Japanese input.
        guard textView.markedTextRange == nil else { return }

        let selectedRange = textView.selectedRange
        textView.text = text

        let length = (textView.text as NSString).length
        let location = min(selectedRange.location, length)
        let availableLength = max(0, length - location)
        textView.selectedRange = NSRange(location: location,
                                         length: min(selectedRange.length, availableLength))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: StableTextEditor
        private weak var textView: UITextView?
        private var keyboardObservers: [NSObjectProtocol] = []

        init(parent: StableTextEditor) {
            self.parent = parent
        }

        deinit {
            stopKeyboardObserving(resetInsets: false)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard parent.text != textView.text else { return }
            parent.text = textView.text
        }

        func setKeyboardAvoidanceEnabled(_ enabled: Bool, for textView: UITextView) {
            self.textView = textView
            if enabled {
                startKeyboardObserving()
            } else {
                stopKeyboardObserving(resetInsets: true)
            }
        }

        private func startKeyboardObserving() {
            guard keyboardObservers.isEmpty else {
                updateKeyboardInset(animated: false, notification: nil)
                return
            }

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
                    self?.setKeyboardInset(0, animated: true, notification: notification)
                }
            ]
            updateKeyboardInset(animated: false, notification: nil)
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
            guard let textView, let window = textView.window else {
                setKeyboardInset(0, animated: animated, notification: notification)
                return
            }
            guard let screenFrame = notification?.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                setKeyboardInset(0, animated: animated, notification: notification)
                return
            }

            let windowFrame = window.convert(screenFrame, from: nil)
            let localFrame = textView.convert(windowFrame, from: window)
            let overlap = textView.bounds.intersection(localFrame).height
            setKeyboardInset(max(0, overlap + 12), animated: animated, notification: notification)
        }

        private func setKeyboardInset(_ bottomInset: CGFloat, animated: Bool, notification: Notification?) {
            guard let textView else { return }

            let updates = {
                var contentInset = textView.contentInset
                contentInset.bottom = bottomInset
                textView.contentInset = contentInset

                var indicatorInsets = textView.verticalScrollIndicatorInsets
                indicatorInsets.bottom = bottomInset
                textView.verticalScrollIndicatorInsets = indicatorInsets
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
