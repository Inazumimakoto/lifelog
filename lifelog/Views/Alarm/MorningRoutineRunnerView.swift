//
//  MorningRoutineRunnerView.swift
//  lifelog
//

import Combine
import SwiftUI

struct MorningRoutineRunnerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore

    @State private var now: Date = Date()
    @State private var showFinishConfirmation = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let session = store.activeMorningRoutineSession {
                content(session: session)
            } else {
                ProgressView()
                    .onAppear {
                        dismiss()
                    }
            }
        }
        .onReceive(timer) { date in
            now = date
            guard let session = store.activeMorningRoutineSession else {
                dismiss()
                return
            }
            guard session.isFinished(at: date) else { return }

            _Concurrency.Task {
                await store.finishMorningRoutine()
                await MainActor.run {
                    dismiss()
                }
            }
        }
        .confirmationDialog("このルーティンを終了しますか？", isPresented: $showFinishConfirmation, titleVisibility: .visible) {
            Button("終了", role: .destructive) {
                _Concurrency.Task {
                    await store.finishMorningRoutine()
                    await MainActor.run {
                        dismiss()
                    }
                }
            }
            Button("キャンセル", role: .cancel) { }
        }
    }

    private func content(session: MorningRoutineSession) -> some View {
        let progress = session.progress(at: now)

        return ZStack {
            LinearGradient(
                colors: [Color(red: 0.96, green: 0.76, blue: 0.52), Color(red: 0.98, green: 0.89, blue: 0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header(session: session, progress: progress)
                    currentStepCard(progress: progress)
                    timelineCard(progress: progress)
                    controls
                }
                .padding(24)
            }
        }
    }

    private func header(session: MorningRoutineSession, progress: MorningRoutineProgress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("朝ルーティン")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black.opacity(0.6))

            Text(session.title)
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(.black)

            HStack(spacing: 12) {
                Label("\(session.steps.count)ステップ", systemImage: "list.bullet")
                if let overallEndAt = progress.overallEndAt {
                    Label("終了予定 \(overallEndAt.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.black.opacity(0.7))
        }
    }

    private func currentStepCard(progress: MorningRoutineProgress) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("いまやること", systemImage: "sun.max.fill")
                    .font(.headline)
                Spacer()
                Text("\(Int(progress.completionFraction * 100))%")
                    .font(.headline.monospacedDigit())
            }

            if let currentStep = progress.currentStep {
                Text(currentStep.title)
                    .font(.system(size: 34, weight: .black, design: .rounded))

                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("この工程の残り")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(currentStep.endAt, style: .timer)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("次の切り替え")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(currentStep.endAt.formatted(date: .omitted, time: .shortened))
                            .font(.title3.monospacedDigit())
                    }
                }

                ProgressView(value: progress.completionFraction)
                    .tint(.black)
            } else {
                Text("おつかれさま。ルーティンは完了しました。")
                    .font(.title2.weight(.bold))
                ProgressView(value: 1)
                    .tint(.black)
            }
        }
        .padding(24)
        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func timelineCard(progress: MorningRoutineProgress) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("流れ", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)

            ForEach(progress.timeline) { step in
                let isCurrent = step.id == progress.currentStep?.id
                let isCompleted = step.endAt <= now

                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(isCurrent ? Color.black : (isCompleted ? Color.black.opacity(0.35) : Color.white))
                        .frame(width: 12, height: 12)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(step.title)
                                .font(isCurrent ? .headline : .body)
                            Spacer()
                            Text("\(step.durationMinutes)分")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Text("\(step.startAt.formatted(date: .omitted, time: .shortened)) - \(step.endAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(isCurrent ? .black.opacity(0.08) : .white.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .padding(22)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Live Activity で続ける") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.black)
            .foregroundStyle(.white)

            Button("このルーティンを終了") {
                showFinishConfirmation = true
            }
            .buttonStyle(.bordered)
            .tint(.black)

            Text("閉じてもロック画面の Live Activity から今の工程を見返せます。")
                .font(.footnote)
                .foregroundStyle(.black.opacity(0.7))
        }
    }
}
