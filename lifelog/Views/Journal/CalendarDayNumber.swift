import SwiftUI

struct CalendarDayNumber: View {
    let date: Date
    let calendar: Calendar
    let isToday: Bool
    let isInMonth: Bool
    var overPhoto = false
    let font: Font

    var textColor: Color {
        if overPhoto { return .white }
        return isInMonth && !calendar.isDateInWeekend(date) ? .primary : .secondary
    }

    var body: some View {
        Text(calendar.component(.day, from: date), format: .number)
            .font(font)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(textColor)
            .accessibilityValue(isToday ? Text("今日") : Text(""))
    }
}
