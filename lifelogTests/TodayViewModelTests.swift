import Combine
import XCTest
@testable import lifelify

@MainActor
final class TodayViewModelTests: XCTestCase {
    func testMemoEdits_updateMemoOnceWithoutRepublishingOtherSections() async {
        let store = PerformanceTestStore.make()
        let day = Calendar.current.startOfDay(for: Date())
        store.tasks = [Task(title: "Task", endDate: day)]
        let viewModel = TodayViewModel(store: store, date: day)
        var cancellables = Set<AnyCancellable>()
        var timelinePublications = 0
        var taskPublications = 0
        var habitPublications = 0
        var memoPublications = 0
        viewModel.$timelineItems.dropFirst().sink { _ in timelinePublications += 1 }.store(in: &cancellables)
        viewModel.$tasksDueToday.dropFirst().sink { _ in taskPublications += 1 }.store(in: &cancellables)
        viewModel.$habitStatuses.dropFirst().sink { _ in habitPublications += 1 }.store(in: &cancellables)
        let updated = expectation(description: "Latest memo snapshot published")
        viewModel.$memoPad.dropFirst().sink { memo in
            memoPublications += 1
            if memo.text == "Latest" { updated.fulfill() }
        }.store(in: &cancellables)

        store.memoPad = MemoPad(text: "L")
        store.memoPad = MemoPad(text: "La")
        store.memoPad = MemoPad(text: "Latest")
        await fulfillment(of: [updated], timeout: 2)

        XCTAssertEqual(viewModel.memoPad.text, "Latest")
        XCTAssertEqual(memoPublications, 1)
        XCTAssertEqual(timelinePublications, 0)
        XCTAssertEqual(taskPublications, 0)
        XCTAssertEqual(habitPublications, 0)
        XCTAssertEqual(viewModel.timelineItems.map(\.sourceId), store.tasks.map { Optional($0.id) })
        withExtendedLifetime(cancellables) {}
    }

    func testTaskAndEventBurst_publishesOneFinalTimeline() async {
        let store = PerformanceTestStore.make()
        let day = Calendar.current.startOfDay(for: Date())
        let viewModel = TodayViewModel(store: store, date: day)
        var timelines: [[JournalViewModel.TimelineItem]] = []
        let updated = expectation(description: "Combined inputs applied")
        let subscription = viewModel.$timelineItems.dropFirst().sink {
            timelines.append($0)
            if $0.count == 2 { updated.fulfill() }
        }
        store.tasks = [Task(title: "Task", endDate: day.addingTimeInterval(12 * 3_600))]
        store.calendarEvents = [CalendarEvent(title: "Event", startDate: day.addingTimeInterval(9 * 3_600),
                                             endDate: day.addingTimeInterval(10 * 3_600), calendarName: "Work")]
        await fulfillment(of: [updated], timeout: 2)
        XCTAssertEqual(timelines.count, 1)
        XCTAssertEqual(Set(viewModel.timelineItems.map(\.title)), Set(["Task", "Event"]))
        withExtendedLifetime(subscription) {}
    }
}
