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

    init(store: AppDataStore) {
        _habitsViewModel = StateObject(wrappedValue: HabitsViewModel(store: store))
        _anniversaryViewModel = StateObject(wrappedValue: AnniversaryViewModel(store: store))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                habitsSection
                anniversarySection
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
    }

    private var habitsSection: some View {
        SectionCard(title: "習慣",
                    actionTitle: "追加",
                    action: { showHabitEditor = true }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("アイコンはSF Symbols名（例: flame, book.fill）を入力、色はパレットから選べます。行をタップすると編集できます。")
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
                                    Label(status.habit.title, systemImage: status.habit.iconName)
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(width: 140, alignment: .leading)
                            ForEach(habitsViewModel.weekDates, id: \.self) { date in
                                Button {
                                    habitsViewModel.toggle(habit: status.habit, on: date)
                                } label: {
                                    Image(systemName: status.isCompleted(on: date) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(status.isCompleted(on: date) ? Color(hex: status.habit.colorHex) ?? .accentColor : .secondary)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
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
                    if index < anniversaryViewModel.rows.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }
}
