import SwiftUI

/// The same video affordance is used on diary, place, and review previews.
struct DiaryVideoBadge: View {
    var body: some View {
        Image(systemName: "play.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(6)
            .background(.black.opacity(0.65), in: Circle())
            .accessibilityLabel(Text("diaryMedia.video"))
    }
}
