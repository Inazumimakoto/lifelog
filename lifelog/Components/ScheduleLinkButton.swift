import SwiftUI

/// A separate native action so opening a link does not edit or complete its row.
struct ScheduleLinkButton: View {
    let url: URL

    var body: some View {
        Link(destination: url) {
            Label(url.host ?? url.absoluteString, systemImage: "link")
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("URLを開く"))
        .accessibilityValue(url.absoluteString)
    }
}
