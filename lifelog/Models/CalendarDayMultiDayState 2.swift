struct CalendarDayMultiDayState: Equatable {
    let visibleLaneCount: Int
    let occupiedVisibleLanes: Set<Int>
    let hiddenMultiDayCount: Int

    static let empty = CalendarDayMultiDayState(visibleLaneCount: 0,
                                               occupiedVisibleLanes: [],
                                               hiddenMultiDayCount: 0)
}
