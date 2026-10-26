import EventKit

/// A known calendar with no category is hidden; unknown calendars use the
/// default category. All import entry points must apply the same selection.
struct ExternalCalendarEventMapper {
    private let linksByIdentifier: [String: CalendarCategoryLink]

    init(links: [CalendarCategoryLink]) {
        linksByIdentifier = Dictionary(uniqueKeysWithValues: links.map { ($0.calendarIdentifier, $0) })
    }

    func categoryName(for calendarIdentifier: String) -> String? {
        if let link = linksByIdentifier[calendarIdentifier] {
            return link.categoryId
        }
        return CategoryPalette.defaultCategoryName
    }

    func map(_ events: [EKEvent]) -> [CalendarEvent] {
        events.compactMap { event in
            guard let category = categoryName(for: event.calendar.calendarIdentifier) else { return nil }
            return CalendarEvent(event: event, categoryName: category)
        }
    }
}
