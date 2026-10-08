import SwiftUI
import UIKit
import XCTest
@testable import lifelify

@MainActor
final class ShoppingComposerFocusTests: XCTestCase {
    func testRemovingMemoAfterReturningToProductName_keepsKeyboardFocusAndAllowsNextAddition() async throws {
        let initialTitleFocus = expectation(description: "Product name receives initial focus")
        let returnedTitleFocus = expectation(description: "Focus returns from memo to product name")
        let memoRemoved = expectation(description: "SwiftUI dismantles the memo branch")
        let state = ComposerState()
        state.onTitleFocusConfirmed = { initialTitleFocus.fulfill() }
        let controller = UIHostingController(rootView: HostedComposer(state: state) {
            memoRemoved.fulfill()
        })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            state.onTitleFocusConfirmed = {}
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        controller.view.layoutIfNeeded()
        await fulfillment(of: [initialTitleFocus], timeout: 3)
        let titleField = try XCTUnwrap(findView(in: controller.view,
                                              as: ShoppingNameTextField.self,
                                              identifier: "shopping.titleDraft"))
        XCTAssertTrue(titleField.isFirstResponder)

        let memoFocus = expectation(forNotification: UITextView.textDidBeginEditingNotification,
                                    object: nil) { notification in
            (notification.object as? UITextView)?.accessibilityIdentifier == "shopping.noteDraft"
        }
        state.memoFocusRequest += 1
        state.showsMemo = true
        controller.view.layoutIfNeeded()
        await fulfillment(of: [memoFocus], timeout: 3)
        let memoField = try XCTUnwrap(findView(in: controller.view,
                                             as: UITextView.self,
                                             identifier: "shopping.noteDraft"))
        XCTAssertTrue(memoField.isFirstResponder)
        XCTAssertFalse(titleField.isFirstResponder)

        // Follow the production sequence: focus the persistent title, then remove the memo.
        state.onTitleFocusConfirmed = {
            XCTAssertTrue(titleField.isFirstResponder)
            state.showsMemo = false
            returnedTitleFocus.fulfill()
        }
        state.titleFocusRequest += 1
        controller.view.layoutIfNeeded()
        await fulfillment(of: [returnedTitleFocus, memoRemoved], timeout: 3)
        controller.view.layoutIfNeeded()

        XCTAssertNil(memoField.window)
        XCTAssertNil(memoField.delegate)
        XCTAssertTrue(findView(in: controller.view, as: ShoppingNameTextField.self,
                               identifier: "shopping.titleDraft") === titleField)
        XCTAssertTrue(titleField.isFirstResponder)

        titleField.text = "次の商品"
        let shouldReturn = titleField.delegate?.textFieldShouldReturn?(titleField)
        XCTAssertEqual(shouldReturn, false)
        XCTAssertEqual(state.submissionCount, 1)
        XCTAssertEqual(state.title, "")
        XCTAssertEqual(titleField.text, "")
        XCTAssertTrue(titleField.isFirstResponder)
    }

    private func findView<T: UIView>(in view: UIView, as type: T.Type, identifier: String) -> T? {
        if let matching = view as? T, matching.accessibilityIdentifier == identifier { return matching }
        for child in view.subviews {
            if let matching = findView(in: child, as: type, identifier: identifier) { return matching }
        }
        return nil
    }

    private final class ComposerState: ObservableObject {
        @Published var title = ""
        @Published var note = ""
        @Published var showsMemo = false
        @Published var titleFocusRequest = 0
        @Published var memoFocusRequest = 0
        var submissionCount = 0
        var onTitleFocusConfirmed: () -> Void = {}

        nonisolated deinit {}
    }

    private struct HostedComposer: View {
        @ObservedObject var state: ComposerState
        let onMemoRemoved: () -> Void

        var body: some View {
            VStack {
                ShoppingItemNameField(text: $state.title, isEnabled: true,
                                      focusRequest: state.titleFocusRequest,
                                      onSubmit: {
                                          state.submissionCount += 1
                                          state.title = ""
                                      },
                                      onFocusConfirmed: { state.onTitleFocusConfirmed() })
                    .frame(height: 44)
                if state.showsMemo {
                    ShoppingItemMemoField(text: $state.note, isEnabled: true,
                                          focusRequest: state.memoFocusRequest)
                        .frame(height: 72)
                        .background(RemovalProbe(onRemoved: onMemoRemoved))
                }
            }
            .padding()
        }
    }

    /// A passive probe waits for the actual SwiftUI teardown, without sleeps or polling.
    private struct RemovalProbe: UIViewRepresentable {
        let onRemoved: () -> Void

        func makeCoordinator() -> Coordinator { Coordinator(onRemoved: onRemoved) }
        func makeUIView(context: Context) -> UIView { UIView() }
        func updateUIView(_ view: UIView, context: Context) {}

        static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
            // Other representables in the removed branch finish dismantling in this turn.
            DispatchQueue.main.async { coordinator.onRemoved() }
        }

        final class Coordinator {
            let onRemoved: () -> Void

            init(onRemoved: @escaping () -> Void) { self.onRemoved = onRemoved }
            nonisolated deinit {}
        }
    }
}
