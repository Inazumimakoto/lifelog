//
//  HabitsCountdownView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct HabitsCountdownView: View {
    @StateObject private var habitsViewModel: HabitsViewModel
    @StateObject private var anniversaryViewModel: AnniversaryViewModel
    private let store: AppDataStore
    @State private var showHabitEditor = false
    @State private var showAnniversaryEditor = false
    @State private var editingHabit: Habit?
    @State private var editingAnniversary: Anniversary?
    @State private var displayMode: DisplayMode = .habits
    @State private var selectedHabitForDetail: Habit?
    @State private var selectedDaySummary: HabitDaySummary?

    init(store: AppDataStore) {
        self.store = store
        _habitsViewModel = StateObject(wrappedValue: HabitsViewModel(store: store))
        _anniversaryViewModel = StateObject(wrappedValue: AnniversaryViewModel(store: store))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                yearlyHeatmapSection
                modePicker
                if displayMode == .habits {
                    habitsSection
                } else {
                    anniversarySection
                }
            }
            .padding()
        }
        .navigationTitle("習慣とカウントダウン")
        .sheet(isPresented: $showHabitEditor) {
            NavigationStack {
                HabitEditorView { habit in
                    habitsViewModel.addHabit(habit)
                }
            }
        }
        .sheet(isPresented: $showAnniversaryEditor) {
            NavigationStack {
                AnniversaryEditorView { anniversary in
                    anniversaryViewModel.add(anniversary)
                }
            }
        }
        .sheet(item: $editingHabit) { habit in
            NavigationStack {
                HabitEditorView(habit: habit) { updated in
                    habitsViewModel.updateHabit(updated)
                }
            }
        }
        .sheet(item: $editingAnniversary) { anniversary in
            NavigationStack {
                AnniversaryEditorView(anniversary: anniversary) { updated in
                    anniversaryViewModel.update(updated)
                }
            }
        }
        .sheet(item: $selectedDaySummary) { summary in
            HabitDaySummarySheet(summary: summary)
                .presentationDetents([.fraction(0.35), .medium])
        }
        .sheet(isPresented: Binding<Bool>(
            get: { selectedHabitForDetail != nil },
            set: { if $0 == false { selectedHabitForDetail = nil } })
        ) {
            if let habit = selectedHabitForDetail {
                NavigationStack {
                    HabitDetailView(store: store, habit: habit)
                }
            }
        }
    }

    private var yearlyHeatmapSection: some View {
        SectionCard(title: "今年の習慣の積み上げ") {
            if habitsViewModel.yearlySummaries.isEmpty {
                Text("習慣がありません。追加して1年の積み上げを可視化しましょう。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HabitYearHeatmapView(startDate: habitsViewModel.yearStartDate,
                                     weekCount: habitsViewModel.yearWeekCount,
                                     summaries: habitsViewModel.yearlySummaries,
                                     onSelect: { summary in
                                         selectedDaySummary = summary
                                     })
            }
        }
    }

    private var modePicker: some View {
        Picker("表示切替", selection: $displayMode) {
            ForEach(DisplayMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var habitsSection: some View {
        SectionCard(title: "習慣",
                    actionTitle: "追加",
                    action: { showHabitEditor = true }) {
            VStack(alignment: .leading, spacing: 12) {
                Text("行をタップすると詳細。色や曜日は編集からいつでも変更できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("習慣")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)
                    ForEach(habitsViewModel.weekDates, id: \.self) { date in
                        Text(date, format: .dateTime.weekday(.short))
                            .font(.caption2)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.secondary)
                    }
                }
                if habitsViewModel.statuses.isEmpty {
                    Text("まだ習慣がありません。追加して継続状況を可視化しましょう。")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                } else {
                    ForEach(Array(habitsViewModel.statuses.enumerated()), id: \.element.id) { index, status in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                Button {
                                    selectedHabitForDetail = status.habit
                                } label: {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color(hex: status.habit.colorHex) ?? .accentColor)
                                            .frame(width: 10, height: 10)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Label(status.habit.title, systemImage: status.habit.iconName)
                                            Text(scheduleDescription(for: status.habit.schedule))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            Text(statsDescription(for: status.habit))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                Button {
                                    editingHabit = status.habit
                                } label: {
                                    Image(systemName: "square.and.pencil")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            HStack {
                                ForEach(habitsViewModel.weekDates, id: \.self) { date in
                                    Button {
                                        habitsViewModel.toggle(habit: status.habit, on: date)
                                    } label: {
                                        let isActive = status.isActive(on: date)
                                        Image(systemName: symbolName(for: status, on: date, isActive: isActive))
                                            .foregroundStyle(
                                                isActive
                                                ? (status.isCompleted(on: date) ? Color(hex: status.habit.colorHex) ?? .accentColor : .secondary)
                                                : Color.black
                                            )
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(status.isActive(on: date) == false)
                                }
                            }
                            MiniHabitHeatmapView(cells: habitsViewModel.miniHeatmap(for: status.habit),
                                                 accentColor: Color(hex: status.habit.colorHex) ?? .accentColor)
                            .onTapGesture {
                                selectedHabitForDetail = status.habit
                            }
                        }
                        if index < habitsViewModel.statuses.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var anniversarySection: some View {
        SectionCard(title: "記念日 / カウントダウン",
                    actionTitle: "追加",
                    action: { showAnniversaryEditor = true }) {
            if anniversaryViewModel.rows.isEmpty {
                Text("記念日は未登録です")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(anniversaryViewModel.rows.enumerated()), id: \.element.id) { index, row in
                    Button {
                        editingAnniversary = row.anniversary
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(row.anniversary.title)
                                    .font(.headline)
                                Text(row.anniversary.targetDate.jaYearMonthDayString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(row.relativeText)
                                .font(.headline)
                        }
                    }
                    .buttonStyle(.plain)
                    if index < anniversaryViewModel.rows.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }
}

extension HabitsCountdownView {
    enum DisplayMode: String, CaseIterable, Identifiable {
        case habits = "習慣"
        case countdown = "カウントダウン"

        var id: String { rawValue }
    }

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

    private func symbolName(for status: HabitsViewModel.HabitWeekStatus, on date: Date, isActive: Bool) -> String {
        if isActive == false {
            return "circle.fill"
        }
        return status.isCompleted(on: date) ? "checkmark.circle.fill" : "circle"
    }

    private func statsDescription(for habit: Habit) -> String {
        let monthCount = habitsViewModel.monthlyCompletionCount(for: habit)
        let streak = habitsViewModel.currentStreak(for: habit)
        return "今月 \(monthCount) 回 / 連続 \(streak) 日"
    }
}

struct MiniHabitHeatmapView: View {
    let cells: [HabitHeatCell]
    let accentColor: Color

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(cells) { cell in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(for: cell.state))
                            .frame(width: 8, height: 10)
                            .id(cell.id)
                    }
                }
            }
            .onAppear {
                if let last = cells.last {
                    proxy.scrollTo(last.id, anchor: .trailing)
                }
            }
        }
        .frame(height: 14)
    }

    private func color(for state: HabitHeatCell.State) -> Color {
        switch state {
        case .inactive:
            return Color.gray.opacity(0.2)
        case .pending:
            return Color.secondary.opacity(0.45)
        case .completed:
            return accentColor
        }
    }
}

struct HabitYearHeatmapView: View {
    let startDate: Date
    let weekCount: Int
    let summaries: [Date: HabitDaySummary]
    let onSelect: (HabitDaySummary) -> Void

    private let calendar = Calendar.current

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 4) {
                    ForEach(0..<weekCount, id: \.self) { week in
                        VStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { offset in
                                let index = week * 7 + offset
                                let date = calendar.date(byAdding: .day, value: index, to: startDate) ?? startDate
                                let day = calendar.startOfDay(for: date)
                                let summary = summaries[day]
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(color(for: summary))
                                    .frame(width: 14, height: 14)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(Color.black.opacity(0.08))
                                    )
                                    .id(day)
                                    .onTapGesture {
                                        if let summary {
                                            onSelect(summary)
                                        }
                                    }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            .onAppear {
                let today = calendar.startOfDay(for: Date())
                proxy.scrollTo(today, anchor: .trailing)
            }
        }
    }

    private func color(for summary: HabitDaySummary?) -> Color {
        guard let summary else { return Color.gray.opacity(0.15) }
        guard summary.scheduledCount > 0 else { return Color.gray.opacity(0.18) }

        let rate = Double(summary.completedCount) / Double(summary.scheduledCount)
        switch rate {
        case 0:
            return Color.gray.opacity(0.28)
        case 0..<0.26:
            return Color(hex: "#bbf7d0") ?? Color.green.opacity(0.35)
        case 0.26..<0.76:
            return Color(hex: "#4ade80") ?? Color.green.opacity(0.65)
        default:
            return Color(hex: "#16a34a") ?? Color.green
        }
    }
}

struct HabitDaySummarySheet: View {
    let summary: HabitDaySummary
    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary.date, formatter: DateFormatter.japaneseYearMonthDay)
                .font(.headline)
            if summary.scheduledCount == 0 {
                Text("この日は予定された習慣がありません。")
                    .foregroundStyle(.secondary)
            } else {
                let rate = Double(summary.completedCount) / Double(max(summary.scheduledCount, 1))
                Text("\(summary.completedCount) / \(summary.scheduledCount) 個の習慣を達成 (\(Int(rate * 100))%)")
                    .font(.subheadline)
                if summary.completedHabits.isEmpty == false {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("達成済み")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ForEach(summary.completedHabits, id: \.id) { habit in
                            Text("・\(habit.title)")
                                .font(.subheadline)
                        }
                    }
                }
                let completed = Set(summary.completedHabits.map(\.id))
                let missed = summary.scheduledHabits.filter { completed.contains($0.id) == false }
                if missed.isEmpty == false {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("未達成")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ForEach(missed, id: \.id) { habit in
                            Text("・\(habit.title)")
                                .font(.subheadline)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding()
    }
}
