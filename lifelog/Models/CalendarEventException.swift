import Foundation

/// A missing replacement skips one slot; a replacement changes only that slot.
struct CalendarEventException: Identifiable, Hashable, Codable {
    var id: UUID
    var seriesID: UUID
    var originalStartDate: Date
    var replacement: CalendarEvent?

    init(id: UUID = UUID(), seriesID: UUID, originalStartDate: Date, replacement: CalendarEvent? = nil) {
        self.id = id
        self.seriesID = seriesID
        self.originalStartDate = originalStartDate
        self.replacement = replacement
    }

    var occurrenceReference: CalendarEventOccurrenceReference {
        CalendarEventOccurrenceReference(seriesID: seriesID, originalStartDate: originalStartDate)
    }

    init(sd: SDCalendarEventException) {
        let replacement: CalendarEvent?
        if let data = sd.replacementData {
            replacement = try? JSONDecoder().decode(CalendarEvent.self, from: data)
        } else {
            replacement = nil
        }
        self.init(id: sd.id,
                  seriesID: sd.seriesID,
                  originalStartDate: sd.originalStartDate,
                  replacement: replacement)
    }
}
