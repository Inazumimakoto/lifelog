import SwiftUI

struct CalendarScheduleWeekdayHeader: View {
    let weekStart: CalendarWeekStart
    let calendar: Calendar

    var body: some View {
        let weekdays = weekStart.weekdaySymbols(in: calendar)
        HStack(spacing: CalendarGridMetrics.gridSpacing) {
            ForEach(Array(weekdays.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
