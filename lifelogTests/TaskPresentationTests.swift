import XCTest
@testable import lifelify

@MainActor
final class TaskPresentationTests: XCTestCase {
    func testOrdering_usesPriorityThenDateThenTitle() {
        let early = Date(timeIntervalSince1970: 1_000)
        let late = early.addingTimeInterval(86_400)
        let tasks = [
            Task(title: "Low early", startDate: early, priority: .low),
            Task(title: "B", startDate: early, priority: .medium),
            Task(title: "Medium late", startDate: late, priority: .medium),
            Task(title: "High late", startDate: late, priority: .high),
            Task(title: "A", startDate: early, priority: .medium)
        ]

        let sorted = tasks.sorted { TaskPresentation.orderedBefore($0, $1, preferring: .start) }

        XCTAssertEqual(sorted.map(\.title), ["High late", "A", "B", "Medium late", "Low early"])
    }

    func testBothDates_calendarPrefersStartAndTaskListPrefersDeadline() {
        let day = Date(timeIntervalSince1970: 1_000)
        let long = Task(title: "Long", startDate: day, endDate: day.addingTimeInterval(3 * 86_400))
        let short = Task(title: "Short", startDate: day.addingTimeInterval(86_400),
                         endDate: day.addingTimeInterval(2 * 86_400))

        XCTAssertTrue(TaskPresentation.orderedBefore(long, short, preferring: .start))
        XCTAssertTrue(TaskPresentation.orderedBefore(short, long, preferring: .deadline))
        XCTAssertEqual(TaskPresentation.displayDate(for: long, preferring: .start), long.startDate)
        XCTAssertEqual(TaskPresentation.displayDate(for: long, preferring: .deadline), long.endDate)
    }

    func testMissingPreferredDate_fallsBackAndSomedaySortsLast() {
        let day = Date(timeIntervalSince1970: 1_000)
        let startOnly = Task(title: "Start", startDate: day)
        let endOnly = Task(title: "End", endDate: day.addingTimeInterval(86_400))
        let someday = Task(title: "Someday")

        XCTAssertEqual(TaskPresentation.displayDate(for: startOnly, preferring: .deadline), day)
        XCTAssertEqual(TaskPresentation.displayDate(for: endOnly, preferring: .start), endOnly.endDate)
        XCTAssertNil(TaskPresentation.displayDate(for: someday, preferring: .start))
        for preference in [TaskPresentation.DatePreference.start, .deadline] {
            let sorted = [someday, endOnly, startOnly].sorted {
                TaskPresentation.orderedBefore($0, $1, preferring: preference)
            }
            XCTAssertEqual(sorted.map(\.title), ["Start", "End", "Someday"])
        }
    }

    func testPersistedWidgetTasks_useSameOrderingAndScheduledDaysAsDomainTasks() {
        let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let tasks = [
            Task(title: "Low", startDate: day, priority: .low),
            Task(title: "High", startDate: day, endDate: day.addingTimeInterval(86_400), priority: .high),
            Task(title: "Someday", priority: .medium)
        ]
        let stored = tasks.map(SDTask.init(domain:))
        for preference in [TaskPresentation.DatePreference.start, .deadline] {
            XCTAssertEqual(stored.sorted { TaskPresentation.orderedBefore($0, $1, preferring: preference) }.map(\.id),
                           tasks.sorted { TaskPresentation.orderedBefore($0, $1, preferring: preference) }.map(\.id))
        }
        for (domain, persisted) in zip(tasks, stored) {
            for date in [day, day.addingTimeInterval(86_400), day.addingTimeInterval(2 * 86_400)] {
                XCTAssertEqual(TaskPresentation.isScheduled(persisted, on: date),
                               TaskPresentation.isScheduled(domain, on: date))
            }
        }
    }

    func testScheduledDays_includeBothEndpointsAcrossDaylightSavingAndExcludeSomeday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        func date(_ day: Int, hour: Int = 12) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
        }
        let spanning = Task(title: "Trip", startDate: date(7, hour: 20), endDate: date(9, hour: 2))

        XCTAssertFalse(TaskPresentation.isScheduled(spanning, on: date(6), calendar: calendar))
        for day in 7...9 {
            XCTAssertTrue(TaskPresentation.isScheduled(spanning, on: date(day), calendar: calendar))
        }
        XCTAssertFalse(TaskPresentation.isScheduled(spanning, on: date(10), calendar: calendar))
        XCTAssertTrue(TaskPresentation.isScheduled(Task(title: "Deadline", endDate: date(8)),
                                                  on: date(8), calendar: calendar))
        XCTAssertTrue(TaskPresentation.isScheduled(Task(title: "Start", startDate: date(8)),
                                                  on: date(8), calendar: calendar))
        XCTAssertFalse(TaskPresentation.isScheduled(Task(title: "Someday"), on: date(8), calendar: calendar))
    }
}
