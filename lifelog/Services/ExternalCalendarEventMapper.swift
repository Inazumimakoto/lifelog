import EventKit

/// A known calendar with no category is hidden; unknown calendars use the
/// default category. All import entry points must apply the same selection.
struct ExternalCalendarEventMapper {
    private let linksByIdentifier: [String: CalendarCategoryLink]

    init(links: [CalendarCategoryLink], unavailableLinks: [CalendarCategoryLink] = []) {
        // The event-query store may still see a calendar missing from the
        // link-query store's transient snapshot. Keep its saved choice (and
        // hidden setting), with current links taking priority over the archive.
        linksByIdentifier = Dictionary((links + unavailableLinks).map { ($0.calendarIdentifier, $0) },
                                       uniquingKeysWith: { current, _ in current })
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
