import Foundation

/// Calendar dates and event indicators for the schedule widget (docs/requirements.md §4.11).
struct ScheduleMonth {
    let calendar: Calendar
    let monthStart: Date
    let dates: [Date?]
    let weekdayNumbers: [Int]
    let daysWithEvents: Set<Date>

    var weekCount: Int { dates.count / 7 }

    init(
        containing date: Date,
        eventIntervals: [DateInterval] = [],
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.calendar = calendar
        weekdayNumbers = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }

        guard let month = calendar.dateInterval(of: .month, for: date) else {
            monthStart = calendar.startOfDay(for: date)
            dates = []
            daysWithEvents = []
            return
        }

        monthStart = month.start
        let leadingDays = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        var grid: [Date?] = Array(repeating: nil, count: leadingDays)
        var day = calendar.startOfDay(for: month.start)
        while day < month.end {
            grid.append(day)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day), nextDay > day else {
                break
            }
            day = calendar.startOfDay(for: nextDay)
        }
        grid.append(contentsOf: Array(repeating: nil, count: (7 - grid.count % 7) % 7))
        dates = grid

        var occupiedDays: Set<Date> = []
        for interval in eventIntervals {
            // Events use an exclusive end: an all-day event does not mark the following midnight.
            let start = max(interval.start, month.start)
            let end = min(interval.end, month.end)
            guard start < end else { continue }

            var eventDay = calendar.startOfDay(for: start)
            while eventDay < end {
                occupiedDays.insert(eventDay)
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: eventDay), nextDay > eventDay else {
                    break
                }
                eventDay = calendar.startOfDay(for: nextDay)
            }
        }
        daysWithEvents = occupiedDays
    }
}
