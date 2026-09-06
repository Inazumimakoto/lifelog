import SwiftUI
import WidgetKit

/// docs/ui-guidelines.md: 予定ウィジェット（中サイズ）。月全体の予定の有無を点で示す。
struct ScheduleMonthCalendarView: View {
    @Environment(\.locale) private var locale
    let month: ScheduleMonth
    let today: Date

    private var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = month.calendar
        formatter.timeZone = month.calendar.timeZone
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                ForEach(month.weekdayNumbers, id: \.self) { weekday in
                    Text(formatter.veryShortStandaloneWeekdaySymbols[weekday - 1])
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(weekdayColor(weekday))
                        .frame(maxWidth: .infinity)
                }
            }
            // Align weekdays with the agenda date; use the remaining height for every week.
            .frame(height: 19)
            .accessibilityHidden(true)

            GeometryReader { geometry in
                let rowHeight = geometry.size.height / CGFloat(max(month.weekCount, 1))
                let diameter = min(20, max(12, rowHeight - 3))

                VStack(spacing: 0) {
                    ForEach(0..<month.weekCount, id: \.self) { week in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { weekday in
                                if let date = month.dates[week * 7 + weekday] {
                                    dayLink(date, diameter: diameter)
                                } else {
                                    Color.clear
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .frame(height: rowHeight)
                    }
                }
            }
        }
    }

    private func dayLink(_ date: Date, diameter: CGFloat) -> some View {
        let isToday = month.calendar.isDate(date, inSameDayAs: today)
        let hasEvents = month.daysWithEvents.contains(date)
        return Link(destination: CalendarDayLink.url(for: date, timeZone: month.calendar.timeZone)) {
            VStack(spacing: 0) {
                Text(dayNumber(date))
                    .font(.system(size: 10, weight: isToday ? .bold : .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color.white : weekdayColor(month.calendar.component(.weekday, from: date)))
                    .fixedSize()
                    .frame(maxWidth: .infinity)
                    .frame(height: diameter)
                    .background {
                        if isToday {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: diameter, height: diameter)
                        }
                    }
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 3)
                    .opacity(hasEvents ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: date, isToday: isToday, hasEvents: hasEvents))
        .accessibilityHint(Text("この日の予定を開く"))
    }

    private func weekdayColor(_ weekday: Int) -> Color {
        switch weekday {
        case 1: return .red.opacity(0.8)
        case 7: return .blue.opacity(0.8)
        default: return .primary.opacity(0.85)
        }
    }

    private func dayNumber(_ date: Date) -> String {
        let formatter = formatter
        formatter.setLocalizedDateFormatFromTemplate("d")
        // Day cells use the locale's numerals without a language-specific date suffix.
        let number = NumberFormatter()
        number.locale = locale
        return number.string(from: NSNumber(value: month.calendar.component(.day, from: date))) ?? formatter.string(from: date)
    }

    private func accessibilityLabel(for date: Date, isToday: Bool, hasEvents: Bool) -> String {
        let formatter = formatter
        formatter.dateStyle = .full
        var parts = [formatter.string(from: date)]
        if isToday { parts.append(String(localized: "今日")) }
        if hasEvents { parts.append(String(localized: "予定あり")) }
        return parts.joined(separator: ", ")
    }
}
