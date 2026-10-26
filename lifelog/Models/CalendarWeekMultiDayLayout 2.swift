import Foundation

struct CalendarWeekMultiDayLayout {
    let visibleLaneCount: Int
    let dayStates: [CalendarDayMultiDayState]
    let segments: [CalendarWeekMultiDaySegment]

    static let empty = CalendarWeekMultiDayLayout(visibleLaneCount: 0,
                                                 dayStates: Array(repeating: .empty, count: 7),
                                                 segments: [])

    init(visibleLaneCount: Int, dayStates: [CalendarDayMultiDayState],
         segments: [CalendarWeekMultiDaySegment]) {
        self.visibleLaneCount = visibleLaneCount
        self.dayStates = dayStates
        self.segments = segments
    }

    init(layout: CalendarPreviewLayout.Week) {
        visibleLaneCount = layout.visibleLaneCount
        dayStates = layout.dayStates
        segments = layout.segments.map { segment in
            CalendarWeekMultiDaySegment(
                id: segment.id,
                eventID: segment.event.id,
                title: segment.event.title,
                categoryName: segment.event.calendarName,
                color: CategoryPalette.color(for: segment.event.calendarName),
                lane: segment.lane,
                startColumn: segment.startColumn,
                endColumn: segment.endColumn,
                continuesBeforeWeek: segment.continuesBeforeWeek,
                continuesAfterWeek: segment.continuesAfterWeek
            )
        }
    }
}
