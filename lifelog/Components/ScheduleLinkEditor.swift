import SwiftUI

/// Optional website link shared by event and task editors (§4.2 / §4.3).
/// Only the text input is disabled for imported calendar events; their links still open.
struct ScheduleLinkEditor: View {
    @Binding var urlString: String
    var isReadOnly = false

    var body: some View {
        TextField("URL（任意）", text: $urlString)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .disabled(isReadOnly)

        if !ScheduleLink.isValid(urlString) {
            Text("有効なWebページのURLを入力してください。")
                .font(.footnote)
                .foregroundStyle(.red)
        }

        if let url = ScheduleLink.url(from: urlString) {
            Link("URLを開く", destination: url)
        }
    }
}
