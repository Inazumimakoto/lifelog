import AVKit
import SwiftUI

/// Only the selected diary/place page owns a player and an on-demand original.
/// See docs/requirements.md §4.4 and §4.12.
struct DiaryVideoPage: View {
    let path: String
    let isActive: Bool
    @Binding var chromeVisible: Bool

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var playback = DiaryVideoPlayback()
    @State private var retryAttempt = 0

    var body: some View {
        ZStack {
            Color.black
            if let player = playback.player {
                VideoPlayer(player: player)
                    .padding(.top, 64)
                    .padding(.bottom, 40)
            } else if let preview = playback.preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
            }
        }
        .overlay(alignment: .bottom) {
            if isActive && (playback.isLoading || playback.failed) {
                VStack(spacing: 12) {
                    if playback.isLoading {
                        ProgressView().tint(.white)
                        Text("diaryMedia.video.loading")
                    } else {
                        Text("diaryMedia.video.unavailable")
                        Button("diaryMedia.video.retry") { retryAttempt += 1 }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding()
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 24)
                .padding(.bottom, 90)
            }
        }
        .task(id: "\(path):\(isActive):\(retryAttempt)") {
            if isActive { chromeVisible = true }
            await playback.prepare(path: path, isActive: isActive,
                                   allowsPlayback: scenePhase == .active)
        }
        .onChange(of: isActive) { _, active in
            if !active { playback.stop() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { playback.pause() }
        }
        .onDisappear { playback.stop() }
    }
}
