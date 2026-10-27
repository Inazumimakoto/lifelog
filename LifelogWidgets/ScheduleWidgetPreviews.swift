import SwiftUI
import WidgetKit

#if DEBUG
enum ScheduleWidgetPreviewData {
    static func entry(month: Int = 9, day: Int = 6, empty: Bool = false,
                      includeOverdue: Bool = false, overdueOnly: Bool = false) -> ScheduleEntry {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let date = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 9))!
        let meeting = ScheduleEventItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: String(localized: "チームMTG"),
            startDate: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: date)!,
            endDate: calendar.date(bySettingHour: 11, minute: 0, second: 0, of: date)!,
            isAllDay: false,
            categoryName: "仕事"
        )
        let intervals: [DateInterval] = empty ? [] : [0, 2, 5, 9, 12, 16].map { offset in
            let start = calendar.date(byAdding: .day, value: offset, to: meeting.startDate)!
            return DateInterval(start: start, duration: 3600)
        }
        let todayTasks: [ScheduleTaskItem] = empty || overdueOnly ? [] : [
            ScheduleTaskItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, title: String(localized: "週次レポート提出"), priority: .high),
            ScheduleTaskItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, title: String(localized: "買い物メモ整理"), priority: .medium)
        ]
        let overdueTasks: [ScheduleTaskItem] = !empty && (includeOverdue || overdueOnly) ? [
            ScheduleTaskItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                             title: String(localized: "週次レポート提出"), priority: .high,
                             dueDate: calendar.date(byAdding: .day, value: -1, to: date), isOverdue: true),
            ScheduleTaskItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
                             title: String(localized: "買い物メモ整理"), priority: .medium,
                             dueDate: calendar.date(byAdding: .day, value: -5, to: date), isOverdue: true)
        ] : []
        return ScheduleEntry(
            date: date,
            events: empty || overdueOnly ? [] : [meeting],
            tasks: todayTasks + overdueTasks,
            nextInlineEvent: empty || overdueOnly ? nil : meeting,
            isPremiumUnlocked: true,
            month: ScheduleMonth(containing: date, eventIntervals: intervals, calendar: calendar)
        )
    }
}

#Preview("Medium", as: .systemMedium) {
    ScheduleWidget()
} timeline: {
    ScheduleWidgetPreviewData.entry()
}

#Preview("Medium · six weeks", as: .systemMedium) {
    ScheduleWidget()
} timeline: {
    ScheduleWidgetPreviewData.entry(month: 8)
}

#Preview("Medium · empty", as: .systemMedium) {
    ScheduleWidget()
} timeline: {
    ScheduleWidgetPreviewData.entry(empty: true)
}

#Preview("Small · overdue", as: .systemSmall) {
    ScheduleWidget()
} timeline: {
    ScheduleWidgetPreviewData.entry(includeOverdue: true)
}

#Preview("Medium · overdue", as: .systemMedium) {
    ScheduleWidget()
} timeline: {
    ScheduleWidgetPreviewData.entry(includeOverdue: true)
}

#Preview("Large · overdue only", as: .systemLarge) {
    ScheduleWidget()
} timeline: {
    ScheduleWidgetPreviewData.entry(overdueOnly: true)
}

#Preview("Lock Screen · overdue", as: .accessoryInline) {
    ScheduleWidget()
} timeline: {
    ScheduleWidgetPreviewData.entry(overdueOnly: true)
}
#endif
