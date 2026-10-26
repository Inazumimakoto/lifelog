import Foundation
import XCTest
@testable import lifelify

@MainActor
final class DiaryPhotoImporterTests: XCTestCase {
    private enum FixtureError: Error { case load, save }

    func testDiaryLimit_doesNotLoadOrSaveItemsBeyondCapacity() async {
        var loadedIdentifiers: [String] = []
        var savedIdentifiers: [String] = []
        let items = (0..<4).map { index in
            let identifier = "asset-\(index)"
            return DiaryPhotoImporter.Item(assetIdentifier: identifier) {
                loadedIdentifiers.append(identifier)
                return Data(identifier.utf8)
            }
        }

        let summary = await DiaryPhotoImporter.importPhotos(from: items, maximumCount: 2, save: { _, identifier in
            savedIdentifiers.append(identifier!)
            return identifier! + ".jpg"
        })

        XCTAssertEqual(loadedIdentifiers, ["asset-0", "asset-1"])
        XCTAssertEqual(savedIdentifiers, loadedIdentifiers)
        XCTAssertEqual(summary.addedPaths, ["asset-0.jpg", "asset-1.jpg"])
        XCTAssertEqual(summary.skippedCount, 2)
    }

    func testFailures_distinguishMissingDataLoadErrorAndSaveError() async {
        let items = [
            DiaryPhotoImporter.Item(assetIdentifier: "missing") { nil },
            DiaryPhotoImporter.Item(assetIdentifier: "load-error") { throw FixtureError.load },
            DiaryPhotoImporter.Item(assetIdentifier: "save-error") { Data([1]) },
            DiaryPhotoImporter.Item(assetIdentifier: "saved") { Data([2]) }
        ]
        var attemptedSaves: [String] = []

        let summary = await DiaryPhotoImporter.importPhotos(from: items, save: { _, identifier in
            attemptedSaves.append(identifier!)
            if identifier == "save-error" { throw FixtureError.save }
            return "saved.jpg"
        })

        XCTAssertEqual(attemptedSaves, ["save-error", "saved"])
        XCTAssertEqual(summary.addedPaths, ["saved.jpg"])
        XCTAssertEqual(summary.failedLoadCount, 2)
        XCTAssertEqual(summary.failedSaveCount, 1)
        XCTAssertEqual(summary.skippedCount, 0)
    }

    func testDiaryReuse_existingAndRepeatedMatchesAreSkippedWithoutSaving() async {
        let items = ["already-present.jpg", "reused.jpg", "reused.jpg"].map { path in
            DiaryPhotoImporter.Item(assetIdentifier: path) { Data([1]) }
        }

        let summary = await DiaryPhotoImporter.importPhotos(
            from: items,
            alreadyContains: { $0 == "already-present.jpg" },
            matchingPath: { identifier, _ in identifier },
            save: { _, _ in
                XCTFail("An existing location photo must be reused without writing another original")
                return "unexpected.jpg"
            }
        )

        XCTAssertEqual(summary.addedPaths, ["reused.jpg"])
        XCTAssertEqual(summary.skippedCount, 2)
        XCTAssertEqual(summary.failedLoadCount, 0)
        XCTAssertEqual(summary.failedSaveCount, 0)
    }

    func testLocationImport_hasNoDiaryLimitAndSavesRepeatedAssetsIndependently() async {
        let items = (0..<10).map { _ in
            DiaryPhotoImporter.Item(assetIdentifier: "same-asset") { Data([1]) }
        }
        var saveCount = 0

        let summary = await DiaryPhotoImporter.importPhotos(from: items, save: { _, identifier in
            XCTAssertEqual(identifier, "same-asset")
            saveCount += 1
            return "photo-\(saveCount).jpg"
        })

        XCTAssertEqual(saveCount, 10)
        XCTAssertEqual(summary.addedCount, 10)
        XCTAssertFalse(summary.hasIssues)
    }
}
