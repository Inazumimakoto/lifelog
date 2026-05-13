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
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        textView.font = font
        textView.keyboardDismissMode = keyboardDismissMode
        textView.textContainerInset = textContainerInset

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

        init(parent: StableTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard parent.text != textView.text else { return }
            parent.text = textView.text
        }
    }
}
