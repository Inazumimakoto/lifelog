import XCTest
@testable import lifelify

@MainActor
final class CalendarEventEditorCategoryMigrationTests: XCTestCase {
    func testRename_updatesOpenDraftWithoutResettingEditedFieldsOrReminder() throws {
        try withFixture {
            let service = makeService()
            let form = makeEditedNewDraft(category: "Work")
            defer { form.clearCachedDraft() }
            var expected = form.draft
            expected.category = "Career"
            NotificationSettingsManager.shared.isEventCategoryNotificationEnabled = true
            NotificationSettingsManager.shared.saveCategorySettings([
                .init(categoryName: "Work", enabled: false, minutesBefore: 5)
            ])

            try service.update(originalName: "Work", name: "Career", colorToken: "#123456")

            XCTAssertEqual(form.draft, expected)
        }
    }

    func testRename_migratesCachedDraftAfterItsEditorHasBeenReleased() throws {
        try withFixture {
            let service = makeService()
            var form: CalendarEventEditorFormState? = makeEditedNewDraft(category: "Work")
            weak var releasedForm = form
            var expected = try XCTUnwrap(form).draft
            expected.category = "Career"
            form?.cacheDraft(detailOverride: "Latest memo from the text editor")
            expected.detail = "Latest memo from the text editor"
            form = nil
            XCTAssertNil(releasedForm)

            try service.update(originalName: "Work", name: "Career", colorToken: "#123456")

            let reopened = CalendarEventEditorFormState(defaultDate: fixtureDay)
            defer { reopened.clearCachedDraft() }
            XCTAssertEqual(reopened.draft, expected)
        }
    }

    func testDelete_movesOpenAndClosedDraftsToReplacementPreservingReminders() throws {
        try withFixture {
            let service = makeService()
            let openForm = makeEditedNewDraft(category: "Work")
            defer { openForm.clearCachedDraft() }
            var expectedOpen = openForm.draft
            expectedOpen.category = "Personal"
            let event = fixtureEvent(category: "Work")
            var closedForm: CalendarEventEditorFormState? = CalendarEventEditorFormState(event: event)
            closedForm?.title = "Unsaved edited title"
            closedForm?.detail = "Unsaved edited memo"
            closedForm?.reminderMinutes = 15
            closedForm?.cacheDraft()
            var expectedClosed = try XCTUnwrap(closedForm).draft
            expectedClosed.category = "Personal"
            closedForm = nil
            NotificationSettingsManager.shared.isEventCategoryNotificationEnabled = true
            NotificationSettingsManager.shared.saveCategorySettings([
                .init(categoryName: "Personal", enabled: false, minutesBefore: 60)
            ])

            XCTAssertEqual(service.delete(name: "Work"), "Personal")

            XCTAssertEqual(openForm.draft, expectedOpen)
            let reopened = CalendarEventEditorFormState(event: event)
            defer { reopened.clearCachedDraft() }
            XCTAssertEqual(reopened.draft, expectedClosed)
        }
    }

    func testColorOnlyUpdate_preservesOpenAndCachedDrafts() throws {
        try withFixture {
            let service = makeService()
            let form = makeEditedNewDraft(category: "Work")
            defer { form.clearCachedDraft() }
            form.cacheDraft()
            let expected = form.draft

            try service.update(originalName: "Work", name: "Work", colorToken: "#0000FF")

            XCTAssertEqual(form.draft, expected)
            let reopened = CalendarEventEditorFormState(defaultDate: fixtureDay)
            XCTAssertEqual(reopened.draft, expected)
        }
    }

    func testSelectingCategoryForNewEvent_appliesDefaultsOnlyForANewSelection() throws {
        try withFixture {
            let form = makeEditedNewDraft(category: "Work")
            defer { form.clearCachedDraft() }
            NotificationSettingsManager.shared.isEventCategoryNotificationEnabled = true
            NotificationSettingsManager.shared.saveCategorySettings([
                .init(categoryName: "Personal", enabled: true, minutesBefore: 60)
            ])

            form.selectCategory("Personal")

            XCTAssertEqual(form.category, "Personal")
            XCTAssertTrue(form.hasReminder)
            XCTAssertTrue(form.useRelativeReminder)
            XCTAssertEqual(form.reminderMinutes, 60)
            XCTAssertEqual(form.reminderDate, form.startDate.addingTimeInterval(-3_600))
            form.reminderMinutes = 15
            form.selectCategory("Personal")
            XCTAssertEqual(form.reminderMinutes, 15)
        }
    }

    func testSelectingCategoryForExistingEvent_preservesExplicitReminder() throws {
        try withFixture {
            let event = fixtureEvent(category: "Work")
            let form = CalendarEventEditorFormState(event: event)
            defer { form.clearCachedDraft() }
            var expected = form.draft
            expected.category = "Personal"
            NotificationSettingsManager.shared.isEventCategoryNotificationEnabled = true
            NotificationSettingsManager.shared.saveCategorySettings([
                .init(categoryName: "Personal", enabled: false, minutesBefore: 60)
            ])

            form.selectCategory("Personal")

            XCTAssertEqual(form.draft, expected)
        }
    }

    private var fixtureDay: Date {
        Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))
    }

    private func makeService() -> CalendarCategoryService {
        CalendarCategoryService(store: AppDataStore(container: PersistenceController(inMemory: true).container,
                                                    startsBackgroundServices: false))
    }

    private func makeEditedNewDraft(category: String) -> CalendarEventEditorFormState {
        let form = CalendarEventEditorFormState(defaultDate: fixtureDay)
        form.title = "Unsaved title"
        form.detail = "Unsaved memo"
        form.category = category
        form.startDate = fixtureDay.addingTimeInterval(39_600)
        form.endDate = fixtureDay.addingTimeInterval(45_000)
        form.hasReminder = true
        form.useRelativeReminder = false
        form.reminderMinutes = 15
        form.reminderDate = fixtureDay.addingTimeInterval(28_800)
        return form
    }

    private func fixtureEvent(category: String) -> CalendarEvent {
        CalendarEvent(title: "Saved event", detail: "Saved memo",
                      startDate: fixtureDay.addingTimeInterval(36_000),
                      endDate: fixtureDay.addingTimeInterval(39_600), calendarName: category,
                      reminderMinutes: 5)
    }

    private func withFixture(operation: () throws -> Void) throws {
        let sharedDefaults = try XCTUnwrap(UserDefaults(suiteName: PersistenceController.appGroupIdentifier))
        let scopes = [UserDefaults.standard, sharedDefaults]
        let paletteKey = "CategoryPalette_Categories_V3"
        let keys = [paletteKey, "categoryNotificationSettings", "eventCategoryNotificationEnabled",
                    "todayOverviewNotificationEnabled", AppDataStore.externalCalendarEventsDefaultsKey,
                    AppDataStore.externalCalendarRangeDefaultsKey]
        let savedValues = scopes.flatMap { defaults in
            keys.map { key in (defaults: defaults, key: key, value: defaults.object(forKey: key)) }
        }
        defer {
            CalendarEventEditorFormState(defaultDate: fixtureDay).clearCachedDraft()
            for entry in savedValues {
                if let value = entry.value {
                    entry.defaults.set(value, forKey: entry.key)
                } else {
                    entry.defaults.removeObject(forKey: entry.key)
                }
            }
        }
        let paletteData = try JSONEncoder().encode(["Work": "#FF0000", "Personal": "#00FF00"])
        for defaults in scopes {
            defaults.set(paletteData, forKey: paletteKey)
            defaults.removeObject(forKey: "categoryNotificationSettings")
            defaults.set(false, forKey: "eventCategoryNotificationEnabled")
            defaults.set(false, forKey: "todayOverviewNotificationEnabled")
            defaults.removeObject(forKey: AppDataStore.externalCalendarEventsDefaultsKey)
            defaults.removeObject(forKey: AppDataStore.externalCalendarRangeDefaultsKey)
        }
        CalendarEventEditorFormState(defaultDate: fixtureDay).clearCachedDraft()
        try operation()
    }
}
