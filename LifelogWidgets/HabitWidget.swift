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

struct HabitEntry: TimelineEntry {
    let date: Date
    let habits: [HabitWidgetModel]
}

struct HabitProvider: TimelineProvider {
    private static var widgetCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.firstWeekday = 1 // Sunday start
        return calendar
    }

    func placeholder(in context: Context) -> HabitEntry {
        HabitEntry(
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
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitEntry) -> Void) {
        _Concurrency.Task { @MainActor in
            completion(HabitEntry(date: Date(), habits: fetchHabits()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitEntry>) -> Void) {
        _Concurrency.Task { @MainActor in
            let now = Date()
            let entry = HabitEntry(date: now, habits: fetchHabits())
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(60 * 30)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    @MainActor
    private func fetchHabits() -> [HabitWidgetModel] {
        do {
            let context = PersistenceController.shared.container.mainContext
            let habitsDesc = FetchDescriptor<SDHabit>(
                predicate: #Predicate<SDHabit> { !$0.isArchived },
                sortBy: [SortDescriptor(\.orderIndex)]
            )
            let habits = try context.fetch(habitsDesc)
            guard habits.isEmpty == false else { return [] }

            let calendar = Self.widgetCalendar
            let today = calendar.startOfDay(for: Date())
            let weekStart = startOfWeek(containing: today, calendar: calendar)
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart

            let recordsDesc = FetchDescriptor<SDHabitRecord>(
                predicate: #Predicate<SDHabitRecord> {
                    $0.isCompleted && $0.date >= weekStart && $0.date < weekEnd
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

            return habits.map { habit in
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
        } catch {
            return []
        }
    }

    private func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let shift = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -shift, to: day) ?? day
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

struct HabitWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    var entry: HabitProvider.Entry

    private let dayLabels = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        GeometryReader { proxy in
            let metrics = HabitWidgetLayoutMetrics(
                family: family,
                habitCount: max(entry.habits.count, 1),
                size: proxy.size
            )

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
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
        }
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
        .description("日〜土の習慣チェックを一覧表示します。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
