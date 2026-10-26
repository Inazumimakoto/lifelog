import EventKit
import Foundation
import SwiftData
import XCTest
@testable import lifelify

@MainActor
final class ScheduleLinkPersistenceTests: XCTestCase {
    private let originalURL = "https://example.com/original?day=1#details"
    private let replacementURL = "https://example.com/one-occurrence"

    func testLegacyJSON_missingURLDecodesWithoutChangingTaskOrEventContent() throws {
        let task = makeTask()
        let event = makeEvent()
        var taskPayload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as? [String: Any])
        var eventPayload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
        taskPayload.removeValue(forKey: "urlString")
        eventPayload.removeValue(forKey: "urlString")

        let decodedTask = try JSONDecoder().decode(Task.self, from: JSONSerialization.data(withJSONObject: taskPayload))
        let decodedEvent = try JSONDecoder().decode(CalendarEvent.self, from: JSONSerialization.data(withJSONObject: eventPayload))

        XCTAssertEqual(decodedTask, task)
        XCTAssertEqual(decodedEvent, event)
        XCTAssertNil(decodedTask.linkURL)
        XCTAssertNil(decodedEvent.linkURL)
    }

    func testJSONRoundTrip_preservesTaskAndEventURLs() throws {
        var task = makeTask()
        var event = makeEvent()
        task.urlString = originalURL
        event.urlString = originalURL

        let decodedTask = try JSONDecoder().decode(Task.self, from: JSONEncoder().encode(task))
        let decodedEvent = try JSONDecoder().decode(CalendarEvent.self, from: JSONEncoder().encode(event))

        XCTAssertEqual(decodedTask, task)
        XCTAssertEqual(decodedEvent, event)
        XCTAssertEqual(decodedTask.linkURL?.absoluteString, originalURL)
        XCTAssertEqual(decodedEvent.linkURL?.absoluteString, originalURL)
    }

    func testSwiftDataCreationAndUpdate_roundTripAndClearURLsWithoutChangingOtherFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        var task = makeTask()
        var event = makeEvent()
        task.urlString = originalURL
        event.urlString = originalURL
        let taskRow = SDTask(domain: task)
        let eventRow = SDCalendarEvent(domain: event)
        context.insert(taskRow)
        context.insert(eventRow)
        try context.save()

        let reader = ModelContext(container)
        XCTAssertEqual(Task(sd: try XCTUnwrap(reader.fetch(FetchDescriptor<SDTask>()).first)), task)
        XCTAssertEqual(CalendarEvent(sd: try XCTUnwrap(reader.fetch(FetchDescriptor<SDCalendarEvent>()).first)), event)

        task.urlString = nil
        event.urlString = nil
        taskRow.update(from: task)
        eventRow.update(from: event)
        try context.save()

        let clearedReader = ModelContext(container)
        XCTAssertEqual(Task(sd: try XCTUnwrap(clearedReader.fetch(FetchDescriptor<SDTask>()).first)), task)
        XCTAssertEqual(CalendarEvent(sd: try XCTUnwrap(clearedReader.fetch(FetchDescriptor<SDCalendarEvent>()).first)), event)
        XCTAssertNil(taskRow.urlString)
        XCTAssertNil(eventRow.urlString)
    }

    func testRecurringOccurrences_inheritMasterURLAndRetainExplicitReplacementURLAfterReload() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        var series = makeEvent()
        series.urlString = originalURL
        series.recurrenceRule = EventRecurrenceRule(frequency: .daily, timeZoneIdentifier: "Asia/Tokyo")
        context.insert(SDCalendarEvent(domain: series))
        let originalStart = series.startDate.addingTimeInterval(86_400)
        var replacement = series
        replacement.startDate = originalStart.addingTimeInterval(3_600)
        replacement.endDate = replacement.startDate.addingTimeInterval(3_600)
        replacement.urlString = replacementURL
        context.insert(SDCalendarEventException(domain: CalendarEventException(
            seriesID: series.id, originalStartDate: originalStart, replacement: replacement
        )))
        try context.save()

        // Exercises the shared app/widget/intent manual mapper as well as the
        // recurrence constructor and JSON-backed exception payload.
        let result = try CalendarEventStorageQuery.events(
            in: ModelContext(container), from: series.startDate,
            to: series.startDate.addingTimeInterval(86_400 * 3), calendar: calendar
        )

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map(\.urlString), [originalURL, replacementURL, originalURL])
        XCTAssertEqual(result[1].occurrenceReference?.originalStartDate, originalStart)
        XCTAssertEqual(result[1].linkURL?.absoluteString, replacementURL)
        XCTAssertEqual(result[2].linkURL?.absoluteString, originalURL)
    }

    func testExternalCalendarMapping_importsURLAndReflectsRemovalWithoutWritingSource() throws {
        let store = EKEventStore()
        let source = EKEvent(eventStore: store)
        source.calendar = EKCalendar(for: .event, eventStore: store)
        source.title = "Imported meeting"
        source.startDate = makeEvent().startDate
        source.endDate = source.startDate.addingTimeInterval(3_600)
        source.url = URL(string: originalURL)
        let mapper = ExternalCalendarEventMapper(links: [])

        let imported = try XCTUnwrap(mapper.map([source]).first)

        XCTAssertEqual(imported.urlString, originalURL)
        XCTAssertEqual(imported.linkURL?.absoluteString, originalURL)
        XCTAssertEqual(source.url?.absoluteString, originalURL)
        source.url = nil
        let updated = try XCTUnwrap(mapper.map([source]).first)
        XCTAssertEqual(updated.id, imported.id)
        XCTAssertNil(updated.urlString)
        XCTAssertNil(updated.linkURL)
    }

    func testLegacySQLiteMigration_addsOptionalURLsAndPreservesTaskAndRecurringEvent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("schedule-link-migration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.store")
        let task = makeTask()
        var event = makeEvent()
        event.recurrenceRule = EventRecurrenceRule(frequency: .weekly, interval: 2, weekdays: [2, 5], timeZoneIdentifier: "Asia/Tokyo")
        weak var releasedContainer: ModelContainer?

        try autoreleasepool {
            let schema = Schema([LegacyScheduleLinkSchema.SDTask.self, LegacyScheduleLinkSchema.SDCalendarEvent.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            releasedContainer = container
            let context = ModelContext(container)
            context.insert(LegacyScheduleLinkSchema.SDTask(task: task))
            context.insert(LegacyScheduleLinkSchema.SDCalendarEvent(event: event))
            try context.save()
        }
        XCTAssertNil(releasedContainer)

        for launch in 0..<2 {
            try autoreleasepool {
                let schema = Schema([SDTask.self, SDCalendarEvent.self])
                let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
                let context = ModelContext(container)
                let taskRow = try XCTUnwrap(context.fetch(FetchDescriptor<SDTask>()).first)
                let eventRow = try XCTUnwrap(context.fetch(FetchDescriptor<SDCalendarEvent>()).first)
                if launch == 0 {
                    XCTAssertEqual(Task(sd: taskRow), task)
                    XCTAssertEqual(CalendarEvent(sd: eventRow), event)
                    XCTAssertNil(taskRow.urlString)
                    XCTAssertNil(eventRow.urlString)
                    taskRow.urlString = originalURL
                    eventRow.urlString = originalURL
                    try context.save()
                } else {
                    var linkedTask = task
                    linkedTask.urlString = originalURL
                    var linkedEvent = event
                    linkedEvent.urlString = originalURL
                    XCTAssertEqual(Task(sd: taskRow), linkedTask)
                    XCTAssertEqual(CalendarEvent(sd: eventRow), linkedEvent)
                }
            }
        }
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return value
    }

    private func makeEvent() -> CalendarEvent {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
        return CalendarEvent(title: "Original user event", detail: "Original memo", startDate: start,
                             endDate: start.addingTimeInterval(3_600), calendarName: "Original category", reminderMinutes: 15)
    }

    private func makeTask() -> Task {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        return Task(title: "Original user task", detail: "Original task memo", startDate: start,
                    endDate: start.addingTimeInterval(86_400), priority: .high,
                    reminderDate: start.addingTimeInterval(3_600), dateOnlyTimeZoneIdentifier: "Asia/Tokyo")
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([SDTask.self, SDCalendarEvent.self, SDCalendarEventException.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }
}

/// Exact scalar entity shapes before adding the optional URL field.
private enum LegacyScheduleLinkSchema {
    @Model
    final class SDTask {
        @Attribute(.unique) var id: UUID
        var title: String
        var detail: String
        var startDate: Date?
        var endDate: Date?
        var priority: TaskPriority
        var isCompleted: Bool
        var reminderDate: Date?
        var completedAt: Date?
        var dateOnlyTimeZoneIdentifier: String?

        init(task: Task) {
            id = task.id
            title = task.title
            detail = task.detail
            startDate = task.startDate
            endDate = task.endDate
            priority = task.priority
            isCompleted = task.isCompleted
            reminderDate = task.reminderDate
            completedAt = task.completedAt
            dateOnlyTimeZoneIdentifier = task.dateOnlyTimeZoneIdentifier
        }
    }

    @Model
    final class SDCalendarEvent {
        @Attribute(.unique) var id: UUID
        var title: String
        var detail: String?
        var startDate: Date
        var endDate: Date
        var calendarName: String
        var isAllDay: Bool
        var sourceCalendarIdentifier: String?
        var reminderMinutes: Int?
        var reminderDate: Date?
        var dateOnlyTimeZoneIdentifier: String?
        var recurrenceRuleData: Data?

        @MainActor
        init(event: CalendarEvent) {
            id = event.id
            title = event.title
            detail = event.detail
            startDate = event.startDate
            endDate = event.endDate
            calendarName = event.calendarName
            isAllDay = event.isAllDay
            sourceCalendarIdentifier = event.sourceCalendarIdentifier
            reminderMinutes = event.reminderMinutes
            reminderDate = event.reminderDate
            dateOnlyTimeZoneIdentifier = event.dateOnlyTimeZoneIdentifier
            if let rule = event.recurrenceRule {
                recurrenceRuleData = try? JSONEncoder().encode(rule)
            } else {
                recurrenceRuleData = nil
            }
        }
    }
}
