import SwiftUI

struct CalendarScheduleDay: Identifiable {
    var id: Date { date }
    let date: Date
    let events: [CalendarEvent]
    let tasks: [Task]
    var isWithinDisplayedMonth = true
}

/// The journal and its settings preview use the same schedule cells and multi-day spans (§4.2).
struct CalendarScheduleGrid<Selection: View>: View {
    @ObservedObject private var palette = CategoryPaletteObserver.shared
    @Environment(\.appTheme) private var theme
    @Environment(\.self) private var environment
    let days: [CalendarScheduleDay]
    let calendar: Calendar
    let preferences: CalendarDisplayPreferences
    var onSelect: ((Date) -> Void)?
    @ViewBuilder let selection: (CalendarScheduleDay, Color) -> Selection

    private var metrics: CalendarGridMetrics { CalendarGridMetrics(fontSize: preferences.fontSize) }

    var body: some View {
        let spacing = CalendarGridMetrics.gridSpacing
        let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: 7)
        let surface = CalendarGridSurface.color(theme: theme, in: environment)
        let highlight = CalendarGridSurface.selectionOutline(theme?.accent ?? .accentColor, on: surface, in: environment)
        let weeks = stride(from: 0, to: days.count, by: 7).map { start in
            weekLayout(for: days[start..<min(start + 7, days.count)])
        }
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                let state = weeks[index / 7].dayStates[index % 7]
                let cell = dayCell(day, state: state)
                    .overlay { selection(day, highlight) }
                if let onSelect {
                    cell.contentShape(Rectangle()).onTapGesture { onSelect(day.date) }
                } else {
                    cell
                }
            }
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                multiDayOverlay(weeks: weeks, width: geometry.size.width)
            }
            .allowsHitTesting(false)
        }
        .background { CalendarGridSurface().padding(-2) }
    }

    private func weekLayout(for days: ArraySlice<CalendarScheduleDay>) -> CalendarPreviewLayout.Week {
        var uniqueEvents: [UUID: CalendarEvent] = [:]
        for day in days {
            for event in day.events where CalendarPreviewLayout.isMultiDayEvent(event, calendar: calendar) {
                uniqueEvents[event.id] = event
            }
        }
        return CalendarPreviewLayout.week(dates: days.map(\.date), events: Array(uniqueEvents.values),
                                          itemLimit: metrics.laneCount, calendar: calendar)
    }

    private func dayCell(_ day: CalendarScheduleDay, state: CalendarDayMultiDayState) -> some View {
        let isToday = calendar.isDateInToday(day.date)
        let singleDayEvents = day.events.filter { !CalendarPreviewLayout.isMultiDayEvent($0, calendar: calendar) }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.displayStartDate(calendar: calendar) < rhs.displayStartDate(calendar: calendar)
            }
        let tasks = day.tasks.sorted { TaskPresentation.orderedBefore($0, $1, preferring: .start, calendar: calendar) }
        let items = singleDayEvents.map { (title: $0.title, color: CategoryPalette.color(for: $0.calendarName)) }
            + tasks.map { (title: $0.title, color: $0.priority.color) }
        let rows = CalendarPreviewLayout.rows(regularItems: items, itemLimit: metrics.laneCount, multiDayState: state)
        return VStack(alignment: .leading, spacing: CalendarGridMetrics.rowSpacing) {
            CalendarDayNumber(date: day.date, calendar: calendar, isToday: isToday,
                              isInMonth: day.isWithinDisplayedMonth, font: .subheadline.weight(.semibold))
                .padding(.horizontal, 4)
                .frame(height: CalendarGridMetrics.dateHeight)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                switch row {
                case .multiDayPlaceholder, .empty:
                    Color.clear.frame(height: metrics.rowHeight)
                case .overflow(let count):
                    Text("+\(count)")
                        .font(.system(size: preferences.fontSize))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: metrics.rowHeight)
                case .item(let item):
                    CalendarPreviewBar(title: item.title, color: item.color, preferences: preferences)
                }
            }
        }
        .padding(.top, CalendarGridMetrics.topPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: CalendarGridMetrics.cellHeight, alignment: .topLeading)
        .mask(Rectangle().padding(.horizontal, -20))
        .background {
            if isToday {
                RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.12))
            }
        }
    }

    @ViewBuilder
    private func multiDayOverlay(weeks: [CalendarPreviewLayout.Week], width: CGFloat) -> some View {
        let spacing = CalendarGridMetrics.gridSpacing
        let cellWidth = (width - 6 * spacing) / 7
        if cellWidth > 0 {
            ZStack(alignment: .topLeading) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { weekIndex, week in
                    ForEach(week.segments) { segment in
                        let span = CGFloat(segment.endColumn - segment.startColumn + 1)
                        // Repeat the label at the week boundary when the fill is invisible.
                        let title = segment.continuesBeforeWeek && preferences.opacity > 0 ? "" : segment.event.title
                        CalendarPreviewBar(title: title, color: CategoryPalette.color(for: segment.event.calendarName),
                                           preferences: preferences, continuesBefore: segment.continuesBeforeWeek,
                                           continuesAfter: segment.continuesAfterWeek)
                            .frame(width: span * cellWidth + (span - 1) * spacing, height: metrics.rowHeight)
                            .offset(x: CGFloat(segment.startColumn) * (cellWidth + spacing),
                                    y: CGFloat(weekIndex) * (CalendarGridMetrics.cellHeight + spacing)
                                       + metrics.rowOffset(for: segment.lane))
                    }
                }
            }
        }
    }
}
