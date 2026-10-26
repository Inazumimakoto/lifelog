import XCTest
import EventKit
@testable import lifelify

@MainActor
final class ExternalCalendarEventIdentityTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    func testRepeatedImport_preservesIdentity() {
        let first = ExternalCalendarEventIdentity.id(calendarIdentifier: "work", eventIdentifier: "meeting", occurrenceDate: date)
        let next = ExternalCalendarEventIdentity.id(calendarIdentifier: "work", eventIdentifier: "meeting", occurrenceDate: date)

        XCTAssertEqual(first, next)
    }

    func testRecurringOccurrences_keepDistinctIdentities() {
        let first = ExternalCalendarEventIdentity.id(calendarIdentifier: "work", eventIdentifier: "meeting", occurrenceDate: date)
        let next = ExternalCalendarEventIdentity.id(calendarIdentifier: "work", eventIdentifier: "meeting", occurrenceDate: date.addingTimeInterval(86_400))

        XCTAssertNotEqual(first, next)
    }

    func testNonRecurringEvent_usesSourceIdentityWithoutAnOccurrenceDate() {
        let first = ExternalCalendarEventIdentity.id(calendarIdentifier: "work", eventIdentifier: "meeting", occurrenceDate: nil)
        let same = ExternalCalendarEventIdentity.id(calendarIdentifier: "work", eventIdentifier: "meeting", occurrenceDate: nil)
        let recurring = ExternalCalendarEventIdentity.id(calendarIdentifier: "work", eventIdentifier: "meeting", occurrenceDate: date)

        XCTAssertEqual(first, same)
        XCTAssertNotEqual(first, recurring)
    }

    func testSameEventInDifferentCalendars_keepsDistinctIdentities() {
        let work = ExternalCalendarEventIdentity.id(calendarIdentifier: "work", eventIdentifier: "meeting", occurrenceDate: date)
        let personal = ExternalCalendarEventIdentity.id(calendarIdentifier: "personal", eventIdentifier: "meeting", occurrenceDate: date)

        XCTAssertNotEqual(work, personal)
    }

    func testIdentifiersWithSeparators_cannotAliasDifferentFields() {
        let first = ExternalCalendarEventIdentity.id(calendarIdentifier: "a|b", eventIdentifier: "c", occurrenceDate: date)
        let second = ExternalCalendarEventIdentity.id(calendarIdentifier: "a", eventIdentifier: "b|c", occurrenceDate: date)

        XCTAssertNotEqual(first, second)
    }

    func testMappingTheSameEventTwice_keepsIdentityAndIncludesEdits() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        let calendar = EKCalendar(for: .event, eventStore: store)
        event.calendar = calendar
        event.title = "Meeting"
        event.startDate = date
        event.endDate = date.addingTimeInterval(3_600)
        let first = CalendarEvent(event: event, categoryName: "Work")

        event.title = "Updated meeting"
        let updated = CalendarEvent(event: event, categoryName: "Work")

        XCTAssertEqual(first.id, updated.id)
        XCTAssertEqual(updated.title, "Updated meeting")
    }
}
