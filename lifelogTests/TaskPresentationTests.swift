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

    func testOverdue_usesDeadlineDayAndExcludesCompletedOrUndatedTasks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2030, month: 3, day: 13))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let now = today.addingTimeInterval(23 * 3_600)
        let overdue = Task(title: "Expired", startDate: yesterday, endDate: today.addingTimeInterval(-1))
        let dueToday = Task(title: "Due today", endDate: today)
        let ongoing = Task(title: "Ongoing", startDate: yesterday, endDate: tomorrow)
        let startOnly = Task(title: "Start only", startDate: yesterday)
        let completed = Task(title: "Done", endDate: yesterday, isCompleted: true)

        XCTAssertTrue(TaskPresentation.isOverdue(overdue, on: now, calendar: calendar))
        XCTAssertTrue(TaskPresentation.isOverdue(startOnly, on: now, calendar: calendar))
        XCTAssertFalse(TaskPresentation.isOverdue(dueToday, on: now, calendar: calendar))
        XCTAssertFalse(TaskPresentation.isOverdue(ongoing, on: now, calendar: calendar))
        XCTAssertFalse(TaskPresentation.isOverdue(completed, on: now, calendar: calendar))
        XCTAssertFalse(TaskPresentation.isOverdue(Task(title: "Someday"), on: now, calendar: calendar))
    }

    func testPending_includesScheduledAndOverdueButExcludesFutureCompletedAndUndatedTasks() {
        let today = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let tasks = [
            Task(title: "Overdue", endDate: yesterday),
            Task(title: "Due today", endDate: today),
            Task(title: "Ongoing", startDate: yesterday, endDate: tomorrow),
            Task(title: "Future", startDate: tomorrow),
            Task(title: "Done today", endDate: today, isCompleted: true),
            Task(title: "Done overdue", endDate: yesterday, isCompleted: true),
            Task(title: "Someday")
        ]

        XCTAssertEqual(tasks.filter { TaskPresentation.isPending($0, on: today) }.map(\.title),
                       ["Overdue", "Due today", "Ongoing"])
    }

    func testTodayOrdering_groupsScheduledBeforeOverdueAndUsesEachGroupsPreferredDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2030, month: 3, day: 13))!
        func shifted(_ days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: today)! }
        let tasks = [
            Task(title: "Overdue high", endDate: shifted(-1), priority: .high),
            Task(title: "Today low", endDate: today, priority: .low),
            Task(title: "Today recent start", startDate: today, endDate: today),
            Task(title: "Today early start", startDate: shifted(-2), endDate: shifted(2)),
            Task(title: "Overdue newer deadline", startDate: shifted(-10), endDate: shifted(-1)),
            Task(title: "Overdue older deadline B", startDate: shifted(-3), endDate: shifted(-2)),
            Task(title: "Overdue older deadline A", startDate: shifted(-3), endDate: shifted(-2))
        ]

        let sorted = tasks.sorted { TaskPresentation.orderedForToday($0, $1, on: today, calendar: calendar) }

        XCTAssertEqual(sorted.map(\.title), ["Today early start", "Today recent start", "Today low",
                                            "Overdue high", "Overdue older deadline A", "Overdue older deadline B",
                                            "Overdue newer deadline"])
    }

    func testPersistedWidgetTasks_matchPendingOverdueAndTodayOrderingAfterTravel() {
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var displayCalendar = Calendar(identifier: .gregorian)
        displayCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let sourceDay = sourceCalendar.date(from: DateComponents(year: 2030, month: 3, day: 13))!
        let displayDay = displayCalendar.date(from: DateComponents(year: 2030, month: 3, day: 13))!
        let sourceYesterday = sourceCalendar.date(byAdding: .day, value: -1, to: sourceDay)!
        let sourceTomorrow = sourceCalendar.date(byAdding: .day, value: 1, to: sourceDay)!
        let tasks = [
            Task(title: "Due today", endDate: sourceDay, dateOnlyTimeZoneIdentifier: "Asia/Tokyo"),
            Task(title: "Expired", endDate: sourceYesterday, priority: .high, dateOnlyTimeZoneIdentifier: "Asia/Tokyo"),
            Task(title: "Start only", startDate: sourceYesterday, dateOnlyTimeZoneIdentifier: "Asia/Tokyo"),
            Task(title: "Future", startDate: sourceTomorrow, dateOnlyTimeZoneIdentifier: "Asia/Tokyo"),
            Task(title: "Done", endDate: sourceYesterday, isCompleted: true, dateOnlyTimeZoneIdentifier: "Asia/Tokyo"),
            Task(title: "Someday")
        ]
        let stored = tasks.map(SDTask.init(domain:))

        XCTAssertFalse(TaskPresentation.isOverdue(tasks[0], on: displayDay, calendar: displayCalendar))
        XCTAssertTrue(TaskPresentation.isPending(tasks[0], on: displayDay, calendar: displayCalendar))
        for (domain, persisted) in zip(tasks, stored) {
            XCTAssertEqual(TaskPresentation.isOverdue(persisted, on: displayDay, calendar: displayCalendar),
                           TaskPresentation.isOverdue(domain, on: displayDay, calendar: displayCalendar))
            XCTAssertEqual(TaskPresentation.isPending(persisted, on: displayDay, calendar: displayCalendar),
                           TaskPresentation.isPending(domain, on: displayDay, calendar: displayCalendar))
        }
        let pendingDomain = tasks.filter { TaskPresentation.isPending($0, on: displayDay, calendar: displayCalendar) }
            .sorted { TaskPresentation.orderedForToday($0, $1, on: displayDay, calendar: displayCalendar) }
        let pendingStored = stored.filter { TaskPresentation.isPending($0, on: displayDay, calendar: displayCalendar) }
            .sorted { TaskPresentation.orderedForToday($0, $1, on: displayDay, calendar: displayCalendar) }
        XCTAssertEqual(pendingStored.map(\.id), pendingDomain.map(\.id))
        XCTAssertEqual(pendingDomain.map(\.title), ["Due today", "Expired", "Start only"])
    }

    func testTodayOrdering_projectsDateOnlyValuesIntoTheSuppliedCalendar() {
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let sourceDay = sourceCalendar.date(from: DateComponents(year: 2030, month: 6, day: 13))!
        let dated = Task(title: "Civil day", endDate: sourceDay, dateOnlyTimeZoneIdentifier: "GMT")
        let legacy = Task(title: "Legacy instant", endDate: sourceDay.addingTimeInterval(6 * 3_600))
        let today = sourceCalendar.date(byAdding: .day, value: 2, to: sourceDay)!
        var eastCalendar = sourceCalendar
        eastCalendar.timeZone = TimeZone(secondsFromGMT: 12 * 3_600)!
        var westCalendar = sourceCalendar
        westCalendar.timeZone = TimeZone(secondsFromGMT: -12 * 3_600)!

        XCTAssertTrue(TaskPresentation.orderedForToday(dated, legacy, on: today, calendar: eastCalendar))
        XCTAssertTrue(TaskPresentation.orderedForToday(legacy, dated, on: today, calendar: westCalendar))
    }
}
