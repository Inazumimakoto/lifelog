import XCTest
@testable import lifelify

@MainActor
final class CalendarTimelineIdentityTests: XCTestCase {
    func testEditingEvent_preservesIdentityAndKeepsKindsDistinct() {
        let sourceID = UUID()
        let original = item(sourceID: sourceID, title: "Original", kind: .event)
        let edited = item(sourceID: sourceID, title: "Edited", kind: .event, offset: 3_600)
        let task = item(sourceID: sourceID, title: "Original", kind: .task)

        XCTAssertEqual(original.id, edited.id)
        XCTAssertNotEqual(original.id, task.id)
    }

    func testSleepAtTheSameTime_distinguishesSummariesAndRemainsStable() {
        let first = item(sourceID: nil, title: "Sleep", kind: .sleep, identitySource: "summary-a-0")
        let rebuilt = item(sourceID: nil, title: "Sleep", kind: .sleep, identitySource: "summary-a-0")
        let otherSummary = item(sourceID: nil, title: "Sleep", kind: .sleep, identitySource: "summary-b-0")

        XCTAssertEqual(first.id, rebuilt.id)
        XCTAssertNotEqual(first.id, otherSummary.id)
    }

    private func item(
        sourceID: UUID?,
        title: String,
        kind: JournalViewModel.TimelineItem.ItemKind,
        offset: TimeInterval = 0,
        identitySource: String? = nil
    ) -> JournalViewModel.TimelineItem {
        JournalViewModel.TimelineItem(
            sourceId: sourceID,
            title: title,
            start: Date(timeIntervalSince1970: 1_000 + offset),
            end: Date(timeIntervalSince1970: 2_000 + offset),
            kind: kind,
            detail: nil,
            eventDetail: nil,
            isAllDay: false,
            identitySource: identitySource
        )
    }
}
