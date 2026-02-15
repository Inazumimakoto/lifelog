//
//  HabitWidget.swift
//  LifelogWidgets
//
//  Rebuilt for scalable weekly habit matrix
//

import WidgetKit
import SwiftUI
import SwiftData

private struct HabitCompletionKey: Hashable {
    let habitID: UUID
    let day: Date
}

struct HabitWidgetModel: Identifiable {
    let id: UUID
    let title: String
    let iconName: String
    let colorHex: String
    let completions: [Bool] // Sun...Sat (7 cells)
}

struct HabitGrassDay: Identifiable {
    let date: Date
    let level: Int // 0...4
    let isToday: Bool

    var id: Date { date }
}

struct HabitEntry: TimelineEntry {
    let date: Date
    let habits: [HabitWidgetModel]
    let grassDays: [HabitGrassDay]
}

struct HabitProvider: TimelineProvider {
    private let grassWeeks = 14
    private typealias GrassThresholds = (q1: Int, q2: Int)

    private struct GrassComputationDay {
        let date: Date
        let scheduledCount: Int
        let completedCount: Int
        let isFuture: Bool
        let isToday: Bool
    }

    private static var widgetCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.firstWeekday = 1 // Sunday start
        return calendar
    }

    func placeholder(in context: Context) -> HabitEntry {
        let calendar = Self.widgetCalendar
        let today = calendar.startOfDay(for: Date())
        let weekStart = startOfWeek(containing: today, calendar: calendar)
        let grassStart = calendar.date(byAdding: .weekOfYear, value: -(grassWeeks - 1), to: weekStart) ?? weekStart

        return HabitEntry(
            date: Date(),
            habits: [
                HabitWidgetModel(
                    id: UUID(),
                    title: "運動",
                    iconName: "figure.run",
                    colorHex: "#22C55E",
                    completions: [true, false, true, false, true, false, false]
                ),
                HabitWidgetModel(
                    id: UUID(),
                    title: "読書",
                    iconName: "book",
                    colorHex: "#3B82F6",
                    completions: [false, true, true, true, false, false, false]
                )
            ],
            grassDays: makePlaceholderGrassDays(start: grassStart, weeks: grassWeeks, today: today, calendar: calendar)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitEntry) -> Void) {
        _Concurrency.Task { @MainActor in
            completion(buildEntry(at: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitEntry>) -> Void) {
        _Concurrency.Task { @MainActor in
            let now = Date()
            let entry = buildEntry(at: now)
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(60 * 30)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    @MainActor
    private func buildEntry(at date: Date) -> HabitEntry {
        do {
            let context = PersistenceController.shared.container.mainContext
            let activeHabitsDesc = FetchDescriptor<SDHabit>(
                predicate: #Predicate<SDHabit> { !$0.isArchived },
                sortBy: [SortDescriptor(\.orderIndex)]
            )
            let activeHabits = try context.fetch(activeHabitsDesc)

            let allHabitsDesc = FetchDescriptor<SDHabit>(
                sortBy: [SortDescriptor(\.createdAt)]
            )
            let allHabits = try context.fetch(allHabitsDesc)

            let calendar = Self.widgetCalendar
            let today = calendar.startOfDay(for: date)
            let weekStart = startOfWeek(containing: today, calendar: calendar)
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart

            let grassStart = calendar.date(byAdding: .weekOfYear, value: -(grassWeeks - 1), to: weekStart) ?? weekStart
            let grassEnd = calendar.date(byAdding: .day, value: grassWeeks * 7, to: grassStart) ?? weekEnd
            let recordsStart = min(weekStart, grassStart)
            let recordsEnd = max(weekEnd, grassEnd)

            let recordsDesc = FetchDescriptor<SDHabitRecord>(
                predicate: #Predicate<SDHabitRecord> {
                    $0.isCompleted && $0.date >= recordsStart && $0.date < recordsEnd
                }
            )
            let records = try context.fetch(recordsDesc)
            let completed = Set(
                records.map {
                    HabitCompletionKey(
                        habitID: $0.habitID,
                        day: calendar.startOfDay(for: $0.date)
                    )
                }
            )

            let habitRows = activeHabits.map { habit in
                let weekCompletions = (0..<7).map { offset in
                    let day = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                    return completed.contains(HabitCompletionKey(habitID: habit.id, day: calendar.startOfDay(for: day)))
                }

                return HabitWidgetModel(
                    id: habit.id,
                    title: habit.title,
                    iconName: habit.iconName,
                    colorHex: habit.colorHex,
                    completions: weekCompletions
                )
            }

            let grassDays = buildGrassDays(
                from: allHabits,
                completed: completed,
                start: grassStart,
                weeks: grassWeeks,
                today: today,
                calendar: calendar
            )

            return HabitEntry(
                date: date,
                habits: habitRows,
                grassDays: grassDays
            )
        } catch {
            return HabitEntry(
                date: date,
                habits: [],
                grassDays: []
            )
        }
    }

    private func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let shift = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -shift, to: day) ?? day
    }

    private func buildGrassDays(
        from habits: [SDHabit],
        completed: Set<HabitCompletionKey>,
        start: Date,
        weeks: Int,
        today: Date,
        calendar: Calendar
    ) -> [HabitGrassDay] {
        guard habits.isEmpty == false else { return [] }

        var daySummaries: [GrassComputationDay] = []
        daySummaries.reserveCapacity(weeks * 7)

        for offset in 0..<(weeks * 7) {
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let day = calendar.startOfDay(for: dayDate)
            let isFuture = day > today

            let activeHabits = habits.filter { isHabit($0, activeOn: day, calendar: calendar) }
            let scheduledHabits = activeHabits.filter { $0.scheduleIsActive(on: day) }
            let completedCount = scheduledHabits.reduce(into: 0) { partial, habit in
                let key = HabitCompletionKey(habitID: habit.id, day: day)
                if completed.contains(key) {
                    partial += 1
                }
            }

            daySummaries.append(
                GrassComputationDay(
                    date: day,
                    scheduledCount: scheduledHabits.count,
                    completedCount: completedCount,
                    isFuture: isFuture,
                    isToday: calendar.isDate(day, inSameDayAs: today)
                )
            )
        }

        let partialNonZeroCounts = daySummaries.compactMap { day -> Int? in
            guard day.isFuture == false else { return nil }
            guard day.scheduledCount > 0 else { return nil }
            guard day.completedCount > 0 else { return nil }
            guard day.completedCount < day.scheduledCount else { return nil }
            return day.completedCount
        }
        .sorted()

        let thresholds: GrassThresholds = (
            q1: nearestRankPercentile(25, in: partialNonZeroCounts),
            q2: nearestRankPercentile(50, in: partialNonZeroCounts)
        )

        return daySummaries.map { day in
            HabitGrassDay(
                date: day.date,
                level: grassLevel(
                    scheduledCount: day.scheduledCount,
                    completedCount: day.completedCount,
                    isFuture: day.isFuture,
                    thresholds: thresholds
                ),
                isToday: day.isToday
            )
        }
    }

    private func isHabit(_ habit: SDHabit, activeOn day: Date, calendar: Calendar) -> Bool {
        let createdDay = calendar.startOfDay(for: habit.createdAt)
        guard createdDay <= day else { return false }

        if let archivedAt = habit.archivedAt {
            let archivedDay = calendar.startOfDay(for: archivedAt)
            return day < archivedDay
        }
        return true
    }

    private func grassLevel(
        scheduledCount: Int,
        completedCount: Int,
        isFuture: Bool,
        thresholds: GrassThresholds
    ) -> Int {
        if isFuture { return 0 }
        guard scheduledCount > 0 else { return 0 }
        guard completedCount > 0 else { return 0 }
        if completedCount == scheduledCount { return 4 }

        if completedCount <= thresholds.q1 { return 1 }
        if completedCount <= thresholds.q2 { return 2 }
        return 3
    }

    private func nearestRankPercentile(_ percentile: Int, in sortedValues: [Int]) -> Int {
        guard sortedValues.isEmpty == false else { return 1 }
        let p = Double(percentile) / 100.0
        let rank = max(1, Int(ceil(Double(sortedValues.count) * p)))
        return sortedValues[min(rank - 1, sortedValues.count - 1)]
    }

    private func makePlaceholderGrassDays(
        start: Date,
        weeks: Int,
        today: Date,
        calendar: Calendar
    ) -> [HabitGrassDay] {
        let pattern = [0, 1, 2, 3, 4, 2, 1]
        return (0..<(weeks * 7)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let day = calendar.startOfDay(for: date)
            let isFuture = day > today

            return HabitGrassDay(
                date: day,
                level: isFuture ? 0 : pattern[offset % pattern.count],
                isToday: calendar.isDate(day, inSameDayAs: today)
            )
        }
    }
}

private struct HabitWidgetLayoutMetrics {
    let family: WidgetFamily
    let habitCount: Int
    let size: CGSize

    var horizontalPadding: CGFloat {
        family == .systemSmall ? 6 : 8
    }

    var verticalPadding: CGFloat {
        family == .systemSmall ? 6 : 8
    }

    var leadingColumnWidth: CGFloat {
        family == .systemSmall ? 16 : 20
    }

    var columnSpacing: CGFloat {
        family == .systemSmall ? 3 : 4
    }

    var sectionSpacing: CGFloat {
        family == .systemSmall ? 4 : 6
    }

    var rowSpacing: CGFloat {
        if habitCount >= 10 { return 1 }
        return family == .systemSmall ? 2 : 3
    }

    var headerHeight: CGFloat {
        family == .systemSmall ? 12 : 14
    }

    var dayFontSize: CGFloat {
        family == .systemSmall ? 8.5 : 9.5
    }

    var emptyFontSize: CGFloat {
        family == .systemSmall ? 10 : 11
    }

    var rowHeight: CGFloat {
        let contentHeight = size.height
            - (verticalPadding * 2)
            - sectionSpacing
            - headerHeight
            - (rowSpacing * CGFloat(max(habitCount - 1, 0)))
        return max(6, floor(contentHeight / CGFloat(max(habitCount, 1))))
    }

    var iconSize: CGFloat {
        max(7, min(rowHeight * 0.62, family == .systemSmall ? 12 : 14))
    }

    var checkSize: CGFloat {
        max(6, min(rowHeight * 0.72, family == .systemSmall ? 12 : 14))
    }
}

private struct HabitMediumSplitMetrics {
    let size: CGSize

    var outerPadding: CGFloat { 8 }
    var columnSpacing: CGFloat { 8 }

    var contentWidth: CGFloat {
        max(0, size.width - (outerPadding * 2))
    }

    var leftWidth: CGFloat {
        floor(max(0, contentWidth - columnSpacing) * 0.5)
    }

    var rightWidth: CGFloat {
        max(0, contentWidth - columnSpacing - leftWidth)
    }

    var panelHeight: CGFloat {
        max(0, size.height - (outerPadding * 2))
    }
}

private struct HabitGrassLayoutMetrics {
    let size: CGSize
    let availableWeekCount: Int

    var columnSpacing: CGFloat { 2 }
    var rowSpacing: CGFloat { 2 }

    var weekCount: Int {
        guard availableWeekCount > 0 else { return 0 }

        let heightBased = (
            (size.height - CGFloat(6) * rowSpacing) / 7.0
        )
        let widthFit = Int(
            floor((size.width + columnSpacing) / max(1, heightBased + columnSpacing))
        )

        return max(1, min(availableWeekCount, widthFit))
    }

    var cellSize: CGFloat {
        let widthBased = (
            (size.width - CGFloat(max(weekCount - 1, 0)) * columnSpacing) / CGFloat(max(weekCount, 1))
        )
        let heightBased = (
            (size.height - CGFloat(6) * rowSpacing) / 7.0
        )
        return max(4, min(widthBased, heightBased))
    }

    var cornerRadius: CGFloat {
        max(1.2, min(2.4, cellSize * 0.2))
    }
}

private struct HabitCheckCell: View {
    let isCompleted: Bool
    let color: Color
    let colorScheme: ColorScheme
    let size: CGFloat

    private var checkmarkColor: Color {
        colorScheme == .dark ? .black : .white
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.35), lineWidth: max(0.8, size * 0.09))
            if isCompleted {
                Circle()
                    .fill(color)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(checkmarkColor)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct HabitGrassGridView: View {
    let days: [HabitGrassDay]
    let panelSize: CGSize
    let colorScheme: ColorScheme

    var body: some View {
        let allWeeks = chunkedWeeks(from: days)
        let metrics = HabitGrassLayoutMetrics(size: panelSize, availableWeekCount: allWeeks.count)
        let weeks = Array(allWeeks.suffix(metrics.weekCount))

        if weeks.isEmpty {
            Text("草データなし")
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            HStack(alignment: .top, spacing: metrics.columnSpacing) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: metrics.rowSpacing) {
                        ForEach(week) { day in
                            RoundedRectangle(cornerRadius: metrics.cornerRadius)
                                .fill(color(for: day.level))
                                .frame(width: metrics.cellSize, height: metrics.cellSize)
                                .overlay(
                                    RoundedRectangle(cornerRadius: metrics.cornerRadius)
                                        .stroke(
                                            day.isToday ? todayStrokeColor : .clear,
                                            lineWidth: day.isToday ? 1.1 : 0
                                        )
                                )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var todayStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.95) : Color.black.opacity(0.45)
    }

    private func color(for level: Int) -> Color {
        let clampedLevel = max(0, min(4, level))
        return githubPalette[clampedLevel]
    }

    private var githubPalette: [Color] {
        if colorScheme == .dark {
            return [
                Color(hex: "#161b22") ?? Color(red: 0.09, green: 0.11, blue: 0.13),
                Color(hex: "#0e4429") ?? Color(red: 0.05, green: 0.27, blue: 0.16),
                Color(hex: "#006d32") ?? Color(red: 0.00, green: 0.43, blue: 0.20),
                Color(hex: "#26a641") ?? Color(red: 0.15, green: 0.65, blue: 0.25),
                Color(hex: "#39d353") ?? Color(red: 0.22, green: 0.83, blue: 0.33)
            ]
        }

        return [
            Color(hex: "#ebedf0") ?? Color(red: 0.92, green: 0.93, blue: 0.94),
            Color(hex: "#9be9a8") ?? Color(red: 0.61, green: 0.91, blue: 0.66),
            Color(hex: "#40c463") ?? Color(red: 0.25, green: 0.77, blue: 0.39),
            Color(hex: "#30a14e") ?? Color(red: 0.19, green: 0.63, blue: 0.31),
            Color(hex: "#216e39") ?? Color(red: 0.13, green: 0.43, blue: 0.22)
        ]
    }

    private func chunkedWeeks(from days: [HabitGrassDay]) -> [[HabitGrassDay]] {
        guard days.isEmpty == false else { return [] }
        let sorted = days.sorted { $0.date < $1.date }
        var weeks: [[HabitGrassDay]] = []
        var index = 0

        while index < sorted.count {
            let end = min(index + 7, sorted.count)
            let slice = Array(sorted[index..<end])
            if slice.count == 7 {
                weeks.append(slice)
            }
            index += 7
        }

        return weeks
    }
}

struct HabitWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    var entry: HabitProvider.Entry

    private let dayLabels = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        GeometryReader { proxy in
            if family == .systemMedium {
                mediumContent(size: proxy.size)
            } else {
                let metrics = HabitWidgetLayoutMetrics(
                    family: .systemSmall,
                    habitCount: max(entry.habits.count, 1),
                    size: proxy.size
                )
                checklistContent(metrics: metrics)
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.vertical, metrics.verticalPadding)
            }
        }
    }

    private func mediumContent(size: CGSize) -> some View {
        let split = HabitMediumSplitMetrics(size: size)
        let displayHabitCount = max(entry.habits.count, 1)
        let leftMetrics = HabitWidgetLayoutMetrics(
            family: .systemSmall,
            habitCount: displayHabitCount,
            size: CGSize(width: split.leftWidth, height: split.panelHeight)
        )
        let rowTopInset = leftMetrics.headerHeight + leftMetrics.sectionSpacing
        let rowBlockHeight = (leftMetrics.rowHeight * CGFloat(displayHabitCount))
            + (leftMetrics.rowSpacing * CGFloat(max(displayHabitCount - 1, 0)))

        return HStack(alignment: .top, spacing: split.columnSpacing) {
            checklistContent(metrics: leftMetrics)
                .frame(width: split.leftWidth, height: split.panelHeight, alignment: .topLeading)

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: rowTopInset)

                HabitGrassGridView(
                    days: entry.grassDays,
                    panelSize: CGSize(width: split.rightWidth, height: rowBlockHeight),
                    colorScheme: colorScheme
                )
                .frame(height: rowBlockHeight, alignment: .topLeading)

                Spacer(minLength: 0)
            }
            .frame(width: split.rightWidth, height: split.panelHeight, alignment: .top)
        }
        .padding(.horizontal, split.outerPadding)
        .padding(.vertical, split.outerPadding)
    }

    private func checklistContent(metrics: HabitWidgetLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            dayHeader(metrics: metrics)

            if entry.habits.isEmpty {
                Text("習慣がありません")
                    .font(.system(size: metrics.emptyFontSize, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                    ForEach(entry.habits) { habit in
                        habitRow(habit: habit, metrics: metrics)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func dayHeader(metrics: HabitWidgetLayoutMetrics) -> some View {
        HStack(spacing: metrics.columnSpacing) {
            Spacer().frame(width: metrics.leadingColumnWidth)
            ForEach(dayLabels, id: \.self) { day in
                Text(day)
                    .font(.system(size: metrics.dayFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: metrics.headerHeight)
    }

    private func habitRow(habit: HabitWidgetModel, metrics: HabitWidgetLayoutMetrics) -> some View {
        HStack(spacing: metrics.columnSpacing) {
            Image(systemName: habit.iconName)
                .font(.system(size: metrics.iconSize, weight: .semibold))
                .foregroundStyle(Color(hex: habit.colorHex) ?? .accentColor)
                .frame(width: metrics.leadingColumnWidth, height: metrics.rowHeight)

            ForEach(0..<7, id: \.self) { index in
                let completed = index < habit.completions.count ? habit.completions[index] : false
                HabitCheckCell(
                    isCompleted: completed,
                    color: Color(hex: habit.colorHex) ?? .accentColor,
                    colorScheme: colorScheme,
                    size: metrics.checkSize
                )
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: metrics.rowHeight)
    }
}

private extension Color {
    init?(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard let value = UInt64(sanitized, radix: 16) else { return nil }

        let r, g, b: Double
        switch sanitized.count {
        case 3:
            r = Double((value >> 8) & 0xF) / 15
            g = Double((value >> 4) & 0xF) / 15
            b = Double(value & 0xF) / 15
        case 6:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        default:
            return nil
        }

        self.init(red: r, green: g, blue: b)
    }
}

struct HabitWidget: Widget {
    let kind: String = "HabitWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HabitProvider()) { entry in
            if #available(iOS 17.0, *) {
                HabitWidgetEntryView(entry: entry)
                    .containerBackground(Color(uiColor: .systemBackground), for: .widget)
            } else {
                HabitWidgetEntryView(entry: entry)
                    .background(Color(uiColor: .systemBackground))
            }
        }
        .configurationDisplayName("週間習慣チェック")
        .description("小: 週間チェック / 中: 週間チェック + 草表示")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
