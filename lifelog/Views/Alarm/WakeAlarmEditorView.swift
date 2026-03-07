//
//  WakeAlarmEditorView.swift
//  lifelog
//

import SwiftUI

struct WakeAlarmEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore

    @State private var title: String
    @State private var time: Date
    @State private var repeatDays: [Weekday]
    @State private var challengeMethod: WakeChallengeMethod
    @State private var morningRoutinePresetID: UUID?
    @State private var isEnabled: Bool
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var isSaving = false

    private let originalAlarm: WakeAlarm?

    init(alarm: WakeAlarm? = nil) {
        self.originalAlarm = alarm

        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = alarm?.hour ?? 7
        components.minute = alarm?.minute ?? 0
        let initialTime = calendar.date(from: components) ?? Date()

        _title = State(initialValue: alarm?.title ?? "朝のアラーム")
        _time = State(initialValue: initialTime)
        _repeatDays = State(initialValue: alarm?.repeatDays ?? [])
        _challengeMethod = State(initialValue: alarm?.challengeMethod ?? .mentalMath)
        _morningRoutinePresetID = State(initialValue: alarm?.morningRoutinePresetID)
        _isEnabled = State(initialValue: alarm?.isEnabled ?? true)
    }

    var body: some View {
        Form {
            Section("基本") {
                TextField("タイトル", text: $title)
                DatePicker("時刻", selection: $time, displayedComponents: .hourAndMinute)
                Toggle("有効", isOn: $isEnabled)
            }

            Section("繰り返し") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 10) {
                    ForEach(Weekday.allCases) { day in
                        Button {
                            toggle(day)
                        } label: {
                            Text(day.shortLabel)
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(repeatDays.contains(day) ? Color.orange : Color.secondary.opacity(0.16))
                                .foregroundStyle(repeatDays.contains(day) ? Color.white : Color.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("曜日を選ばない場合は、次回1回だけ鳴ります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("解除方法") {
                Picker("チャレンジ", selection: $challengeMethod) {
                    ForEach(WakeChallengeMethod.allCases) { method in
                        VStack(alignment: .leading) {
                            Text(method.title)
                            Text(method.detail)
                        }
                        .tag(method)
                    }
                }
                Text("stop を押すと、この解除テストをフルスクリーンで開始します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("起床後ルーティン") {
                if store.morningRoutinePresets.isEmpty {
                    NavigationLink {
                        MorningRoutinePresetListView()
                    } label: {
                        Label("朝ルーティンを作成", systemImage: "sunrise.fill")
                    }

                    Text("先にプリセットを作ると、解除後にそのまま流れを始めるか確認できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("プリセット", selection: $morningRoutinePresetID) {
                        Text("なし").tag(UUID?.none)
                        ForEach(store.morningRoutinePresets) { preset in
                            Text("\(preset.title) (\(preset.totalDurationMinutes)分)").tag(Optional(preset.id))
                        }
                    }

                    if let morningRoutinePresetID,
                       let preset = store.morningRoutinePreset(id: morningRoutinePresetID) {
                        Text("\(preset.previewText)\n\(preset.summaryText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if originalAlarm != nil {
                Section {
                    Button("アラームを削除", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
        }
        .navigationTitle(originalAlarm == nil ? "アラーム追加" : "アラーム編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("保存") {
                        save()
                    }
                }
            }
        }
        .confirmationDialog("このアラームを削除しますか？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                deleteAlarm()
            }
            Button("キャンセル", role: .cancel) { }
        }
        .alert("アラーム", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func toggle(_ day: Weekday) {
        if let index = repeatDays.firstIndex(of: day) {
            repeatDays.remove(at: index)
        } else {
            repeatDays.append(day)
            repeatDays = WakeAlarm.normalizedRepeatDays(repeatDays)
        }
    }

    private func save() {
        isSaving = true

        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        let alarm = WakeAlarm(
            id: originalAlarm?.id ?? UUID(),
            title: normalizedTitle.isEmpty ? "朝のアラーム" : normalizedTitle,
            hour: components.hour ?? 7,
            minute: components.minute ?? 0,
            repeatDays: repeatDays,
            challengeMethod: challengeMethod,
            morningRoutinePresetID: morningRoutinePresetID,
            isEnabled: isEnabled,
            createdAt: originalAlarm?.createdAt ?? Date(),
            lastChallengeSuccessAt: originalAlarm?.lastChallengeSuccessAt
        )

        _Concurrency.Task {
            do {
                try await store.saveWakeAlarm(alarm)
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func deleteAlarm() {
        guard let originalAlarm else { return }
        do {
            try store.deleteWakeAlarm(originalAlarm.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
