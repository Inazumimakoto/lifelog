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
    @State private var showHabitEditor = false
    @State private var showAnniversaryEditor = false
    @State private var editingHabit: Habit?
    @State private var editingAnniversary: Anniversary?
    @State private var displayMode: DisplayMode = .habits

    init(store: AppDataStore) {
        _habitsViewModel = StateObject(wrappedValue: HabitsViewModel(store: store))
        _anniversaryViewModel = StateObject(wrappedValue: AnniversaryViewModel(store: store))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
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
            VStack(alignment: .leading, spacing: 8) {
                Text("アイコンをタップして編集できます。色もパレットから選択してください。")
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
                        HStack {
                            Button {
                                editingHabit = status.habit
                            } label: {
                                HStack(spacing: 6) {
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
                            .frame(width: 140, alignment: .leading)
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
