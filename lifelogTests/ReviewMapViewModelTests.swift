import XCTest
@testable import lifelify

@MainActor
final class ReviewMapViewModelTests: XCTestCase {
    func testPeriodFilterAndEnvironmentChanges_reuseDiarySourceSnapshot() async throws {
        let store = PerformanceTestStore.make()
        store.diaryEntries = [entry()]
        store.locationVisitTagDefinitions = [LocationVisitTagDefinition(name: "Cafe", sortOrder: 0)]
        let viewModel = ReviewMapViewModel(store: store)
        viewModel.activate(period: .all, anchorDate: anchorDate)
        await viewModel.flush()
        XCTAssertEqual(viewModel.sourceSnapshotBuildCount, 1)
        XCTAssertEqual(viewModel.displayState?.snapshot.places.count, 1)

        viewModel.setPeriod(.month, anchorDate: anchorDate)
        await viewModel.flush()
        let monthRevision = try XCTUnwrap(viewModel.displayState).revision
        viewModel.setPeriod(.all, anchorDate: anchorDate)
        await viewModel.flush()
        XCTAssertGreaterThan(try XCTUnwrap(viewModel.displayState).revision, monthRevision)
        viewModel.setPeriod(.month, anchorDate: anchorDate)
        await viewModel.flush()
        viewModel.setFilters(["Cafe"])
        await viewModel.flush()
        viewModel.refreshEnvironment()
        await viewModel.flush()
        viewModel.setPeriod(.all, anchorDate: anchorDate)
        await viewModel.flush()

        XCTAssertEqual(viewModel.sourceSnapshotBuildCount, 1)
        let state = try XCTUnwrap(viewModel.displayState)
        XCTAssertEqual(state.snapshot.query, ReviewMapQuery(selectedFilters: ["Cafe"]))
        XCTAssertEqual(state.renderedPlaces.count, 1)
    }

    func testDiaryPublication_rebuildsSourceAndPreservesLocationDetails() async throws {
        let store = PerformanceTestStore.make()
        store.diaryEntries = [entry()]
        let viewModel = ReviewMapViewModel(store: store)
        viewModel.activate(period: .all, anchorDate: anchorDate)
        await viewModel.flush()
        let previousRevision = try XCTUnwrap(viewModel.displayState).revision
        var changed = store.diaryEntries[0]
        changed.locations[0].name = "Updated place"
        changed.locations[0].latitude = 34.69
        changed.locations[0].longitude = 135.50
        changed.locations[0].photoPaths = ["saved-photo.jpg"]
        changed.locations[0].visitTags = ["Work"]
        store.diaryEntries = [changed]
        await viewModel.flush()

        let state = try XCTUnwrap(viewModel.displayState)
        let place = try XCTUnwrap(state.snapshot.places.first)
        XCTAssertEqual(viewModel.sourceSnapshotBuildCount, 2)
        XCTAssertGreaterThan(state.revision, previousRevision)
        XCTAssertEqual(place.location.name, "Updated place")
        XCTAssertEqual(place.location.latitude, 34.69)
        XCTAssertEqual(place.location.longitude, 135.50)
        XCTAssertEqual(place.visits.first?.photoPaths, ["saved-photo.jpg"])
        XCTAssertEqual(place.visits.first?.tags, ["Work"])
        XCTAssertEqual(state.renderedPlaces.first?.detailGroup().location.id, changed.locations[0].id)
    }

    func testRapidDiaryAndQueryChanges_publishLatestGenerationOnce() async throws {
        let store = PerformanceTestStore.make()
        store.diaryEntries = [entry()]
        let viewModel = ReviewMapViewModel(store: store)
        viewModel.activate(period: .all, anchorDate: anchorDate)
        await viewModel.flush()

        store.diaryEntries[0].locations[0].name = "First edit"
        viewModel.setFilters(["Work"])
        store.diaryEntries[0].locations[0].name = "Latest edit"
        store.diaryEntries[0].locations[0].visitTags = ["Work"]
        viewModel.setPeriod(.month, anchorDate: anchorDate)
        await viewModel.flush()

        let state = try XCTUnwrap(viewModel.displayState)
        XCTAssertEqual(viewModel.sourceSnapshotBuildCount, 2)
        XCTAssertEqual(state.snapshot.places.first?.location.name, "Latest edit")
        XCTAssertEqual(state.snapshot.query.selectedFilters, ["Work"])
        XCTAssertNotNil(state.snapshot.query.monthStart)
    }

    private var anchorDate: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
    }

    private func entry() -> DiaryEntry {
        DiaryEntry(date: anchorDate, text: "Saved diary", locations: [
            DiaryLocation(name: "Saved place", address: "Saved address",
                          latitude: 35.68, longitude: 139.76,
                          mapItemURL: "https://maps.apple.com/?q=Saved%20place",
                          visitTags: ["Cafe"])
        ])
    }
}
