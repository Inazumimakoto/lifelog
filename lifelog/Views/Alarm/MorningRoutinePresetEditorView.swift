//
//  MorningRoutinePresetEditorView.swift
//  lifelog
//

import SwiftUI

struct MorningRoutinePresetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore

    @State private var title: String
    @State private var steps: [MorningRoutineStep]
    @State private var errorMessage: String?

    private let originalPreset: MorningRoutinePreset?

    init(preset: MorningRoutinePreset? = nil) {
        self.originalPreset = preset
        _title = State(initialValue: preset?.title ?? "朝の支度")
        _steps = State(initialValue: preset?.steps ?? MorningRoutinePreset.defaultTemplateSteps())
    }

    var body: some View {
        Form {
            Section("基本") {
                TextField("プリセット名", text: $title)

                LabeledContent("合計時間") {
                    Text("\(normalizedSteps.reduce(0) { $0 + $1.durationMinutes })分")
                        .monospacedDigit()
                }
            }

            Section("ステップ") {
                if steps.isEmpty {
                    ContentUnavailableView(
                        "ステップがありません",
                        systemImage: "list.bullet.clipboard",
                        description: Text("追加ボタンから朝の流れを作ってください。")
                    )
                } else {
                    ForEach($steps) { $step in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                TextField("やること", text: $step.title)
                                Button(role: .destructive) {
                                    removeStep(step.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }

                            Stepper(value: $step.durationMinutes, in: 1...90) {
                                Label("\(step.durationMinutes)分", systemImage: "timer")
                                    .monospacedDigit()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Button {
                    steps.append(MorningRoutineStep(title: "", durationMinutes: 3))
                } label: {
                    Label("ステップを追加", systemImage: "plus.circle.fill")
                }

                if originalPreset == nil {
                    Button("朝の支度テンプレートに戻す") {
                        steps = MorningRoutinePreset.defaultTemplateSteps()
                    }
                    .font(.footnote)
                }
            }

            Section("メモ") {
                Text("起床後にこのプリセットを始めるか確認し、開始したら Live Activity に流れを出します。")
                Text("順番に沿って進める前提なので、まずはやることと分数だけを整える設計です。")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .navigationTitle(originalPreset == nil ? "ルーティン追加" : "ルーティン編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    save()
                }
            }
        }
        .alert("朝ルーティン", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var normalizedSteps: [MorningRoutineStep] {
        MorningRoutinePreset.normalizedSteps(steps)
    }

    private func removeStep(_ id: UUID) {
        steps.removeAll { $0.id == id }
    }

    private func save() {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSteps = MorningRoutinePreset.normalizedSteps(steps)

        guard normalizedSteps.isEmpty == false else {
            errorMessage = MorningRoutineError.emptyPreset.localizedDescription
            return
        }

        let preset = MorningRoutinePreset(
            id: originalPreset?.id ?? UUID(),
            title: normalizedTitle.isEmpty ? "朝の支度" : normalizedTitle,
            steps: normalizedSteps,
            createdAt: originalPreset?.createdAt ?? Date(),
            updatedAt: Date()
        )
        store.saveMorningRoutinePreset(preset)
        dismiss()
    }
}
