//
//  WakeAlarmListView.swift
//  lifelog
//

import SwiftUI

struct WakeAlarmListView: View {
    @EnvironmentObject private var store: AppDataStore
    @EnvironmentObject private var deepLinkManager: DeepLinkManager
    @AppStorage("hasSeenWakeAlarmOnboarding") private var hasSeenWakeAlarmOnboarding: Bool = false

    @State private var authorizationStatus: WakeAlarmAuthorizationStatus = .unsupported
    @State private var isShowingEditor = false
    @State private var editingAlarm: WakeAlarm?
    @State private var previewAlarm: WakeAlarm?
    @State private var errorMessage: String?
    @State private var showOnboarding = false
    @State private var isRequestingAuthorization = false

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
            presentOnboardingIfNeeded()
        }
        .sheet(isPresented: $isShowingEditor) {
            NavigationStack {
                WakeAlarmEditorView(alarm: editingAlarm)
            }
            .environmentObject(store)
            .environmentObject(deepLinkManager)
        }
        .sheet(isPresented: $showOnboarding, onDismiss: {
            hasSeenWakeAlarmOnboarding = true
        }) {
            WakeAlarmOnboardingSheet(
                authorizationStatus: authorizationStatus,
                isRequestingAuthorization: isRequestingAuthorization,
                onPrimaryAction: requestAuthorizationFromOnboarding,
                onSecondaryAction: {
                    showOnboarding = false
                }
            )
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
                    Text("iPhone の正式な目覚ましとして鳴らし、解除テストと朝ルーティンを組み合わせます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .notDetermined:
                Button("システムの目覚ましを許可") {
                    requestAuthorizationFromList()
                }
                .disabled(isRequestingAuthorization)
                Text("このアプリで iPhone の正式な目覚ましを作るための許可です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .denied:
                Label("設定アプリで目覚ましの許可を有効にしてください", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("許可すると、解除テスト付きのアラームと朝ルーティンを使えます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .authorized:
                Label("目覚ましの許可は有効です", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("アラーム鳴動後は解除テストを経由して止め、そのまま朝ルーティンへ進めます。")
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

    private func presentOnboardingIfNeeded() {
        guard hasSeenWakeAlarmOnboarding == false else { return }
        guard authorizationStatus != .unsupported else {
            hasSeenWakeAlarmOnboarding = true
            return
        }
        showOnboarding = true
    }

    private func requestAuthorizationFromList() {
        isRequestingAuthorization = true
        _Concurrency.Task {
            let newStatus = await WakeAlarmService.shared.requestAuthorization()
            await MainActor.run {
                authorizationStatus = newStatus
                isRequestingAuthorization = false
            }
        }
    }

    private func requestAuthorizationFromOnboarding() {
        if authorizationStatus != .notDetermined {
            showOnboarding = false
            return
        }

        isRequestingAuthorization = true
        _Concurrency.Task {
            let newStatus = await WakeAlarmService.shared.requestAuthorization()
            await MainActor.run {
                authorizationStatus = newStatus
                isRequestingAuthorization = false
                showOnboarding = false
            }
        }
    }
}

private struct WakeAlarmOnboardingSheet: View {
    let authorizationStatus: WakeAlarmAuthorizationStatus
    let isRequestingAuthorization: Bool
    let onPrimaryAction: () -> Void
    let onSecondaryAction: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    featureCard(
                        icon: "alarm.fill",
                        title: "二度寝防止アラーム",
                        detail: "このアプリが iPhone の正式な目覚ましを作ります。鳴ったあと、そのまま解除テストへ進みます。"
                    )
                    featureCard(
                        icon: "brain.head.profile",
                        title: "解除テスト",
                        detail: "暗算、短期記憶、文字列入力、シェイクから選んで、起きたあとに頭と体を動かします。"
                    )
                    featureCard(
                        icon: "sunrise.fill",
                        title: "朝ルーティン",
                        detail: "起きた後の流れをプリセット化して、Live Activity で今やることと残り時間を確認できます。"
                    )
                    footer
                }
                .padding(24)
            }
            .background(
                LinearGradient(
                    colors: [Color(red: 0.11, green: 0.09, blue: 0.07), Color(red: 0.20, green: 0.16, blue: 0.11)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("あとで") {
                        onSecondaryAction()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("二度寝防止アラーム")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text("解除テストでしっかり起きて、そのまま朝ルーティンへつなげます。")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.82))
        }
    }

    private func featureCard(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("最初に必要なこと")
                .font(.headline)
                .foregroundStyle(.white)

            Text("このあと、iPhone のシステム目覚ましとして使うための許可を確認します。")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))

            Button {
                onPrimaryAction()
            } label: {
                if isRequestingAuthorization {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(primaryButtonTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .foregroundStyle(.black)
            .disabled(isRequestingAuthorization)
        }
    }

    private var primaryButtonTitle: String {
        switch authorizationStatus {
        case .notDetermined:
            return "使ってみる"
        case .authorized:
            return "一覧へ進む"
        case .denied:
            return "閉じる"
        case .unsupported:
            return "閉じる"
        }
    }
}
