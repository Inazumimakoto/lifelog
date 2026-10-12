import SwiftUI

/// Shared task/event memo field. Keep draft edits out of the enclosing form's
/// published state so typing retains LongFormTextView's narrow update path.
struct DetailMemoEditor: View {
    @ObservedObject var draft: LongFormTextDraft
    let onTextChange: (String) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("詳細メモ（任意）")
                .foregroundStyle(.tertiary)
                .opacity(draft.isEmpty ? 1 : 0)
                .allowsHitTesting(false)
            LongFormTextView(text: draft.text,
                             textVersion: draft.version,
                             onTextChange: { newValue in
                                 draft.updateFromEditor(newValue)
                                 onTextChange(newValue)
                             })
                .frame(minHeight: 56, alignment: .topLeading)
        }
    }
}
