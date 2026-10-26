import Combine
import XCTest
@testable import lifelify

@MainActor
final class JournalViewModelTests: XCTestCase {
    func testHabitMetadataChange_invalidatesCachedDetail() async {
        let store = PerformanceTestStore.make()
        let day = Calendar.current.startOfDay(for: Date())
        store.habits = [Habit(title: "Before", iconName: "star", colorHex: "#000000", schedule: .daily)]
        let viewModel = JournalViewModel(store: store, anchorDate: day)
        XCTAssertEqual(viewModel.calendarDetailSnapshot(for: day).habitStatuses.first?.habit.title, "Before")
        let updated = expectation(description: "Habit invalidates detail")
        let subscription = viewModel.$dataRevision.dropFirst().sink { _ in updated.fulfill() }

        store.habits[0].title = "After"
        await fulfillment(of: [updated], timeout: 2)

        XCTAssertEqual(viewModel.calendarDetailSnapshot(for: day).habitStatuses.first?.habit.title, "After")
        withExtendedLifetime(subscription) {}
    }

    func testHealthChange_invalidatesCachedDetailAndRetainsTimelineIdentity() async {
        let day = Calendar.current.startOfDay(for: Date())
        var health = HealthSummary(date: day)
        health.sleepStages = [SleepStage(start: day, end: day.addingTimeInterval(6 * 3_600), stage: .deep)]
        let store = PerformanceTestStore.make(health: [health])
        let viewModel = JournalViewModel(store: store, anchorDate: day)
        XCTAssertNil(viewModel.calendarDetailSnapshot(for: day).healthSummary?.weatherCondition)
        let originalTimeline = viewModel.timelineItems(for: day)
        XCTAssertEqual(originalTimeline.count, 1)
        let updated = expectation(description: "Health invalidates detail")
        let subscription = viewModel.$dataRevision.dropFirst().sink { _ in updated.fulfill() }

        store.updateWeather(for: day, condition: "Clear", high: 25, low: 15)
        await fulfillment(of: [updated], timeout: 2)

        XCTAssertEqual(viewModel.calendarDetailSnapshot(for: day).healthSummary?.weatherCondition, "Clear")
        XCTAssertEqual(viewModel.timelineItems(for: day), originalTimeline)
        withExtendedLifetime(subscription) {}
    }

    func testUnrelatedMemoChange_doesNotInvalidateCalendar() async {
        let store = PerformanceTestStore.make()
        let viewModel = JournalViewModel(store: store)
        _ = viewModel.calendarDetailSnapshot(for: Date())
        _ = viewModel.timelineItems(for: Date())
        var publications = 0
        let subscription = viewModel.objectWillChange.sink { publications += 1 }
        store.memoPad = MemoPad(text: "Memo edit")
        await nextMainQueueTurn()
        await nextMainQueueTurn()

        XCTAssertEqual(viewModel.dataRevision, 0)
        XCTAssertEqual(publications, 0)
        withExtendedLifetime(subscription) {}
    }

    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
