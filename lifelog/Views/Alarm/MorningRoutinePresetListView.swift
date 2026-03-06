//
//  MorningRoutinePresetListView.swift
//  lifelog
//

import SwiftUI

struct MorningRoutinePresetListView: View {
    @EnvironmentObject private var store: AppDataStore
    @EnvironmentObject private var deepLinkManager: DeepLinkManager

    @State private var editingPreset: MorningRoutinePreset?
    @State private var isShowingEditor = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let session = store.activeMorningRoutineSession {
                activeSessionSection(session)
            }

            presetsSection
            guidanceSection
        }
        .navigationTitle("朝ルーティン")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingPreset = nil
                    isShowingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            NavigationStack {
                MorningRoutinePresetEditorView(preset: editingPreset)
            }
            .environmentObject(store)
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

    private func activeSessionSection(_ session: MorningRoutineSession) -> some View {
        Section("進行中") {
            Button {
                deepLinkManager.requestMorningRoutinePresentation()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Label(session.title, systemImage: "figure.walk.motion")
                        .font(.headline)
                    if let currentStep = session.progress.currentStep {
                        Text("いま: \(currentStep.title) ・ 残り \(currentStep.durationMinutes)分枠")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("終了済みです。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var presetsSection: some View {
        Section("プリセット") {
            if store.morningRoutinePresets.isEmpty {
                ContentUnavailableView(
                    "プリセットがありません",
                    systemImage: "sunrise.fill",
                    description: Text("起床後の流れを先に作っておくと、アラームにひも付けられます。")
                )
            } else {
                ForEach(store.morningRoutinePresets) { preset in
                    Button {
                        editingPreset = preset
                        isShowingEditor = true
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(preset.title)
                                    .font(.headline)
                                Spacer()
                                Text(preset.summaryText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if preset.previewText.isEmpty == false {
                                Text(preset.previewText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("削除", role: .destructive) {
                            store.deleteMorningRoutinePreset(preset.id)
                        }
                        Button("開始") {
                            startRoutine(preset)
                        }
                        .tint(.orange)
                    }
                }
            }
        }
    }

    private var guidanceSection: some View {
        Section("メモ") {
            Text("アラームごとに 1 つのプリセットをひも付けられます。")
            Text("開始すると Live Activity に現在の工程と残り時間を出します。")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func startRoutine(_ preset: MorningRoutinePreset) {
        _Concurrency.Task {
            do {
                _ = try await store.startMorningRoutine(presetID: preset.id, sourceAlarmID: nil)
                await MainActor.run {
                    deepLinkManager.requestMorningRoutinePresentation()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
