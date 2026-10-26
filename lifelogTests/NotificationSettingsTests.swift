import XCTest
@testable import lifelify

@MainActor
final class NotificationSettingsTests: XCTestCase {
    func testGetOrCreateNewCategory_persistsDisabledSetting() throws {
        try withCategorySettings {
            let manager = NotificationSettingsManager.shared

            let setting = manager.getOrCreateSetting(for: "New category")

            XCTAssertFalse(setting.enabled)
            XCTAssertEqual(setting.minutesBefore, CategoryNotificationSetting.defaultMinutes)
            XCTAssertEqual(manager.getCategorySettings(), [setting])
        }
    }

    func testEnsureCategories_preservesSavedChoicesAndDisablesNewCategories() throws {
        try withCategorySettings {
            let manager = NotificationSettingsManager.shared
            let enabled = CategoryNotificationSetting(categoryName: "Enabled", enabled: true, minutesBefore: 1)
            let disabled = CategoryNotificationSetting(categoryName: "Disabled", enabled: false,
                                                       useRelativeTime: false, hour: 8, minute: 45)
            manager.saveCategorySettings([enabled, disabled])

            let settings = manager.ensureCategorySettings(for: ["Enabled", "New", "Disabled", "New"])

            XCTAssertEqual(settings, [enabled, disabled, .init(categoryName: "New", enabled: false)])
            XCTAssertEqual(manager.getCategorySettings(), settings)
            XCTAssertEqual(manager.getOrCreateSetting(for: "Enabled"), enabled)
        }
    }

    func testUpdateUnknownCategoryTiming_keepsNotificationsDisabled() throws {
        try withCategorySettings {
            let manager = NotificationSettingsManager.shared

            manager.updateSetting(for: "New category", minutesBefore: 1)

            let setting = try XCTUnwrap(manager.getSetting(for: "New category"))
            XCTAssertFalse(setting.enabled)
            XCTAssertEqual(setting.minutesBefore, 1)
        }
    }

    func testExplicitOptInAndParentReenable_preserveSavedCategoryChoices() throws {
        try withCategorySettings {
            let manager = NotificationSettingsManager.shared
            manager.updateSetting(for: "Enabled", enabled: true, minutesBefore: 1)
            manager.updateSetting(for: "Disabled", enabled: false, minutesBefore: 5)
            let expected = manager.getCategorySettings()

            manager.isEventCategoryNotificationEnabled = true
            manager.isEventCategoryNotificationEnabled = false
            manager.isEventCategoryNotificationEnabled = true
            manager.ensureCategorySettings(for: ["Enabled", "Disabled"])

            XCTAssertEqual(manager.getCategorySettings(), expected)
            XCTAssertEqual(manager.getSetting(for: "Enabled")?.enabled, true)
            XCTAssertEqual(manager.getSetting(for: "Disabled")?.enabled, false)
            XCTAssertEqual(manager.getSetting(for: "Enabled")?.minutesBefore, 1)
        }
    }

    func testParentEnabledWithUnconfiguredCategory_leavesNewEventReminderOff() throws {
        try withCategorySettings {
            NotificationSettingsManager.shared.isEventCategoryNotificationEnabled = true
            let form = CalendarEventEditorFormState(defaultDate: Date(timeIntervalSince1970: 2_000_000_000))
            defer { form.clearCachedDraft() }

            XCTAssertFalse(form.hasReminder)
            XCTAssertEqual(NotificationSettingsManager.shared.getSetting(for: form.category)?.enabled, false)

            form.hasReminder = true
            form.selectCategory("Another unconfigured category")

            XCTAssertFalse(form.hasReminder)
            XCTAssertEqual(NotificationSettingsManager.shared.getSetting(for: form.category)?.enabled, false)
        }
    }

    func testReminderDisplayWithoutCategorySetting_showsNoImplicitReminder() throws {
        try withCategorySettings {
            NotificationSettingsManager.shared.isEventCategoryNotificationEnabled = true
            let start = Date(timeIntervalSince1970: 2_000_000_000)
            var event = CalendarEvent(title: "Event", startDate: start, endDate: start.addingTimeInterval(3_600),
                                      calendarName: "Unconfigured category")

            XCTAssertNil(ReminderDisplay.eventReminderDate(for: event))

            event.reminderMinutes = 1
            XCTAssertEqual(ReminderDisplay.eventReminderDate(for: event), start.addingTimeInterval(-60))
        }
    }

    private func withCategorySettings(operation: () throws -> Void) throws {
        let defaults = UserDefaults.standard
        let keys = ["categoryNotificationSettings", "eventCategoryNotificationEnabled"]
        let savedValues = keys.map { (key: $0, value: defaults.object(forKey: $0)) }
        defer {
            for entry in savedValues {
                if let value = entry.value {
                    defaults.set(value, forKey: entry.key)
                } else {
                    defaults.removeObject(forKey: entry.key)
                }
            }
        }
        keys.forEach { defaults.removeObject(forKey: $0) }
        try operation()
    }
}
