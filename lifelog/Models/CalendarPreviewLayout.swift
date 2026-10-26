import Foundation

/// Shared calendar preview placement for the journal and wallpaper (requirements §Calendar).
/// Presentation colors and privacy labels stay with their respective consumers.
enum CalendarPreviewLayout {
    struct Segment: Identifiable {
        let id: String
        let event: CalendarEvent
        let lane: Int
        let startColumn: Int
        let endColumn: Int
        let continuesBeforeWeek: Bool
        let continuesAfterWeek: Bool
    }

    struct Week {
        let visibleLaneCount: Int
        let dayStates: [CalendarDayMultiDayState]
        let segments: [Segment]

        static let empty = Week(visibleLaneCount: 0,
                                dayStates: Array(repeating: .empty, count: 7),
                                segments: [])
    }

    enum Row<Item> {
        case empty
        case multiDayPlaceholder
        case item(Item)
        case overflow(Int)
    }

    static func isMultiDayEvent(start: Date, end: Date, calendar: Calendar) -> Bool {
        let adjustedEnd = calendar.date(byAdding: .second, value: -1, to: end) ?? end
        return !calendar.isDate(start, inSameDayAs: adjustedEnd)
    }

    static func isMultiDayEvent(_ event: CalendarEvent, calendar: Calendar) -> Bool {
        isMultiDayEvent(start: event.displayStartDate(calendar: calendar), end: event.displayEndDate(calendar: calendar), calendar: calendar)
    }

    static func week(dates weekDates: [Date], events: [CalendarEvent],
                     itemLimit: Int, calendar: Calendar) -> Week {
        guard weekDates.count == 7,
              let firstWeekDate = weekDates.first,
              let lastWeekDate = weekDates.last
        else {
            return .empty
        }

        let weekStart = calendar.startOfDay(for: firstWeekDate)
        let weekLastDay = calendar.startOfDay(for: lastWeekDate)
        guard let weekEndExclusive = calendar.date(byAdding: .day, value: 1, to: weekLastDay) else {
            return .empty
        }

        struct Candidate {
            let event: CalendarEvent
            let startColumn: Int
            let endColumn: Int
            let continuesBeforeWeek: Bool
            let continuesAfterWeek: Bool
        }

        var candidates: [Candidate] = []
        for event in events {
            let start = event.displayStartDate(calendar: calendar), end = event.displayEndDate(calendar: calendar)
            guard start < weekEndExclusive, end > weekStart else { continue }

            let adjustedEnd = calendar.date(byAdding: .second, value: -1, to: end) ?? end
            let eventStartDay = calendar.startOfDay(for: start)
            let rawEventEndDay = calendar.startOfDay(for: adjustedEnd)
            let eventEndDay = max(rawEventEndDay, eventStartDay)
            let visibleStartDay = max(eventStartDay, weekStart)
            let visibleEndDay = min(eventEndDay, weekLastDay)

            guard visibleStartDay <= visibleEndDay else { continue }

            let startColumn = calendar.dateComponents([.day], from: weekStart, to: visibleStartDay).day ?? 0
            let endColumn = calendar.dateComponents([.day], from: weekStart, to: visibleEndDay).day ?? 0
            guard (0..<7).contains(startColumn), (0..<7).contains(endColumn), startColumn <= endColumn else { continue }

            candidates.append(
                Candidate(
                    event: event,
                    startColumn: startColumn,
                    endColumn: endColumn,
                    continuesBeforeWeek: eventStartDay < weekStart,
                    continuesAfterWeek: eventEndDay > weekLastDay
                )
            )
        }

        if candidates.isEmpty {
            return .empty
        }

        let sortedCandidates = candidates.sorted { lhs, rhs in
            if lhs.startColumn != rhs.startColumn {
                return lhs.startColumn < rhs.startColumn
            }
            let lhsSpan = lhs.endColumn - lhs.startColumn
            let rhsSpan = rhs.endColumn - rhs.startColumn
            if lhsSpan != rhsSpan {
                return lhsSpan > rhsSpan
            }
            if lhs.event.isAllDay != rhs.event.isAllDay {
                return lhs.event.isAllDay && rhs.event.isAllDay == false
            }
            let leftStart = lhs.event.displayStartDate(calendar: calendar), rightStart = rhs.event.displayStartDate(calendar: calendar)
            if leftStart != rightStart {
                return leftStart < rightStart
            }
            return lhs.event.title < rhs.event.title
        }

        let maxVisibleLanes = max(0, itemLimit - 1)
        var laneEndColumns: [Int] = []
        var visibleSegments: [Segment] = []
        var occupiedVisibleLanesByDay = Array(repeating: Set<Int>(), count: 7)
        var hiddenCountByDay = Array(repeating: 0, count: 7)

        for candidate in sortedCandidates {
            let assignedLane: Int
            if let lane = laneEndColumns.firstIndex(where: { candidate.startColumn > $0 }) {
                assignedLane = lane
                laneEndColumns[lane] = candidate.endColumn
            } else {
                assignedLane = laneEndColumns.count
                laneEndColumns.append(candidate.endColumn)
            }

            if assignedLane < maxVisibleLanes {
                for dayIndex in candidate.startColumn...candidate.endColumn {
                    occupiedVisibleLanesByDay[dayIndex].insert(assignedLane)
                }
                visibleSegments.append(
                    Segment(
                        id: "\(weekStart.timeIntervalSince1970)-\(candidate.event.id.uuidString)-\(assignedLane)",
                        event: candidate.event,
                        lane: assignedLane,
                        startColumn: candidate.startColumn,
                        endColumn: candidate.endColumn,
                        continuesBeforeWeek: candidate.continuesBeforeWeek,
                        continuesAfterWeek: candidate.continuesAfterWeek
                    )
                )
            } else {
                for dayIndex in candidate.startColumn...candidate.endColumn {
                    hiddenCountByDay[dayIndex] += 1
                }
            }
        }

        let visibleLaneCount = min(laneEndColumns.count, maxVisibleLanes)
        let dayStates = (0..<7).map { index in
            CalendarDayMultiDayState(
                visibleLaneCount: visibleLaneCount,
                occupiedVisibleLanes: occupiedVisibleLanesByDay[index],
                hiddenMultiDayCount: hiddenCountByDay[index]
            )
        }

        return Week(
            visibleLaneCount: visibleLaneCount,
            dayStates: dayStates,
            segments: visibleSegments
        )
    }

    static func rows<Item>(regularItems: [Item], itemLimit: Int,
                           multiDayState: CalendarDayMultiDayState) -> [Row<Item>] {
        guard itemLimit > 0 else { return [] }
        let regularItemCount = regularItems.count
        var rows = Array(repeating: Row<Item>.empty, count: itemLimit)
        var availableRows: [Int] = []
        for rowIndex in 0..<itemLimit {
            if rowIndex < multiDayState.visibleLaneCount && multiDayState.occupiedVisibleLanes.contains(rowIndex) {
                rows[rowIndex] = .multiDayPlaceholder
            } else {
                availableRows.append(rowIndex)
            }
        }
        guard !availableRows.isEmpty else { return rows }

        let needsOverflowRow = multiDayState.hiddenMultiDayCount > 0 || regularItemCount > availableRows.count
        let regularCapacity = availableRows.count - (needsOverflowRow ? 1 : 0)
        let displayedCount = min(regularItemCount, regularCapacity)
        for index in 0..<displayedCount {
            rows[availableRows[index]] = .item(regularItems[index])
        }
        let overflowCount = multiDayState.hiddenMultiDayCount + max(0, regularItemCount - displayedCount)
        if overflowCount > 0, availableRows.indices.contains(displayedCount) {
            rows[availableRows[displayedCount]] = .overflow(overflowCount)
        }
        return rows
    }
}

extension CalendarPreviewLayout.Row: Equatable where Item: Equatable {}
