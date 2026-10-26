import Foundation
import SwiftData
import XCTest
@testable import lifelify

@MainActor
final class EventRecurrencePersistenceTests: XCTestCase {
    func testLegacyJSON_withoutRecurrenceFieldsRemainsSingleEvent() throws {
        let event = makeEvent()
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
        payload.removeValue(forKey: "recurrenceRule")
        payload.removeValue(forKey: "occurrenceReference")
        let decoded = try JSONDecoder().decode(CalendarEvent.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(decoded, event)
        XCTAssertNil(decoded.recurrenceRule)
        XCTAssertNil(decoded.occurrenceReference)
    }

    func testSeriesAndException_saveReloadAndUpdatePreserveRecurrenceAndReminder() throws {
        let schema = Schema([SDCalendarEvent.self, SDCalendarEventException.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        var series = makeEvent()
        series.recurrenceRule = EventRecurrenceRule(frequency: .weekly, interval: 2, weekdays: [2, 5],
                                                  until: series.startDate.addingTimeInterval(86_400 * 90), timeZoneIdentifier: "Asia/Tokyo")
        let row = SDCalendarEvent(domain: series)
        context.insert(row)
        var replacement = series
        replacement.title = "Only this occurrence"
        replacement.startDate = series.startDate.addingTimeInterval(86_400)
        replacement.endDate = series.endDate.addingTimeInterval(86_400)
        replacement.reminderDate = replacement.startDate.addingTimeInterval(-1_800)
        let exception = CalendarEventException(seriesID: series.id, originalStartDate: series.startDate, replacement: replacement)
        let exceptionRow = SDCalendarEventException(domain: exception)
        context.insert(exceptionRow)
        try context.save()

        let reader = ModelContext(container)
        XCTAssertEqual(CalendarEvent(sd: try XCTUnwrap(reader.fetch(FetchDescriptor<SDCalendarEvent>()).first)), series)
        XCTAssertEqual(CalendarEventException(sd: try XCTUnwrap(reader.fetch(FetchDescriptor<SDCalendarEventException>()).first)), exception)

        var endedSeries = series
        endedSeries.recurrenceRule = nil
        row.update(from: endedSeries)
        let cancelled = CalendarEventException(id: exception.id, seriesID: series.id, originalStartDate: series.startDate)
        exceptionRow.update(from: cancelled)
        try context.save()
        let updatedReader = ModelContext(container)
        XCTAssertEqual(CalendarEvent(sd: try XCTUnwrap(updatedReader.fetch(FetchDescriptor<SDCalendarEvent>()).first)), endedSeries)
        XCTAssertEqual(CalendarEventException(sd: try XCTUnwrap(updatedReader.fetch(FetchDescriptor<SDCalendarEventException>()).first)), cancelled)
    }

    func testLegacySQLiteMigration_preservesSingleEventAndAllowsPersistingExceptions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("event-recurrence-migration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.store")
        let event = makeEvent()
        weak var releasedContainer: ModelContainer?

        try autoreleasepool {
            let schema = Schema([LegacyRecurringEventSchema.SDCalendarEvent.self])
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            releasedContainer = container
            let context = ModelContext(container)
            context.insert(LegacyRecurringEventSchema.SDCalendarEvent(event: event))
            try context.save()
        }
        XCTAssertNil(releasedContainer)

        for launch in 0..<2 {
            try autoreleasepool {
                let schema = Schema([SDCalendarEvent.self, SDCalendarEventException.self])
                let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
                let container = try ModelContainer(for: schema, configurations: [configuration])
                let context = ModelContext(container)
                let rows = try context.fetch(FetchDescriptor<SDCalendarEvent>())
                XCTAssertEqual(rows.count, 1)
                XCTAssertEqual(CalendarEvent(sd: try XCTUnwrap(rows.first)), event)
                XCTAssertNil(rows.first?.recurrenceRuleData)
                if launch == 0 {
                    context.insert(SDCalendarEventException(domain: CalendarEventException(seriesID: event.id, originalStartDate: event.startDate)))
                    try context.save()
                } else {
                    let exceptions = try context.fetch(FetchDescriptor<SDCalendarEventException>())
                    XCTAssertEqual(exceptions.count, 1)
                    XCTAssertEqual(exceptions.first?.seriesID, event.id)
                    XCTAssertNil(exceptions.first?.replacementData)
                }
            }
        }
    }

    private func makeEvent() -> CalendarEvent {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        return CalendarEvent(title: "Original user title", detail: "Original user memo", startDate: start,
                             endDate: start.addingTimeInterval(3_600), calendarName: "Original category", reminderMinutes: 30)
    }
}

/// Scalar shape shipped before recurrence. Identical entity name exercises
/// adding the optional recurrence payload and the separate exception entity.
private enum LegacyRecurringEventSchema {
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
        }
    }
}
