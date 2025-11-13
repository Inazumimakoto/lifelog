//
//  HabitEditorView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct HabitEditorView: View {
    @Environment(\.dismiss) private var dismiss
    var habit: Habit?
    var onSave: (Habit) -> Void

    @State private var title = ""
    @State private var iconName = "star.fill"
    @State private var colorHex = "#F97316"
    @State private var scheduleOption: HabitScheduleOption = .daily
    @State private var customDays: Set<Weekday> = []

    private let palette: [String] = [
        "#F97316", "#F43F5E", "#EC4899", "#8B5CF6",
        "#3B82F6", "#0EA5E9", "#10B981", "#22C55E",
        "#84CC16", "#EAB308", "#EF4444", "#94A3B8"
    ]
    private let iconPalette: [String] = [
        "sun.max.fill", "moon.stars.fill", "flame.fill", "drop.fill",
        "leaf.fill", "heart.fill", "book.fill", "pencil",
        "figure.walk", "figure.run", "fork.knife", "sparkles"
    ]

    init(habit: Habit? = nil, onSave: @escaping (Habit) -> Void) {
        self.habit = habit
        self.onSave = onSave
        _title = State(initialValue: habit?.title ?? "")
        _iconName = State(initialValue: habit?.iconName ?? "star.fill")
        _colorHex = State(initialValue: habit?.colorHex ?? "#F97316")
        if let habitSchedule = habit?.schedule {
            switch habitSchedule {
            case .daily:
                _scheduleOption = State(initialValue: .daily)
            case .weekdays:
                _scheduleOption = State(initialValue: .weekdays)
            case .custom(let days):
                _scheduleOption = State(initialValue: .custom)
                _customDays = State(initialValue: Set(days))
            }
        }
    }

    var body: some View {
        Form {
            Section("基本情報") {
                TextField("習慣名", text: $title)
                TextField("SF Symbols 名称", text: $iconName)
                VStack(alignment: .leading, spacing: 8) {
                    Text("よく使うアイコンから選択")
                        .font(.subheadline)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(iconPalette, id: \.self) { symbol in
                            Button {
                                iconName = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .frame(width: 30, height: 30)
                                    .foregroundStyle(iconName == symbol ? Color.accentColor : .primary)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(iconName == symbol ? Color.accentColor : Color.secondary.opacity(0.3))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("カラーを選択")
                        .font(.subheadline)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(palette, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex) ?? .accentColor)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: colorHex == hex ? 2 : 0)
                                )
                                .onTapGesture {
                                    colorHex = hex
                                }
                        }
                    }
                }
            }

            Section("スケジュール") {
                Picker("頻度", selection: $scheduleOption) {
                    ForEach(HabitScheduleOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                if scheduleOption == .custom {
                    VStack {
                        Text("曜日を選択")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
                            ForEach(Weekday.allCases) { weekday in
                                Button {
                                    if customDays.contains(weekday) {
                                        customDays.remove(weekday)
                                    } else {
                                        customDays.insert(weekday)
                                    }
                                } label: {
                                    Text(weekday.shortLabel)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(customDays.contains(weekday) ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(habit == nil ? "習慣を追加" : "習慣を編集")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let schedule = scheduleOption.schedule(with: customDays)
                    let habitToSave = Habit(id: habit?.id ?? UUID(),
                                            title: title,
                                            iconName: iconName,
                                            colorHex: colorHex,
                                            schedule: schedule)
                    onSave(habitToSave)
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル", role: .cancel) { dismiss() }
            }
        }
    }
}

private enum HabitScheduleOption: Int, CaseIterable, Identifiable {
    case daily, weekdays, custom

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .daily: return "毎日"
        case .weekdays: return "平日"
        case .custom: return "カスタム"
        }
    }

    func schedule(with days: Set<Weekday>) -> HabitSchedule {
        switch self {
        case .daily: return .daily
        case .weekdays: return .weekdays
        case .custom: return .custom(days: Array(days))
        }
    }
}
