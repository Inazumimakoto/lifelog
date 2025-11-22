//
//  HabitDetailView.swift
//  lifelog
//
//  Created by Codex on 2025/11/22.
//

import SwiftUI

struct HabitDetailView: View {
    @ObservedObject var store: AppDataStore
    var habit: Habit

    @State private var highlightedDate: Date?
    @State private var showEditor = false
    private let calendar = Calendar.current

    private var currentHabit: Habit {
        store.habits.first(where: { $0.id == habit.id }) ?? habit
    }

    private var accentColor: Color {
        Color(hex: currentHabit.colorHex) ?? .accentColor
    }

    private var detailCells: [HabitHeatCell] {
        buildCells(days: 84)
    }

    private var recentDates: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (0..<30).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    heatmapSection(proxy: proxy)
                    historySection
                    editButton
                }
                .padding()
            }
        }
        .navigationTitle("習慣詳細")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                HabitEditorView(habit: currentHabit) { updated in
                    store.updateHabit(updated)
                }
            }
        }
    }

    private var headerCard: some View {
        SectionCard {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Label(currentHabit.title, systemImage: currentHabit.iconName)
                        .font(.headline)
                    Text(scheduleDescription(for: currentHabit.schedule))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    streakBadge(title: "連続達成", value: currentStreak())
                    streakBadge(title: "最高ストリーク", value: maxStreak())
                    Text("達成合計 \(totalCompletions()) 回")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func streakBadge(title: String, value: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value) 回")
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func heatmapSection(proxy: ScrollViewProxy) -> some View {
        SectionCard(title: "直近の積み上げ") {
            HabitDetailHeatmapView(cells: detailCells,
                                   accentColor: accentColor) { date in
                highlightedDate = date
                withAnimation {
                    proxy.scrollTo(date, anchor: .center)
                }
            }
            Text("右端が今日。タップした日付は下の履歴で確認・更新できます。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var historySection: some View {
        SectionCard(title: "最近の履歴") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(recentDates, id: \.self) { date in
                    let isScheduled = currentHabit.schedule.isActive(on: date)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(date, formatter: DateFormatter.japaneseYearMonthDay)
                                .font(.subheadline)
                            Text(date.jaWeekdayNarrowString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isScheduled {
                            Button {
                                toggle(date: date)
                            } label: {
                                Image(systemName: isCompleted(on: date) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(isCompleted(on: date) ? accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("予定なし")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .padding(.vertical, 4)
                    .id(date)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(highlightedDate == date ? accentColor.opacity(0.08) : Color.clear)
                    )
                }
            }
        }
    }

    private var editButton: some View {
        Button {
            showEditor = true
        } label: {
            HStack {
                Spacer()
                Label("習慣を編集", systemImage: "square.and.pencil")
                Spacer()
            }
            .padding()
            .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func scheduleDescription(for schedule: HabitSchedule) -> String {
        switch schedule {
        case .daily:
            return "毎日"
        case .weekdays:
            return "平日"
        case .custom(let days):
            let labels = days.sorted { $0.rawValue < $1.rawValue }.map(\.shortLabel)
            return labels.joined(separator: " ")
        }
    }

    private func toggle(date: Date) {
        guard currentHabit.schedule.isActive(on: date) else { return }
        store.toggleHabit(currentHabit.id, on: date)
    }

    private func isCompleted(on date: Date) -> Bool {
        record(on: date)?.isCompleted == true
    }

    private func record(on date: Date) -> HabitRecord? {
        store.habitRecords.first {
            $0.habitID == currentHabit.id && calendar.isDate($0.date, inSameDayAs: date)
        }
    }

    private func buildCells(days: Int) -> [HabitHeatCell] {
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        var cells: [HabitHeatCell] = []
        for offset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let day = calendar.startOfDay(for: date)
            let isActive = currentHabit.schedule.isActive(on: day)
            if isActive == false {
                cells.append(HabitHeatCell(date: day, state: .inactive, isToday: calendar.isDate(day, inSameDayAs: today)))
                continue
            }
            let done = isCompleted(on: day)
            cells.append(HabitHeatCell(date: day,
                                       state: done ? .completed : .pending,
                                       isToday: calendar.isDate(day, inSameDayAs: today)))
        }
        return cells
    }

    private func currentStreak(asOf date: Date = Date()) -> Int {
        let today = calendar.startOfDay(for: date)
        var streak = 0
        var cursor = today

        while true {
            if currentHabit.schedule.isActive(on: cursor) == false {
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = previous
                continue
            }

            guard let record = record(on: cursor), record.isCompleted else {
                break
            }

            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return streak
    }

    private func maxStreak() -> Int {
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -365, to: today) ?? today
        var cursor = start
        var longest = 0
        var running = 0

        while cursor <= today {
            if currentHabit.schedule.isActive(on: cursor) {
                if isCompleted(on: cursor) {
                    running += 1
                    longest = max(longest, running)
                } else {
                    running = 0
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return max(longest, currentStreak())
    }

    private func totalCompletions() -> Int {
        store.habitRecords.filter { $0.habitID == currentHabit.id && $0.isCompleted }.count
    }
}

private struct HabitDetailHeatmapView: View {
    let cells: [HabitHeatCell]
    let accentColor: Color
    let onSelect: (Date) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(cells) { cell in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color(for: cell.state))
                            .frame(width: 14, height: 16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(cell.isToday ? Color.white.opacity(0.9) : .clear, lineWidth: 1.4)
                            )
                            .scaleEffect(cell.isToday ? 1.1 : 1.0)
                            .id(cell.id)
                            .onTapGesture {
                                onSelect(cell.date)
                            }
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear {
                if let last = cells.last {
                    proxy.scrollTo(last.id, anchor: .trailing)
                }
            }
        }
    }

    private func color(for state: HabitHeatCell.State) -> Color {
        switch state {
        case .inactive:
            return Color.gray.opacity(0.22)
        case .pending:
            return Color.secondary.opacity(0.5)
        case .completed:
            return accentColor
        }
    }
}
