import SwiftUI

struct CalendarDisplaySettingsView: View {
    @AppStorage(CalendarDisplayPreferences.fontSizeKey) private var storedFontSize = CalendarDisplayPreferences.defaultFontSize
    @AppStorage(CalendarDisplayPreferences.opacityKey) private var storedOpacity = CalendarDisplayPreferences.defaultOpacity

    private var preferences: CalendarDisplayPreferences {
        CalendarDisplayPreferences(fontSize: storedFontSize, opacity: storedOpacity)
    }

    private var hasCustomValues: Bool {
        preferences.fontSize != CGFloat(CalendarDisplayPreferences.defaultFontSize)
            || (preferences.opacity * 100).rounded() != (CalendarDisplayPreferences.defaultOpacity * 100).rounded()
    }

    var body: some View {
        Form {
            Section("calendar.display.preview") {
                CurrentWeekCalendarPreview(preferences: preferences)
                    .padding(.vertical, 6)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .listRowBackground(CalendarGridSurface())
            }

            Section("calendar.display.appliesTo") {
                Stepper(value: Binding(get: { Double(preferences.fontSize) }, set: { storedFontSize = $0 }),
                        in: CalendarDisplayPreferences.fontSizeRange, step: 1) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("calendar.display.fontSize")
                        Text("calendar.display.pointValue \(Int(preferences.fontSize.rounded()))")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("calendar.display.categoryOpacity") {
                        Text(preferences.opacity, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                    .accessibilityHidden(true)

                    Slider(value: Binding(get: { preferences.opacity }, set: { storedOpacity = ($0 * 100).rounded() / 100 }),
                           in: CalendarDisplayPreferences.opacityRange, step: 0.01) {
                        Text("calendar.display.categoryOpacity")
                    }
                    .accessibilityValue(Text(preferences.opacity, format: .percent.precision(.fractionLength(0))))
                }
                .padding(.vertical, 4)

                if hasCustomValues {
                    Button("calendar.display.restoreDefaults") {
                        storedFontSize = CalendarDisplayPreferences.defaultFontSize
                        storedOpacity = CalendarDisplayPreferences.defaultOpacity
                    }
                }
            }
        }
        .appThemeBackground()
        .navigationTitle("calendar.display.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CurrentWeekCalendarPreview: View {
    @EnvironmentObject private var store: AppDataStore
    @AppStorage(CalendarWeekStart.storageKey, store: CalendarWeekStart.defaults)
    private var weekStartRawValue = CalendarWeekStart.sunday.rawValue
    @State private var now = Date()
    let preferences: CalendarDisplayPreferences

    var body: some View {
        let weekStart = CalendarWeekStart(rawValue: weekStartRawValue) ?? .sunday
        let calendar = weekStart.calendar
        let dates = JournalViewModel.weekDates(containing: now, calendar: calendar)
        let days = schedule(for: dates, calendar: calendar)
        VStack(spacing: 4) {
            CalendarScheduleWeekdayHeader(weekStart: weekStart, calendar: calendar)
            CalendarScheduleGrid(days: days, calendar: calendar, preferences: preferences) { _, _ in EmptyView() }
                .overlay {
                    if days.allSatisfy({ $0.events.isEmpty && $0.tasks.isEmpty }) {
                        Text("calendar.display.emptyWeek")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, CalendarGridMetrics.topPadding + CalendarGridMetrics.dateHeight)
                    }
                }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            now = Date()
        }
    }

    private func schedule(for dates: [Date], calendar: Calendar) -> [CalendarScheduleDay] {
        let week = Set(dates.map { calendar.startOfDay(for: $0) })
        var tasksByDay: [Date: [Task]] = [:]
        for task in store.tasks {
            guard let deadline = TaskPresentation.displayDate(for: task, preferring: .deadline, calendar: calendar) else { continue }
            let day = calendar.startOfDay(for: deadline)
            if week.contains(day) { tasksByDay[day, default: []].append(task) }
        }
        return dates.map { day in
            CalendarScheduleDay(date: day, events: store.events(on: day), tasks: tasksByDay[calendar.startOfDay(for: day)] ?? [])
        }
    }
}
