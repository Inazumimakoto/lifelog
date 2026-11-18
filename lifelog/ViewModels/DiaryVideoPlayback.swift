import AVFoundation
import Combine
import UIKit

/// Playback keeps downloaded originals only for the currently visible media page.
@MainActor
final class DiaryVideoPlayback: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var preview: UIImage?
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false

    private let loadThumbnail: (String) async -> UIImage?
    private let loadVideoURL: (String) async throws -> URL
    private let releaseVideoURL: (URL) -> Void
    private var videoURL: URL?
    private var previewPath: String?
    private var loadGeneration = UUID()
    private var statusObservation: NSKeyValueObservation?
    private var allowsPlayback = false

    init(loadThumbnail: @escaping (String) async -> UIImage? = { await PhotoStorage.loadThumbnail(at: $0) },
         loadVideoURL: @escaping (String) async throws -> URL = { try await PhotoStorage.loadVideoURL(at: $0) },
         releaseVideoURL: @escaping (URL) -> Void = { PhotoStorage.releaseVideoURL($0) }) {
        self.loadThumbnail = loadThumbnail
        self.loadVideoURL = loadVideoURL
        self.releaseVideoURL = releaseVideoURL
    }

    func prepare(path: String, isActive: Bool, allowsPlayback: Bool) async {
        // A superseded SwiftUI task may start after the new page's task. It
        // must not stop the current player or invalidate the newer download.
        guard !_Concurrency.Task.isCancelled else { return }
        stop()
        let generation = loadGeneration
        self.allowsPlayback = allowsPlayback && isActive
        if previewPath != path {
            previewPath = path
            preview = nil
        }
        isLoading = isActive

        if preview == nil {
            let thumbnail = await loadThumbnail(path)
            guard isCurrent(generation) else { return }
            preview = thumbnail
        }
        guard isActive, isCurrent(generation) else { return }

        do {
            let url = try await loadVideoURL(path)
            guard isCurrent(generation) else {
                releaseVideoURL(url)
                return
            }
            videoURL = url
            let item = AVPlayerItem(url: url)
            player = AVPlayer(playerItem: item)
            statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                let status = item.status
                _Concurrency.Task { @MainActor [weak self] in
                    guard let self, self.isCurrent(generation) else { return }
                    switch status {
                    case .readyToPlay:
                        self.isLoading = false
                        if self.allowsPlayback { self.player?.play() }
                    case .failed:
                        self.isLoading = false
                        self.failed = true
                        self.pause()
                    default:
                        break
                    }
                }
            }
        } catch {
            guard isCurrent(generation) else { return }
            isLoading = false
            failed = true
        }
    }

    func pause() {
        allowsPlayback = false
        player?.pause()
    }

    func stop() {
        loadGeneration = UUID()
        pause()
        statusObservation?.invalidate()
        statusObservation = nil
        player?.replaceCurrentItem(with: nil)
        player = nil
        if let videoURL {
            releaseVideoURL(videoURL)
            self.videoURL = nil
        }
        isLoading = false
        failed = false
    }

    private func isCurrent(_ generation: UUID) -> Bool {
        !_Concurrency.Task.isCancelled && generation == loadGeneration
    }
}
