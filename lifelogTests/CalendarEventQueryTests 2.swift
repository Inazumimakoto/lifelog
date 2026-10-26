import XCTest
@testable import lifelify

@MainActor
final class CalendarEventQueryTests: XCTestCase {
    func testQueryFromMainActor_executesOffMainThreadAndReturnsResults() async {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(3_600)
        let queryRan = expectation(description: "Off-main database query ran")
        let query = CalendarEventQuery { requestedStart, requestedEnd in
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertEqual(requestedStart, start)
            XCTAssertEqual(requestedEnd, end)
            queryRan.fulfill()
            return []
        }

        let events = await query.fetchEvents(from: start, to: end)
        await fulfillment(of: [queryRan], timeout: 2)

        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(Thread.isMainThread)
    }

    func testInvalidRange_doesNotRunDatabaseQuery() async {
        let query = CalendarEventQuery { _, _ in
            XCTFail("An invalid date range must not query EventKit")
            return []
        }
        let events = await query.fetchEvents(from: Date(timeIntervalSince1970: 2_000),
                                            to: Date(timeIntervalSince1970: 1_000))

        XCTAssertTrue(events.isEmpty)
    }

    func testConcurrentIdenticalRanges_shareQueryAndLaterRefreshQueriesAgain() async {
        let count = QueryCount()
        let queryStarted = expectation(description: "Database query started")
        let releaseQuery = DispatchSemaphore(value: 0)
        let query = CalendarEventQuery { _, _ in
            if count.increment() == 1 {
                queryStarted.fulfill()
                _ = releaseQuery.wait(timeout: .now() + 5)
            }
            return []
        }
        let coordinator = CalendarEventQueryCoordinator(query: query)
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(3_600)
        async let first = coordinator.fetchEvents(from: start, to: end)
        async let second = coordinator.fetchEvents(from: start, to: end)
        await fulfillment(of: [queryStarted], timeout: 2)
        releaseQuery.signal()
        _ = await (first, second)

        XCTAssertEqual(count.value, 1)
        _ = await coordinator.fetchEvents(from: start, to: end)
        XCTAssertEqual(count.value, 2)
    }

    func testDifferentRanges_doNotJoinTheSameQuery() async {
        let count = QueryCount()
        let coordinator = CalendarEventQueryCoordinator(query: CalendarEventQuery { _, _ in
            _ = count.increment()
            return []
        })
        let start = Date(timeIntervalSince1970: 1_000)
        async let day = coordinator.fetchEvents(from: start, to: start.addingTimeInterval(86_400))
        async let month = coordinator.fetchEvents(from: start, to: start.addingTimeInterval(31 * 86_400))
        _ = await (day, month)

        XCTAssertEqual(count.value, 2)
    }
}

private final class QueryCount: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        storage += 1
        return storage
    }
}
