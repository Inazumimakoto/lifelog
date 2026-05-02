//
//  InitialPermissionsSetupView.swift
//  lifelog
//
//  Created by Codex on 2026/05/02.
//

import SwiftUI

struct InitialPermissionsSetupView: View {
    @ObservedObject var store: AppDataStore
    var onComplete: () -> Void

    @StateObject private var weatherService = WeatherService()
    @State private var currentStep: InitialPermissionStep = .notifications
    @State private var completedSteps: Set<InitialPermissionStep> = []
    @State private var isRequesting = false
    @State private var statusText: String?

    var body: some View {
        VStack(spacing: 0) {
            progressHeader

            Spacer(minLength: 24)

            VStack(spacing: 22) {
                Image(systemName: currentStep.systemImage)
                    .font(.system(size: 54, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(currentStep.tint)
                    .frame(width: 96, height: 96)
                    .background(currentStep.tint.opacity(0.14), in: Circle())

                VStack(spacing: 10) {
                    Text(currentStep.title)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text(currentStep.message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: 340)
                }

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(currentStep.details, id: \.self) { detail in
                        Label(detail, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .labelStyle(.titleAndIcon)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                if let statusText {
                    Text(statusText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 24)

            VStack(spacing: 12) {
                Button {
                    requestCurrentPermission()
                } label: {
                    HStack {
                        if isRequesting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(currentStep.primaryButtonTitle)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRequesting)

                Button {
                    skipCurrentPermission()
                } label: {
                    Text("あとで")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isRequesting)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .interactiveDismissDisabled()
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("初期設定")
                        .font(.headline)
                    Text("\(currentStep.rawValue + 1) / \(InitialPermissionStep.allCases.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("スキップ") {
                    completeSetup()
                }
                .font(.subheadline.weight(.semibold))
                .disabled(isRequesting)
            }

            HStack(spacing: 8) {
                ForEach(InitialPermissionStep.allCases) { step in
                    Capsule()
                        .fill(progressColor(for: step))
                        .frame(height: 5)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private func progressColor(for step: InitialPermissionStep) -> Color {
        if completedSteps.contains(step) || step.rawValue <= currentStep.rawValue {
            return step.tint
        }
        return Color(.systemGray4)
    }

    private func requestCurrentPermission() {
        guard isRequesting == false else { return }
        isRequesting = true
        statusText = nil

        _Concurrency.Task { @MainActor in
            let granted = await requestPermission(for: currentStep)
            completedSteps.insert(currentStep)
            statusText = granted ? "許可されました" : "あとから設定で変更できます"

            try? await _Concurrency.Task.sleep(nanoseconds: 450_000_000)
            isRequesting = false
            moveToNextStep()
        }
    }

    private func skipCurrentPermission() {
        guard isRequesting == false else { return }
        completedSteps.insert(currentStep)
        statusText = nil
        moveToNextStep()
    }

    private func moveToNextStep() {
        guard let nextStep = currentStep.next else {
            completeSetup()
            return
        }
        statusText = nil
        currentStep = nextStep
    }

    private func completeSetup() {
        UserDefaults.standard.set(true, forKey: InitialPermissionsState.completedKey)
        onComplete()
    }

    @MainActor
    private func requestPermission(for step: InitialPermissionStep) async -> Bool {
        switch step {
        case .notifications:
            UserDefaults.standard.set(true, forKey: InitialPermissionsState.notificationRequestedKey)
            return await NotificationService.shared.requestAuthorization(registerForRemoteNotifications: true)
        case .location:
            UserDefaults.standard.set(true, forKey: InitialPermissionsState.locationRequestedKey)
            return await weatherService.requestLocationPermissionForInitialSetup()
        case .calendar:
            UserDefaults.standard.set(true, forKey: InitialPermissionsState.calendarRequestedKey)
            return await store.syncExternalCalendarsIfAuthorized(requestPermissionIfNeeded: true)
        case .health:
            UserDefaults.standard.set(true, forKey: InitialPermissionsState.healthRequestedKey)
            return await store.loadHealthData(requestAuthorizationIfNeeded: true)
        }
    }
}

private enum InitialPermissionStep: Int, CaseIterable, Identifiable, Hashable {
    case notifications
    case location
    case calendar
    case health

    var id: Int { rawValue }

    var next: InitialPermissionStep? {
        InitialPermissionStep(rawValue: rawValue + 1)
    }

    var title: String {
        switch self {
        case .notifications:
            return "通知をオンにしてください"
        case .location:
            return "位置情報を許可してください"
        case .calendar:
            return "カレンダー連携を許可してください"
        case .health:
            return "歩数と睡眠の取得を許可してください"
        }
    }

    var message: String {
        switch self {
        case .notifications:
            return "日記、予定、タスク、手紙のリマインダーを必要なタイミングで受け取れます。"
        case .location:
            return "現在地の天気をホームに表示し、日記の振り返りに使いやすくします。"
        case .calendar:
            return "iPhoneの標準カレンダーに入っている予定を、lifelifyのホームとカレンダーに表示します。"
        case .health:
            return "ヘルスケアの歩数や睡眠を読み取り、日ごとの振り返りにまとめます。"
        }
    }

    var details: [String] {
        switch self {
        case .notifications:
            return ["予定やタスクのリマインダー", "日記を書き忘れた日の通知", "手紙が届いたときの通知"]
        case .location:
            return ["今日の天気", "最高・最低気温", "日記の振り返り"]
        case .calendar:
            return ["標準カレンダーの予定を表示", "カレンダーごとにカテゴリ分け", "ホームの今日の予定に反映"]
        case .health:
            return ["歩数", "睡眠時間", "ムーブ・エクササイズ・スタンド"]
        }
    }

    var primaryButtonTitle: String {
        switch self {
        case .notifications:
            return "通知を許可する"
        case .location:
            return "位置情報を許可する"
        case .calendar:
            return "カレンダーを許可する"
        case .health:
            return "ヘルスケアを許可する"
        }
    }

    var systemImage: String {
        switch self {
        case .notifications:
            return "bell.badge.fill"
        case .location:
            return "location.circle.fill"
        case .calendar:
            return "calendar.badge.clock"
        case .health:
            return "heart.text.square.fill"
        }
    }

    var tint: Color {
        switch self {
        case .notifications:
            return .orange
        case .location:
            return .green
        case .calendar:
            return .blue
        case .health:
            return .pink
        }
    }
}
