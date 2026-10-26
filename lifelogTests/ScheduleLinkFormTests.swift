import XCTest
@testable import lifelify

@MainActor
final class ScheduleLinkFormTests: XCTestCase {
    func testOptionalURLs_allowEmptyAndRejectInvalidNonemptyValues() {
        let eventForm = CalendarEventEditorFormState(defaultDate: fixtureDate)
        let taskForm = TaskEditorFormState(defaultDate: fixtureDate)
        defer {
            eventForm.clearCachedDraft()
            taskForm.clearCachedDraft()
        }
        eventForm.title = "Event"
        taskForm.title = "Task"

        XCTAssertTrue(eventForm.canSave)
        XCTAssertTrue(taskForm.canSave)
        XCTAssertNil(eventForm.makeEvent().urlString)
        XCTAssertNil(taskForm.makeTask().urlString)

        eventForm.urlString = "javascript:alert(1)"
        taskForm.urlString = "not a website"
        XCTAssertFalse(eventForm.canSave)
        XCTAssertFalse(taskForm.canSave)

        eventForm.urlString = "   "
        taskForm.urlString = "   "
        XCTAssertTrue(eventForm.canSave)
        XCTAssertTrue(taskForm.canSave)
    }

    func testSavingSchemelessURLs_normalizesBothForms() {
        let eventForm = CalendarEventEditorFormState(defaultDate: fixtureDate)
        let taskForm = TaskEditorFormState(defaultDate: fixtureDate)
        defer {
            eventForm.clearCachedDraft()
            taskForm.clearCachedDraft()
        }
        eventForm.title = "Event"
        taskForm.title = "Task"
        eventForm.urlString = "  example.com/event  "
        taskForm.urlString = "example.com/task"

        XCTAssertTrue(eventForm.canSave)
        XCTAssertTrue(taskForm.canSave)
        XCTAssertEqual(eventForm.makeEvent().urlString, "https://example.com/event")
        XCTAssertEqual(taskForm.makeTask().urlString, "https://example.com/task")
    }

    func testExistingURLs_populateFormsAndCanBeRemovedWithoutChangingIdentity() {
        let event = CalendarEvent(title: "Event", startDate: fixtureDate,
                                  endDate: fixtureDate.addingTimeInterval(3_600), calendarName: "Work",
                                  urlString: "https://example.com/event")
        let task = Task(title: "Task", startDate: fixtureDate, endDate: fixtureDate,
                        urlString: "https://example.com/task")
        let eventForm = CalendarEventEditorFormState(event: event)
        let taskForm = TaskEditorFormState(task: task)
        defer {
            eventForm.clearCachedDraft()
            taskForm.clearCachedDraft()
        }
        XCTAssertEqual(eventForm.urlString, event.urlString)
        XCTAssertEqual(taskForm.urlString, task.urlString)

        eventForm.urlString = ""
        taskForm.urlString = ""

        XCTAssertEqual(eventForm.makeEvent().id, event.id)
        XCTAssertEqual(taskForm.makeTask().id, task.id)
        XCTAssertNil(eventForm.makeEvent().urlString)
        XCTAssertNil(taskForm.makeTask().urlString)
    }

    func testUnsavedURLDrafts_restoreExactTypedValues() {
        let eventForm = CalendarEventEditorFormState(defaultDate: fixtureDate)
        let taskForm = TaskEditorFormState(defaultDate: fixtureDate)
        defer {
            eventForm.clearCachedDraft()
            taskForm.clearCachedDraft()
        }
        // Preserve incomplete input while editing; normalize only when saving.
        eventForm.urlString = "  example.com/event  "
        taskForm.urlString = "https://"
        eventForm.cacheDraft()
        taskForm.cacheDraft()

        let reopenedEvent = CalendarEventEditorFormState(defaultDate: fixtureDate)
        let reopenedTask = TaskEditorFormState(defaultDate: fixtureDate)

        XCTAssertEqual(reopenedEvent.urlString, eventForm.urlString)
        XCTAssertEqual(reopenedTask.urlString, taskForm.urlString)
    }

    func testOccurrenceURLChanges_preserveRecurrenceReferenceAndRule() {
        let rule = EventRecurrenceRule(frequency: .weekly, weekdays: [3], timeZoneIdentifier: "Asia/Tokyo")
        let reference = CalendarEventOccurrenceReference(seriesID: UUID(), originalStartDate: fixtureDate)
        let event = CalendarEvent(title: "Class", startDate: fixtureDate,
                                  endDate: fixtureDate.addingTimeInterval(3_600), calendarName: "Work",
                                  recurrenceRule: rule, occurrenceReference: reference,
                                  urlString: "https://example.com/regular-class")
        let form = CalendarEventEditorFormState(event: event)
        defer { form.clearCachedDraft() }
        form.urlString = "example.com/this-class"

        let saved = form.makeEvent()

        XCTAssertEqual(saved.urlString, "https://example.com/this-class")
        XCTAssertEqual(saved.id, event.id)
        XCTAssertEqual(saved.occurrenceReference, reference)
        XCTAssertEqual(saved.recurrenceRule, rule)
    }

    func testResetForms_clearsURLFieldsAndCachedURLs() {
        let eventForm = CalendarEventEditorFormState(defaultDate: fixtureDate)
        let taskForm = TaskEditorFormState(defaultDate: fixtureDate)
        defer {
            eventForm.clearCachedDraft()
            taskForm.clearCachedDraft()
        }
        eventForm.urlString = "example.com/event"
        taskForm.urlString = "example.com/task"
        eventForm.cacheDraft()
        taskForm.cacheDraft()

        eventForm.reset()
        taskForm.reset()

        XCTAssertEqual(eventForm.urlString, "")
        XCTAssertEqual(taskForm.urlString, "")
        XCTAssertEqual(CalendarEventEditorFormState(defaultDate: fixtureDate).urlString, "")
        XCTAssertEqual(TaskEditorFormState(defaultDate: fixtureDate).urlString, "")
    }

    private var fixtureDate: Date { Date(timeIntervalSince1970: 2_000_000_000) }
}
