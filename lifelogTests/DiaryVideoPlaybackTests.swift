import Foundation
import XCTest
@testable import lifelify

@MainActor
final class DiaryVideoPlaybackTests: XCTestCase {
    func testInactivePage_doesNotRequestOriginalOrCreatePlayer() async {
        let playback = DiaryVideoPlayback(loadThumbnail: { _ in nil }, loadVideoURL: { _ in
            XCTFail("Adjacent pages must not download a video original")
            return URL(fileURLWithPath: "/unused.mov")
        }, releaseVideoURL: { _ in
            XCTFail("An inactive page must not own a video file")
        })

        await playback.prepare(path: "video.mov", isActive: false, allowsPlayback: true)

        XCTAssertNil(playback.player)
        XCTAssertFalse(playback.isLoading)
        XCTAssertFalse(playback.failed)
    }

    func testStop_releasesPlayerAndOwnedFileOnlyOnce() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        var releasedURLs: [URL] = []
        let playback = DiaryVideoPlayback(loadThumbnail: { _ in nil }, loadVideoURL: { _ in url },
                                          releaseVideoURL: { releasedURLs.append($0) })
        await playback.prepare(path: "video.mov", isActive: true, allowsPlayback: false)
        XCTAssertNotNil(playback.player)

        playback.stop()
        playback.stop()

        XCTAssertNil(playback.player)
        XCTAssertFalse(playback.isLoading)
        XCTAssertEqual(releasedURLs, [url])
    }

    func testCancelledPreparation_doesNotStopNewerPlayer() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        var releasedURLs: [URL] = []
        let playback = DiaryVideoPlayback(loadThumbnail: { _ in nil }, loadVideoURL: { _ in url },
                                          releaseVideoURL: { releasedURLs.append($0) })
        await playback.prepare(path: "current.mov", isActive: true, allowsPlayback: false)
        let currentPlayer = playback.player
        let superseded = _Concurrency.Task {
            await playback.prepare(path: "previous.mov", isActive: false, allowsPlayback: false)
        }
        superseded.cancel()
        await superseded.value

        XCTAssertTrue(playback.player === currentPlayer)
        XCTAssertTrue(releasedURLs.isEmpty)
        playback.stop()
    }

    func testDownloadCompletesAfterPageDismissal_releasesFileWithoutCreatingPlayer() async {
        let requested = expectation(description: "Video download requested")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        var download: CheckedContinuation<URL, Error>?
        var releasedURLs: [URL] = []
        let playback = DiaryVideoPlayback(loadThumbnail: { _ in nil }, loadVideoURL: { _ in
            try await withCheckedThrowingContinuation { continuation in
                download = continuation
                requested.fulfill()
            }
        }, releaseVideoURL: { releasedURLs.append($0) })
        let request = _Concurrency.Task {
            await playback.prepare(path: "video.mov", isActive: true, allowsPlayback: true)
        }
        await fulfillment(of: [requested], timeout: 1)

        playback.stop()
        download?.resume(returning: url)
        await request.value

        XCTAssertNil(playback.player)
        XCTAssertFalse(playback.isLoading)
        XCTAssertFalse(playback.failed)
        XCTAssertEqual(releasedURLs, [url])
    }

    func testUnavailableOriginal_exposesRetryState() async {
        enum FixtureError: Error { case unavailable }
        let playback = DiaryVideoPlayback(loadThumbnail: { _ in nil }, loadVideoURL: { _ in
            throw FixtureError.unavailable
        }, releaseVideoURL: { _ in })

        await playback.prepare(path: "video.mov", isActive: true, allowsPlayback: true)

        XCTAssertNil(playback.player)
        XCTAssertFalse(playback.isLoading)
        XCTAssertTrue(playback.failed)
    }
}
