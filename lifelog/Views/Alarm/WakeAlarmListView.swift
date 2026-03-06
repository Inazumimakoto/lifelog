//
//  WakeAlarmListView.swift
//  lifelog
//

import SwiftUI

struct WakeAlarmListView: View {
    @EnvironmentObject private var store: AppDataStore
    @EnvironmentObject private var deepLinkManager: DeepLinkManager

    @State private var authorizationStatus: WakeAlarmAuthorizationStatus = .unsupported
    @State private var isShowingEditor = false
    @State private var editingAlarm: WakeAlarm?
    @State private var previewAlarm: WakeAlarm?
    @State private var errorMessage: String?

    var body: some View {
        List {
            statusSection
            alarmsSection
            routinesSection
            guidanceSection
        }
        .navigationTitle("目覚まし")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingAlarm = nil
                    isShowingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(authorizationStatus != .authorized)
            }
        }
        .task {
            await refreshAuthorizationStatus()
        }
        .sheet(isPresented: $isShowingEditor) {
            NavigationStack {
                WakeAlarmEditorView(alarm: editingAlarm)
            }
            .environmentObject(store)
            .environmentObject(deepLinkManager)
        }
        .fullScreenCover(item: $previewAlarm) { alarm in
            WakeChallengeView(alarm: alarm, mode: .preview) {
                previewAlarm = nil
            }
            .environmentObject(store)
            .environmentObject(deepLinkManager)
        }
        .alert("目覚まし", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var statusSection: some View {
        Section("権限") {
            switch authorizationStatus {
            case .unsupported:
                VStack(alignment: .leading, spacing: 8) {
                    Label("この機能は iOS 26 以降で使えます", systemImage: "iphone.slash")
                        .foregroundStyle(.secondary)
                    Text("AlarmKit を使ってロック画面から解除テストへ遷移します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .notDetermined:
                Button("目覚ましの許可をリクエスト") {
                    _Concurrency.Task {
                        authorizationStatus = await WakeAlarmService.shared.requestAuthorization()
                    }
                }
                Text("一度許可すると、stop から解除テストを起動できるようになります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .denied:
                Label("設定アプリで目覚ましの許可を有効にしてください", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("いまは保存済みの一覧しか見られません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .authorized:
                Label("目覚ましの許可は有効です", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("stop を押すと解除テストを開始する設計です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var alarmsSection: some View {
        Section("アラーム") {
            if store.wakeAlarms.isEmpty {
                ContentUnavailableView(
                    "まだアラームがありません",
                    systemImage: "alarm",
                    description: Text("右上の追加ボタンから作成できます。")
                )
            } else {
                ForEach(store.wakeAlarms) { alarm in
                    HStack(alignment: .top, spacing: 12) {
                        Button {
                            editingAlarm = alarm
                            isShowingEditor = true
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(alarm.timeText)
                                        .font(.title3.monospacedDigit())
                                        .fontWeight(.semibold)
                                    Text(alarm.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                }

                                HStack(spacing: 8) {
                                    Label(alarm.repeatSummary, systemImage: "repeat")
                                    Label(alarm.challengeMethod.title, systemImage: alarm.challengeMethod.iconName)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                if let presetTitle = routineTitle(for: alarm) {
                                    Label(presetTitle, systemImage: "sunrise.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if let lastSuccessAt = alarm.lastChallengeSuccessAt {
                                    Text("最終解除: \(lastSuccessAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Toggle("", isOn: Binding(
                            get: { alarm.isEnabled },
                            set: { newValue in
                                _Concurrency.Task {
                                    do {
                                        try await store.setWakeAlarmEnabled(alarm.id, isEnabled: newValue)
                                    } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("削除", role: .destructive) {
                            do {
                                try store.deleteWakeAlarm(alarm.id)
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                        Button("テスト") {
                            previewAlarm = alarm
                        }
                        .tint(.orange)
                    }
                }
            }
        }
    }

    private var routinesSection: some View {
        Section("起床後ルーティン") {
            NavigationLink {
                MorningRoutinePresetListView()
            } label: {
                HStack {
                    Label("プリセットを管理", systemImage: "sunrise.fill")
                    Spacer()
                    Text("\(store.morningRoutinePresets.count)")
                        .foregroundStyle(.secondary)
                }
            }

            if let session = store.activeMorningRoutineSession,
               let currentStep = session.progress.currentStep {
                Label("\(session.title): \(currentStep.title)", systemImage: "figure.walk.motion")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var guidanceSection: some View {
        Section("メモ") {
            Text("stop に解除テストを割り当て、snooze は使わない前提で設計しています。")
            Text("解除方法は暗算・短期記憶・文字列入力・シェイクから選べます。")
            Text("起床後ルーティンをひも付けると、解除後にそのまま Live Activity で朝の流れを見続けられます。")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func refreshAuthorizationStatus() async {
        authorizationStatus = await WakeAlarmService.shared.authorizationStatus()
    }

    private func routineTitle(for alarm: WakeAlarm) -> String? {
        guard let presetID = alarm.morningRoutinePresetID,
              let preset = store.morningRoutinePreset(id: presetID) else {
            return nil
        }
        return preset.title
    }
}
