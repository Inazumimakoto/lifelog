import SwiftUI
import UIKit

/// Keeps the native input control alive for the entire addition session.
/// Return adds an item without resigning first responder or recreating the keyboard.
struct ShoppingItemNameField: UIViewRepresentable {
    @Binding var text: String
    let isEnabled: Bool
    let focusRequest: Int
    let onSubmit: () -> Void
    let onFocusConfirmed: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> ShoppingNameTextField {
        let field = ShoppingNameTextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)),
                        for: .editingChanged)
        field.borderStyle = .none
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = .label
        field.placeholder = String(localized: "商品名")
        field.accessibilityLabel = String(localized: "商品名")
        field.accessibilityIdentifier = "shopping.titleDraft"
        field.returnKeyType = .default
        field.enablesReturnKeyAutomatically = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: ShoppingNameTextField, context: Context) {
        context.coordinator.parent = self
        field.isEnabled = isEnabled
        // Do not replace Japanese/Korean/Chinese composition while the user is typing.
        // An explicitly cleared draft follows a successful save and starts the next item.
        if field.text != text, field.markedTextRange == nil || text.isEmpty {
            if text.isEmpty { field.unmarkText() }
            field.text = text
        }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            field.requestFocus { [weak coordinator = context.coordinator] in
                coordinator?.parent.onFocusConfirmed()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ShoppingNameTextField,
                     context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return CGSize(width: width, height: uiView.intrinsicContentSize.height)
    }

    static func dismantleUIView(_ field: ShoppingNameTextField, coordinator: Coordinator) {
        field.stopRequestingFocus()
        field.delegate = nil
        if field.isFirstResponder { field.resignFirstResponder() }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ShoppingItemNameField
        var lastFocusRequest: Int?

        init(_ parent: ShoppingItemNameField) {
            self.parent = parent
        }

        // Avoid implicit isolated deinit on older Swift runtimes (swiftlang/swift#87316).
        nonisolated deinit {}

        @objc func textChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            guard field.markedTextRange == nil else { return false }
            parent.text = field.text ?? ""
            parent.onSubmit()
            // Update the same control immediately, with no blur/refocus cycle.
            field.text = parent.text
            return false
        }
    }
}

final class ShoppingNameTextField: UITextField {
    private var wantsFocus = false
    private var isFocusScheduled = false
    private var focusCompletion: (() -> Void)?

    nonisolated deinit {}

    func requestFocus(onConfirmed: @escaping () -> Void) {
        wantsFocus = true
        focusCompletion = onConfirmed
        scheduleFocusIfNeeded()
    }

    func stopRequestingFocus() {
        wantsFocus = false
        focusCompletion = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        scheduleFocusIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scheduleFocusIfNeeded()
    }

    private func scheduleFocusIfNeeded() {
        guard wantsFocus, window != nil, isEnabled, !isFocusScheduled else { return }
        isFocusScheduled = true
        // Focus after the sheet's control has entered the window and finished layout.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isFocusScheduled = false
            guard self.wantsFocus, self.window != nil, self.isEnabled else { return }
            if self.isFirstResponder || self.becomeFirstResponder() {
                self.wantsFocus = false
                let completion = self.focusCompletion
                self.focusCompletion = nil
                completion?()
            }
        }
    }
}
