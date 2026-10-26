import Foundation
import SwiftData
import XCTest
@testable import lifelify

@MainActor
final class DateOnlyProjectionTests: XCTestCase {
    nonisolated deinit {}

    func testTaskAcrossDateLine_domainAndWidgetKeepInclusiveCivilDays() {
        let source = calendar("Pacific/Kiritimati"), display = calendar("America/Los_Angeles")
        let task = Task(title: "Travel", startDate: date(2026, 10, 14, in: source), endDate: date(2026, 10, 15, in: source),
                        dateOnlyTimeZoneIdentifier: source.timeZone.identifier)
        let row = SDTask(domain: task)

        XCTAssertEqual(TaskPresentation.displayDate(for: task, preferring: .start, calendar: display), date(2026, 10, 14, in: display))
        for day in 13...16 {
            let expected = (14...15).contains(day)
            XCTAssertEqual(TaskPresentation.isScheduled(task, on: date(2026, 10, day, in: display), calendar: display), expected)
            XCTAssertEqual(TaskPresentation.isScheduled(row, on: date(2026, 10, day, in: display), calendar: display), expected)
        }
        XCTAssertEqual(Task(sd: row), task)
    }

    func testTaskEditor_afterTravelTitleOnlySavePreservesSourceInstants() {
        let source = calendar("Pacific/Kiritimati"), display = calendar("America/Los_Angeles")
        let task = Task(title: "Original", startDate: date(2026, 10, 14, in: source), endDate: date(2026, 10, 15, in: source),
                        dateOnlyTimeZoneIdentifier: source.timeZone.identifier)
        let form = TaskEditorFormState(task: task, calendar: display)
        defer { form.clearCachedDraft() }
        XCTAssertEqual(form.startDate, date(2026, 10, 14, in: display))
        XCTAssertEqual(form.endDate, date(2026, 10, 15, in: display))
        form.title = "Updated title"
        let saved = form.makeTask()
        XCTAssertEqual(saved.startDate, task.startDate)
        XCTAssertEqual(saved.endDate, task.endDate)
        XCTAssertEqual(saved.dateOnlyTimeZoneIdentifier, source.timeZone.identifier)
        form.endDate = date(2026, 10, 16, in: display)
        XCTAssertEqual(form.makeTask().endDate, date(2026, 10, 16, in: source))
    }

    func testTaskEditor_startOnlyAndEndOnlyRemainSingleBoundAfterUnrelatedEdit() {
        let source = calendar("Pacific/Kiritimati"), display = calendar("America/Los_Angeles")
        for startOnly in [true, false] {
            let bound = date(2026, 10, 14, in: source)
            let task = Task(title: "One bound", startDate: startOnly ? bound : nil, endDate: startOnly ? nil : bound,
                            dateOnlyTimeZoneIdentifier: source.timeZone.identifier)
            let form = TaskEditorFormState(task: task, calendar: display)
            defer { form.clearCachedDraft() }
            form.detail = "Keep date bounds"
            XCTAssertEqual(form.makeTask().startDate, task.startDate)
            XCTAssertEqual(form.makeTask().endDate, task.endDate)
        }
    }

    func testTaskDateProjection_usesGregorianLabelsEvenWithBuddhistDisplayCalendar() {
        let source = calendar("Pacific/Kiritimati")
        var display = Calendar(identifier: .buddhist)
        display.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let task = Task(title: "Civil day", startDate: date(2026, 10, 14, in: source), dateOnlyTimeZoneIdentifier: source.timeZone.identifier)
        XCTAssertEqual(TaskPresentation.displayDate(for: task, preferring: .start, calendar: display), date(2026, 10, 14, in: calendar("America/Los_Angeles")))
    }

    func testAllDayNewYorkToLosAngeles_appearsOnExactlyItsSourceDay() {
        let source = calendar("America/New_York"), display = calendar("America/Los_Angeles")
        let event = allDay(start: date(2026, 11, 1, in: source), end: date(2026, 11, 2, in: source), zone: source.timeZone.identifier)
        XCTAssertEqual(event.displayStartDate(calendar: display), date(2026, 11, 1, in: display))
        XCTAssertEqual(event.displayEndDate(calendar: display), date(2026, 11, 2, in: display))
        XCTAssertEqual(event.endDate.timeIntervalSince(event.startDate), 25 * 3_600)
        for day in [31, 1, 2] {
            let start = day == 31 ? date(2026, 10, day, in: display) : date(2026, 11, day, in: display)
            let end = display.date(byAdding: .day, value: 1, to: start)!
            XCTAssertEqual(EventQuerying.overlapping([event], rangeStart: start, rangeEndExclusive: end, calendar: display).count, day == 1 ? 1 : 0)
        }
        XCTAssertFalse(CalendarPreviewLayout.isMultiDayEvent(event, calendar: display))
    }

    func testAllDaySpringDST_projectionPreservesOneDayWithDifferentDuration() {
        let source = calendar("America/New_York"), display = calendar("Asia/Tokyo")
        let event = allDay(start: date(2026, 3, 8, in: source), end: date(2026, 3, 9, in: source), zone: source.timeZone.identifier)
        XCTAssertEqual(event.endDate.timeIntervalSince(event.startDate), 23 * 3_600)
        XCTAssertEqual(event.displayEndDate(calendar: display).timeIntervalSince(event.displayStartDate(calendar: display)), 24 * 3_600)
        XCTAssertFalse(CalendarPreviewLayout.isMultiDayEvent(event, calendar: display))
        XCTAssertEqual(event.startDate, date(2026, 3, 8, in: source))
    }

    func testAllDayAcrossDateLine_weekSegmentsKeepCivilStartAndExclusiveEnd() {
        let source = calendar("Pacific/Kiritimati"), display = calendar("America/Los_Angeles")
        let event = allDay(start: date(2026, 10, 14, in: source), end: date(2026, 10, 16, in: source), zone: source.timeZone.identifier)
        let week = (12...18).map { date(2026, 10, $0, in: display) }
        let layout = CalendarPreviewLayout.week(dates: week, events: [event], itemLimit: 4, calendar: display)
        XCTAssertEqual(layout.segments.count, 1)
        XCTAssertEqual(layout.segments.first?.startColumn, 2)
        XCTAssertEqual(layout.segments.first?.endColumn, 3)
        XCTAssertTrue(CalendarPreviewLayout.isMultiDayEvent(event, calendar: display))
        let sourceWindow = EventQuerying.storageRange(rangeStart: date(2026, 10, 14, in: display), rangeEndExclusive: date(2026, 10, 16, in: display), calendar: display)
        XCTAssertLessThan(sourceWindow.start, event.startDate)
        XCTAssertGreaterThan(sourceWindow.end, event.endDate)
    }

    func testTimedEvent_projectionNeverMovesItsInstants() {
        let start = Date(timeIntervalSince1970: 1_792_000_000)
        let event = CalendarEvent(title: "Timed", startDate: start, endDate: start.addingTimeInterval(3_600), calendarName: "Work",
                                  dateOnlyTimeZoneIdentifier: "Pacific/Kiritimati")
        for zone in ["America/Los_Angeles", "Asia/Tokyo"] {
            XCTAssertEqual(event.displayStartDate(calendar: calendar(zone)), start)
            XCTAssertEqual(event.displayEndDate(calendar: calendar(zone)), event.endDate)
        }
    }

    func testLegacyRecords_nilSourceZoneKeepsExistingDateBehavior() throws {
        let start = Date(timeIntervalSince1970: 1_792_000_000), end = start.addingTimeInterval(86_400)
        let event = CalendarEvent(title: "Legacy", startDate: start, endDate: end, calendarName: "Work", isAllDay: true)
        let task = Task(title: "Legacy", startDate: start)
        let display = calendar("America/Los_Angeles")
        XCTAssertEqual(event.displayStartDate(calendar: display), start)
        XCTAssertEqual(TaskPresentation.displayDate(for: task, preferring: .start, calendar: display), start)
        var encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
        encoded.removeValue(forKey: "dateOnlyTimeZoneIdentifier")
        XCTAssertNil(try JSONDecoder().decode(CalendarEvent.self, from: JSONSerialization.data(withJSONObject: encoded)).dateOnlyTimeZoneIdentifier)
    }

    func testPersistenceAndCodable_keepSourceZoneAndOriginalInstants() throws {
        let source = calendar("America/New_York")
        let event = allDay(start: date(2026, 11, 1, in: source), end: date(2026, 11, 2, in: source), zone: source.timeZone.identifier)
        let task = Task(title: "Persisted", startDate: event.startDate, endDate: event.startDate, dateOnlyTimeZoneIdentifier: source.timeZone.identifier)
        let container = try ModelContainer(for: SDTask.self, SDCalendarEvent.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        container.mainContext.insert(SDTask(domain: task)); container.mainContext.insert(SDCalendarEvent(domain: event))
        try container.mainContext.save()
        let context = ModelContext(container)
        XCTAssertEqual(Task(sd: try XCTUnwrap(context.fetch(FetchDescriptor<SDTask>()).first)), task)
        XCTAssertEqual(CalendarEvent(sd: try XCTUnwrap(context.fetch(FetchDescriptor<SDCalendarEvent>()).first)), event)
        XCTAssertEqual(try JSONDecoder().decode(CalendarEvent.self, from: JSONEncoder().encode(event)), event)
        XCTAssertEqual(try JSONDecoder().decode(Task.self, from: JSONEncoder().encode(task)), task)
    }


    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) -> Date {
        calendar.startOfDay(for: calendar.date(from: DateComponents(year: year, month: month, day: day))!)
    }
    private func allDay(start: Date, end: Date, zone: String) -> CalendarEvent {
        CalendarEvent(title: "All day", startDate: start, endDate: end, calendarName: "Work", isAllDay: true, dateOnlyTimeZoneIdentifier: zone)
    }
}
