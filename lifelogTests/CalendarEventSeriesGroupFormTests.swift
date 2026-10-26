import Foundation
import SwiftData
import XCTest
@testable import lifelify

@MainActor
final class CalendarEventSeriesGroupFormTests: XCTestCase {
    func testOccurrenceFrequencyEdit_preservesLogicalGroupAndOccurrenceIdentity() throws {
        let groupID = UUID()
        let rule = groupedRule(groupID: groupID)
        let original = try occurrence(of: series(rule: rule), at: date(18))
        let form = CalendarEventEditorFormState(event: original)
        defer { form.clearCachedDraft() }

        form.selectRecurrenceFrequency(.daily)
        let edited = form.makeEvent()

        XCTAssertEqual(edited.recurrenceRule?.frequency, .daily)
        XCTAssertEqual(edited.recurrenceRule?.seriesGroupID, groupID)
        XCTAssertEqual(edited.recurrenceRule?.anchorDate, rule.anchorDate)
        XCTAssertEqual(edited.occurrenceReference, original.occurrenceReference)
        XCTAssertTrue(form.hasRecurrenceRuleChanges)
    }

    func testOccurrenceWeekdayEdit_preservesLogicalGroupAndInterval() throws {
        let groupID = UUID()
        let original = try occurrence(of: series(rule: groupedRule(groupID: groupID)), at: date(18))
        let form = CalendarEventEditorFormState(event: original)
        defer { form.clearCachedDraft() }

        form.recurrenceWeekdays = [3, 6]
        let rule = try XCTUnwrap(form.makeEvent().recurrenceRule)

        XCTAssertEqual(rule.weekdays, [3, 6])
        XCTAssertEqual(rule.interval, 2)
        XCTAssertEqual(rule.seriesGroupID, groupID)
        XCTAssertTrue(form.hasRecurrenceRuleChanges)
    }

    func testUnchangedGroupedRule_preservesExactMetadataWhileEditingContent() throws {
        let rule = groupedRule(groupID: UUID())
        let original = try occurrence(of: series(rule: rule), at: date(18))
        let form = CalendarEventEditorFormState(event: original)
        defer { form.clearCachedDraft() }
        form.title = "Changed title"
        form.detail = "Changed memo"
        form.urlString = "https://example.com/changed"

        XCTAssertEqual(form.makeEvent().recurrenceRule, rule)
        XCTAssertFalse(form.hasRecurrenceRuleChanges)
    }

    func testFutureSplitThenSeriesFrequencyEdit_keepsGroupingMetadataInTheEditorAndStore() throws {
        let initial = series(rule: .init(frequency: .weekly, weekdays: [2], timeZoneIdentifier: "UTC"))
        let store = try makeStore(series: initial)
        let original = try occurrence(of: initial, at: date(18))
        let splitForm = CalendarEventEditorFormState(event: original)
        defer { splitForm.clearCachedDraft() }
        splitForm.selectRecurrenceFrequency(.daily)

        let split = try store.prepareCalendarEventEdit(original: original, edited: splitForm.makeEvent(), scope: .future)
        try store.applyCalendarEventEdit(split)
        let futureMaster = try XCTUnwrap(store.calendarEvents.first { $0.id != initial.id })
        let futureOccurrence = try occurrence(of: futureMaster, at: date(19))
        let futureForm = CalendarEventEditorFormState(event: futureOccurrence)
        defer { futureForm.clearCachedDraft() }
        XCTAssertEqual(futureForm.recurrenceFrequency, .daily)
        XCTAssertEqual(futureForm.makeEvent().recurrenceRule, futureMaster.recurrenceRule)
        XCTAssertFalse(futureForm.hasRecurrenceRuleChanges)

        futureForm.selectRecurrenceFrequency(.biweekly)
        futureForm.recurrenceWeekdays = [3, 5]
        let edited = futureForm.makeEvent()
        XCTAssertEqual(edited.recurrenceRule?.seriesGroupID, initial.id)
        let wholeSegment = try store.prepareCalendarEventEdit(original: futureOccurrence, edited: edited, scope: .series)
        try store.applyCalendarEventEdit(wholeSegment)

        XCTAssertEqual(store.calendarEvents.count, 2)
        XCTAssertTrue(store.calendarEvents.allSatisfy { $0.recurrenceRule?.seriesGroupID == initial.id })
        let updated = try XCTUnwrap(store.calendarEvents.first { $0.id == futureMaster.id })
        XCTAssertEqual(updated.recurrenceRule?.frequency, .weekly)
        XCTAssertEqual(updated.recurrenceRule?.interval, 2)
        XCTAssertEqual(updated.recurrenceRule?.weekdays, [3, 5])
        let persisted = try ModelContext(store.modelContext.container)
            .fetch(FetchDescriptor<SDCalendarEvent>()).map { CalendarEvent(sd: $0) }
        XCTAssertEqual(Set(persisted), Set(store.calendarEvents))
    }

    func testGroupedRuleJSON_roundTripsAndLegacyMissingGroupRemainsOptional() throws {
        let rule = groupedRule(groupID: UUID())
        let data = try JSONEncoder().encode(rule)
        XCTAssertEqual(try JSONDecoder().decode(EventRecurrenceRule.self, from: data), rule)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "seriesGroupID")
        let decoded = try JSONDecoder().decode(EventRecurrenceRule.self, from: JSONSerialization.data(withJSONObject: legacy))
        var expected = rule
        expected.seriesGroupID = nil

        XCTAssertNil(decoded.seriesGroupID)
        XCTAssertEqual(decoded, expected)
    }

    private func groupedRule(groupID: UUID) -> EventRecurrenceRule {
        EventRecurrenceRule(frequency: .weekly, interval: 2, weekdays: [2], until: date(30),
                            timeZoneIdentifier: "UTC", anchorDate: date(4), seriesGroupID: groupID)
    }

    private func series(rule: EventRecurrenceRule) -> CalendarEvent {
        CalendarEvent(title: "Series", startDate: date(4), endDate: date(4, hour: 10),
                      calendarName: "Work", recurrenceRule: rule)
    }

    private func occurrence(of series: CalendarEvent, at start: Date) throws -> CalendarEvent {
        try XCTUnwrap(EventRecurrenceExpander.originalOccurrence(of: series, startingAt: start, calendar: calendar))
    }

    private func makeStore(series: CalendarEvent) throws -> AppDataStore {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        context.autosaveEnabled = false
        context.insert(SDCalendarEvent(domain: series))
        try context.save()
        return AppDataStore(container: persistence.container, startsBackgroundServices: false,
                            calendarNotificationService: NotificationService(requestHandler: { _ in }))
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2030, month: 3, day: day, hour: hour))!
    }
}
