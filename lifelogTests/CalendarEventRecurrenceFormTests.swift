import XCTest
@testable import lifelify

@MainActor
final class CalendarEventRecurrenceFormTests: XCTestCase {
    func testWeeklyRule_savesSelectedDaysIntervalAndInclusiveEndDate() throws {
        let form = CalendarEventEditorFormState(defaultDate: fixtureStart)
        defer { form.clearCachedDraft() }
        form.title = "Swimming"
        form.startDate = fixtureStart
        form.selectRecurrenceFrequency(.biweekly)
        form.recurrenceWeekdays = [2, 5]
        form.hasRecurrenceEnd = true
        form.recurrenceEndDate = fixtureStart.addingTimeInterval(30 * 86_400)

        let event = form.makeEvent()
        let rule = try XCTUnwrap(event.recurrenceRule)

        XCTAssertEqual(rule.frequency, .weekly)
        XCTAssertEqual(rule.interval, 2)
        XCTAssertEqual(rule.weekdays, [2, 5])
        XCTAssertEqual(rule.until, form.recurrenceEndDate)
        XCTAssertEqual(rule.timeZoneIdentifier, form.calendar.timeZone.identifier)
        XCTAssertTrue(form.canSave)
        XCTAssertNil(event.occurrenceReference)
    }

    func testWeeklyRuleWithoutWeekdays_preventsSaving() {
        let form = CalendarEventEditorFormState(defaultDate: fixtureStart)
        defer { form.clearCachedDraft() }
        form.title = "Class"
        form.selectRecurrenceFrequency(.weekly)
        form.recurrenceWeekdays = []

        XCTAssertFalse(form.canSave)
        form.selectRecurrenceFrequency(.daily)
        XCTAssertTrue(form.canSave)
    }

    func testOccurrenceEdit_preservesOriginalIdentityAndSeriesRuleWhenMoved() throws {
        let rule = EventRecurrenceRule(frequency: .weekly, interval: 2, weekdays: [3], timeZoneIdentifier: "Asia/Tokyo")
        let reference = CalendarEventOccurrenceReference(seriesID: UUID(), originalStartDate: fixtureStart)
        let event = CalendarEvent(title: "Original", startDate: fixtureStart,
                                  endDate: fixtureStart.addingTimeInterval(3_600), calendarName: "Work",
                                  recurrenceRule: rule, occurrenceReference: reference)
        let form = CalendarEventEditorFormState(event: event)
        defer { form.clearCachedDraft() }
        form.title = "Moved this week"
        form.startDate = fixtureStart.addingTimeInterval(86_400)
        form.endDate = form.startDate.addingTimeInterval(7_200)

        let updated = form.makeEvent()

        XCTAssertEqual(updated.id, event.id)
        XCTAssertEqual(updated.occurrenceReference, reference)
        XCTAssertEqual(updated.recurrenceRule, rule)
        XCTAssertEqual(updated.startDate, form.startDate)
        XCTAssertEqual(updated.title, "Moved this week")
        XCTAssertEqual(form.calendar.timeZone.identifier, "Asia/Tokyo")
        XCTAssertFalse(form.hasRecurrenceRuleChanges)
    }

    func testOccurrenceRecurrenceControls_canTurnOffRepeatingWithoutLosingReference() {
        let rule = EventRecurrenceRule(frequency: .weekly, weekdays: [3], timeZoneIdentifier: "Asia/Tokyo")
        let reference = CalendarEventOccurrenceReference(seriesID: UUID(), originalStartDate: fixtureStart)
        let event = CalendarEvent(title: "Class", startDate: fixtureStart,
                                  endDate: fixtureStart.addingTimeInterval(3_600), calendarName: "Work",
                                  recurrenceRule: rule, occurrenceReference: reference)
        let form = CalendarEventEditorFormState(event: event)
        defer { form.clearCachedDraft() }

        form.selectRecurrenceFrequency(.none)

        XCTAssertNil(form.makeEvent().recurrenceRule)
        XCTAssertEqual(form.makeEvent().occurrenceReference, reference)
        XCTAssertTrue(form.hasRecurrenceRuleChanges)
        XCTAssertTrue(form.canSave)
    }

    func testOccurrenceWeekdayChanges_updateRuleAndRetainItsIntervalAnchor() throws {
        let anchor = fixtureStart.addingTimeInterval(-28 * 86_400)
        let rule = EventRecurrenceRule(frequency: .weekly, interval: 2, weekdays: [3],
                                       timeZoneIdentifier: "Asia/Tokyo", anchorDate: anchor)
        let event = CalendarEvent(title: "Class", startDate: fixtureStart,
                                  endDate: fixtureStart.addingTimeInterval(3_600), calendarName: "Work",
                                  recurrenceRule: rule,
                                  occurrenceReference: .init(seriesID: UUID(), originalStartDate: fixtureStart))
        let form = CalendarEventEditorFormState(event: event)
        defer { form.clearCachedDraft() }
        form.recurrenceWeekdays = [2, 5]

        let editedRule = try XCTUnwrap(form.makeEvent().recurrenceRule)

        XCTAssertEqual(editedRule.weekdays, [2, 5])
        XCTAssertEqual(editedRule.interval, 2)
        XCTAssertEqual(editedRule.anchorDate, anchor)
        XCTAssertTrue(form.hasRecurrenceRuleChanges)
        form.recurrenceWeekdays = []
        XCTAssertFalse(form.canSave)
    }

    func testUntouchedOccurrenceRule_preservesCadenceMetadataExactly() {
        let anchor = fixtureStart.addingTimeInterval(-42 * 86_400)
        let rule = EventRecurrenceRule(frequency: .weekly, interval: 3, weekdays: [],
                                       timeZoneIdentifier: "Asia/Tokyo", anchorDate: anchor)
        let event = CalendarEvent(title: "Class", startDate: fixtureStart,
                                  endDate: fixtureStart.addingTimeInterval(3_600), calendarName: "Work",
                                  recurrenceRule: rule,
                                  occurrenceReference: .init(seriesID: UUID(), originalStartDate: fixtureStart))
        let form = CalendarEventEditorFormState(event: event)
        defer { form.clearCachedDraft() }
        form.title = "Changed title"

        XCTAssertEqual(form.makeEvent().recurrenceRule, rule)
        XCTAssertFalse(form.hasRecurrenceRuleChanges)
    }

    func testMovedLegacyOccurrenceWithImplicitWeekday_opensWithoutChangingItsRule() throws {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let movedStart = try XCTUnwrap(tokyo.date(byAdding: .day, value: 1, to: fixtureStart))
        let rule = EventRecurrenceRule(frequency: .weekly, weekdays: [], timeZoneIdentifier: "Asia/Tokyo")
        let event = CalendarEvent(title: "Moved class", startDate: movedStart,
                                  endDate: movedStart.addingTimeInterval(3_600), calendarName: "Work",
                                  recurrenceRule: rule,
                                  occurrenceReference: .init(seriesID: UUID(), originalStartDate: fixtureStart))
        let form = CalendarEventEditorFormState(event: event)
        defer { form.clearCachedDraft() }

        XCTAssertEqual(form.recurrenceWeekdays, [tokyo.component(.weekday, from: fixtureStart)])
        XCTAssertEqual(form.makeEvent().recurrenceRule, rule)
        XCTAssertFalse(form.hasRecurrenceRuleChanges)
    }

    func testRuleEndDateWithinSameSourceDay_doesNotCreateFalseRuleChange() throws {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let until = tokyo.startOfDay(for: fixtureStart.addingTimeInterval(30 * 86_400))
        let rule = EventRecurrenceRule(frequency: .weekly, weekdays: [3], until: until, timeZoneIdentifier: "Asia/Tokyo")
        let event = CalendarEvent(title: "Class", startDate: fixtureStart,
                                  endDate: fixtureStart.addingTimeInterval(3_600), calendarName: "Work", recurrenceRule: rule)
        let form = CalendarEventEditorFormState(event: event)
        defer { form.clearCachedDraft() }
        form.recurrenceEndDate = try XCTUnwrap(tokyo.date(byAdding: .hour, value: 12, to: until))

        XCTAssertEqual(form.makeEvent().recurrenceRule, rule)
        XCTAssertFalse(form.hasRecurrenceRuleChanges)
    }

    func testReopenedDraft_keepsUnsavedTextAndItsOwnBaselineWhenSourceChanged() {
        let original = CalendarEvent(title: "Original", startDate: fixtureStart,
                                     endDate: fixtureStart.addingTimeInterval(3_600), calendarName: "Work",
                                     recurrenceRule: .init(frequency: .weekly, weekdays: [3], timeZoneIdentifier: "Asia/Tokyo"))
        let form = CalendarEventEditorFormState(event: original)
        defer { form.clearCachedDraft() }
        form.title = "Unsaved text"
        form.recurrenceWeekdays = [2, 5]
        form.cacheDraft()
        var newerSource = original
        newerSource.title = "Changed elsewhere"
        newerSource.recurrenceRule = .init(frequency: .daily, timeZoneIdentifier: "Asia/Tokyo")

        let reopened = CalendarEventEditorFormState(event: newerSource)

        XCTAssertEqual(reopened.title, "Unsaved text")
        XCTAssertEqual(reopened.originalEvent, original)
        XCTAssertEqual(reopened.recurrenceWeekdays, [2, 5])
        XCTAssertTrue(reopened.hasRecurrenceRuleChanges)
    }

    func testCategoryReplacement_migratesOpenBaselineWhenDraftUsesAnotherCategory() {
        let original = CalendarEvent(title: "Original", startDate: fixtureStart,
                                     endDate: fixtureStart.addingTimeInterval(3_600), calendarName: "Saved category",
                                     recurrenceRule: .init(frequency: .weekly, weekdays: [3], timeZoneIdentifier: "Asia/Tokyo"))
        let form = CalendarEventEditorFormState(event: original)
        defer { form.clearCachedDraft() }
        form.title = "Unsaved title"
        form.detail = "Unsaved memo"
        form.urlString = "https://example.com/unsaved"
        form.category = "Different draft category"
        form.cacheDraft()
        let expectedDraft = form.draft
        var renamed = original
        renamed.calendarName = "Renamed saved category"

        CategoryPalette.notifyCategoryReplacement(from: original.calendarName, to: renamed.calendarName)

        XCTAssertEqual(form.originalEvent, renamed)
        XCTAssertEqual(form.draft, expectedDraft)
        // A subsequent keystroke must not put the obsolete baseline back into
        // the static cache after its category replacement observer has run.
        form.cacheDraft()
        let reopened = CalendarEventEditorFormState(event: renamed)
        XCTAssertEqual(reopened.originalEvent, renamed)
        XCTAssertEqual(reopened.draft, expectedDraft)
    }

    func testCategoryReplacement_migratesClosedDraftBaselineIndependentlyOfDraftCategory() throws {
        let original = CalendarEvent(title: "Original", startDate: fixtureStart,
                                     endDate: fixtureStart.addingTimeInterval(3_600), calendarName: "Saved category",
                                     recurrenceRule: .init(frequency: .weekly, weekdays: [3], timeZoneIdentifier: "Asia/Tokyo"))
        var form: CalendarEventEditorFormState? = CalendarEventEditorFormState(event: original)
        form?.title = "Unsaved title"
        form?.category = "Different draft category"
        form?.cacheDraft()
        let expectedDraft = try XCTUnwrap(form).draft
        weak var released = form
        form = nil
        XCTAssertNil(released)
        var renamed = original
        renamed.calendarName = "Renamed saved category"

        CategoryPalette.notifyCategoryReplacement(from: original.calendarName, to: renamed.calendarName)

        let reopened = CalendarEventEditorFormState(event: renamed)
        defer { reopened.clearCachedDraft() }
        XCTAssertEqual(reopened.originalEvent, renamed)
        XCTAssertEqual(reopened.draft, expectedDraft)
    }

    func testRecurrenceDraft_reopensWithWeekdaysAndEndDate() {
        let form = CalendarEventEditorFormState(defaultDate: fixtureStart)
        defer { form.clearCachedDraft() }
        form.title = "Draft"
        form.selectRecurrenceFrequency(.weekly)
        form.recurrenceWeekdays = [1, 7]
        form.hasRecurrenceEnd = true
        form.recurrenceEndDate = fixtureStart.addingTimeInterval(90 * 86_400)
        form.cacheDraft()

        let reopened = CalendarEventEditorFormState(defaultDate: fixtureStart)

        XCTAssertEqual(reopened.draft, form.draft)
    }

    func testEnablingRecurrence_replacesAbsoluteReminderWithPerOccurrenceOffset() {
        let form = CalendarEventEditorFormState(defaultDate: fixtureStart)
        defer { form.clearCachedDraft() }
        form.title = "Reminder"
        form.hasReminder = true
        form.useRelativeReminder = false
        form.reminderMinutes = 15
        form.selectRecurrenceFrequency(.weekly)

        let event = form.makeEvent()

        XCTAssertTrue(form.useRelativeReminder)
        XCTAssertEqual(event.reminderMinutes, 15)
        XCTAssertNil(event.reminderDate)
    }

    func testResavingSeriesEndedBeforeFirstOccurrence_preservesEarlierCutoffAndSourceTimeZone() throws {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let cutoff = try XCTUnwrap(tokyo.date(byAdding: .day, value: -1, to: tokyo.startOfDay(for: fixtureStart)))
        let rule = EventRecurrenceRule(frequency: .weekly, weekdays: [3], until: cutoff, timeZoneIdentifier: "Asia/Tokyo")
        let event = CalendarEvent(title: "Ended", startDate: fixtureStart,
                                  endDate: fixtureStart.addingTimeInterval(3_600), calendarName: "Work", recurrenceRule: rule)
        let form = CalendarEventEditorFormState(event: event)
        defer { form.clearCachedDraft() }

        let saved = form.makeEvent()

        XCTAssertEqual(saved.recurrenceRule?.until, cutoff)
        XCTAssertEqual(form.recurrenceEndLowerBound, cutoff)
        XCTAssertEqual(saved.recurrenceRule?.timeZoneIdentifier, "Asia/Tokyo")
    }

    private var fixtureStart: Date { Date(timeIntervalSince1970: 1_900_000_000) }
}
