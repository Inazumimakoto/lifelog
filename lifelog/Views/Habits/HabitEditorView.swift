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
    var onDelete: (() -> Void)?

    @State private var title = ""
    @State private var iconName = "sun.max.fill"
    @State private var colorHex = "#F97316"
    @State private var scheduleOption: HabitScheduleOption = .daily
    @State private var customDays: Set<Weekday> = []
    @State private var showDeleteConfirmation = false

    private let palette: [String] = [
        "#F97316", "#F43F5E", "#EC4899", "#8B5CF6",
        "#3B82F6", "#0EA5E9", "#10B981", "#22C55E",
        "#84CC16", "#EAB308", "#EF4444", "#94A3B8"
    ]
    private let iconsByCategory: [IconCategory] = [
        IconCategory(title: "ライフスタイル", symbols: ["sun.max.fill", "moon.stars.fill", "sparkles", "flame.fill", "drop.fill"]),
        IconCategory(title: "健康", symbols: ["heart.fill", "lungs.fill", "hare.fill", "figure.walk", "figure.run"]),
        IconCategory(title: "学習・作業", symbols: ["book.fill", "pencil", "brain.head.profile", "laptopcomputer", "graduationcap.fill"]),
        IconCategory(title: "食事・生活", symbols: ["fork.knife", "cup.and.saucer.fill", "cart.fill", "leaf.fill", "house.fill"]),
        IconCategory(title: "感情・自己管理", symbols: ["face.smiling", "star.fill", "bolt.fill", "timer", "camera.fill"])
    ]

    init(habit: Habit? = nil,
         onSave: @escaping (Habit) -> Void,
         onDelete: (() -> Void)? = nil) {
        self.habit = habit
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: habit?.title ?? "")
        _iconName = State(initialValue: habit?.iconName ?? "sun.max.fill")
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("よく使うアイコンから選択")
                        .font(.subheadline)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(iconsByCategory) { category in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(category.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                                    ForEach(category.symbols, id: \.self) { symbol in
                                        Button {
                                            iconName = symbol
                                        } label: {
                                            Image(systemName: symbol)
                                                .frame(width: 32, height: 32)
                                                .foregroundStyle(iconName == symbol ? Color.accentColor : .primary)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(iconName == symbol ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1.5)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
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
            
            if habit != nil && onDelete != nil {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("習慣を削除")
                            Spacer()
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
        .confirmationDialog("この習慣を削除しますか？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("キャンセル", role: .cancel) { }
        }
    }
}

private struct IconCategory: Identifiable {
    let id = UUID()
    let title: String
    let symbols: [String]
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
