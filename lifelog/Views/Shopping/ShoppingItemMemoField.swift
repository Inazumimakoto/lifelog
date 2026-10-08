import SwiftUI
import UIKit

/// Shares UIKit's responder chain with the product name field.
/// Closing the memo after transferring focus does not clear SwiftUI scene focus.
struct ShoppingItemMemoField: UIViewRepresentable {
    @Binding var text: String
    let isEnabled: Bool
    let focusRequest: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> ShoppingMemoTextView {
        let view = ShoppingMemoTextView(frame: .zero, textContainer: nil)
        view.delegate = context.coordinator
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .label
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.contentInset = .zero
        view.contentInsetAdjustmentBehavior = .never
        view.isScrollEnabled = true
        view.alwaysBounceVertical = false
        view.bounces = false
        view.allowsEditingTextAttributes = false
        view.returnKeyType = .default
        view.placeholder = String(localized: "メモ（任意）")
        view.accessibilityLabel = String(localized: "メモ（任意）")
        view.accessibilityIdentifier = "shopping.noteDraft"
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: ShoppingMemoTextView, context: Context) {
        context.coordinator.parent = self
        view.isEditable = isEnabled
        view.isSelectable = isEnabled
        // Preserve in-progress Japanese, Korean, and Chinese composition.
        // Only a cleared draft from a successful save explicitly clears composition.
        if view.text != text, view.markedTextRange == nil || text.isEmpty {
            context.coordinator.isUpdatingText = true
            if text.isEmpty { view.unmarkText() }
            view.text = text
            view.refreshTextLayout()
            if text.isEmpty { view.setContentOffset(.zero, animated: false) }
            context.coordinator.isUpdatingText = false
        }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            if focusRequest != 0 { view.requestFocus() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ShoppingMemoTextView,
                     context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let lineHeight = (uiView.font ?? UIFont.preferredFont(forTextStyle: .body)).lineHeight
        let fittingHeight = uiView.sizeThatFits(CGSize(width: width,
                                                      height: .greatestFiniteMagnitude)).height
        let height = min(max(ceil(fittingHeight), ceil(lineHeight)), ceil(lineHeight * 3))
        return CGSize(width: width, height: height)
    }

    static func dismantleUIView(_ view: ShoppingMemoTextView, coordinator: Coordinator) {
        view.stopRequestingFocus()
        view.delegate = nil
        // The product name may already own focus; never resign that other control.
        if view.isFirstResponder { view.resignFirstResponder() }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ShoppingItemMemoField
        var lastFocusRequest = 0
        var isUpdatingText = false

        init(_ parent: ShoppingItemMemoField) {
            self.parent = parent
        }

        // Avoid implicit isolated deinit on older Swift runtimes (swiftlang/swift#87316).
        nonisolated deinit {}

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdatingText else { return }
            parent.text = textView.text ?? ""
            (textView as? ShoppingMemoTextView)?.refreshTextLayout()
        }
    }
}

final class ShoppingMemoTextView: UITextView {
    private let placeholderLabel = UILabel()
    private var wantsFocus = false
    private var isFocusScheduled = false

    var placeholder: String = "" {
        didSet {
            placeholderLabel.text = placeholder
            refreshTextLayout()
        }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.isAccessibilityElement = false
        addSubview(placeholderLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    nonisolated deinit {}

    func refreshTextLayout() {
        placeholderLabel.isHidden = !text.isEmpty
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func requestFocus() {
        wantsFocus = true
        scheduleFocusIfNeeded()
    }

    func stopRequestingFocus() {
        wantsFocus = false
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        scheduleFocusIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        placeholderLabel.font = font
        placeholderLabel.textAlignment = textAlignment
        placeholderLabel.frame = CGRect(x: 0, y: 0, width: bounds.width,
                                        height: ceil(font?.lineHeight ?? 0))
        scheduleFocusIfNeeded()
    }

    private func scheduleFocusIfNeeded() {
        guard wantsFocus, window != nil, isEditable, !isFocusScheduled else { return }
        isFocusScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isFocusScheduled = false
            guard self.wantsFocus, self.window != nil, self.isEditable else { return }
            if self.isFirstResponder || self.becomeFirstResponder() {
                self.wantsFocus = false
            }
        }
    }
}
