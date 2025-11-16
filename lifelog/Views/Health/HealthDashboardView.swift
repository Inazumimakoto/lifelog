//
//  HealthDashboardView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI
import Charts
import HealthKit

struct HealthDashboardView: View {
    @StateObject private var viewModel: HealthViewModel

    init(store: AppDataStore) {
        _viewModel = StateObject(wrappedValue: HealthViewModel(store: store))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summarySection
                stepsChart
                sleepDurationChart
//                sleepStageTimeline
                correlationSection
                fitnessSection
            }
            .padding()
        }
        .navigationTitle("ヘルスケア")
        .overlay(
            Group {
                if viewModel.summaries.isEmpty {
                    VStack(spacing: 12) {
                        Text("ヘルスケアデータがありません")
                            .font(.headline)
                        if HKHealthStore.isHealthDataAvailable() {
                            Text("iPhoneの「ヘルスケア」アプリとの連携が必要です。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("ヘルスケアに接続") {
                                _Concurrency.Task {
                                    await viewModel.requestHealthKitAuthorization()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Text("お使いのデバイスではヘルスケアを利用できません。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        )
    }

    private var summarySection: some View {
        SectionCard(title: "直近1週間の平均") {
            HStack {
                StatTile(title: "歩数",
                         value: "\(viewModel.averageSteps)")
                StatTile(title: "睡眠",
                         value: String(format: "%.1f h", viewModel.averageSleep))
            }
        }
    }

    private var stepsChart: some View {
        SectionCard(title: "歩数グラフ") {
            let summaries = Array(viewModel.weeklySummaries.suffix(7))
            if summaries.isEmpty {
                Text("まだ歩数データがありません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(Array(summaries.enumerated()), id: \.offset) { _, summary in
                            let steps = summary.steps ?? 0
                            VStack(spacing: 4) {
                                Text("\(steps)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor)
                                    .frame(height: barHeight(for: steps, in: summaries))
                                Text(summary.date.jaWeekdayString)
                                    .font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                Text("直近7日分の歩数です。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var sleepDurationChart: some View {
        SectionCard(title: "睡眠時間") {
            let summaries = Array(viewModel.weeklySummaries.suffix(7))
            if summaries.isEmpty {
                Text("まだ睡眠データがありません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(Array(summaries.enumerated()), id: \.offset) { _, summary in
                            let hours = summary.sleepHours ?? 0
                            VStack(spacing: 4) {
                                Text(String(format: "%.1f h", hours))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.purple)
                                    .frame(height: sleepBarHeight(for: hours, in: summaries))
                                Text(summary.date.jaWeekdayString)
                                    .font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    Text("直近7日分の睡眠時間です。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var correlationSection: some View {
        SectionCard(title: "睡眠・歩数と気分の関係") {
            if viewModel.correlationPoints.isEmpty {
                Text("まだ比較できるデータがありません")
                    .foregroundStyle(.secondary)
            } else {
                Chart(viewModel.correlationPoints) { point in
                    PointMark(
                        x: .value("睡眠", point.sleepHours),
                        y: .value("歩数", point.steps)
                    )
                    .foregroundStyle(color(for: point.condition))
                    .annotation {
                        Text(point.mood?.emoji ?? "•")
                    }
                }
                .frame(height: 220)
                Text("縦軸が歩数、横軸が睡眠時間です。色は体調スコアを表します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fitnessSection: some View {
        SectionCard(title: "Appleフィットネス連携（サンプル）") {
            let latest = viewModel.weeklySummaries.first { Calendar.current.isDateInToday($0.date) } ?? viewModel.weeklySummaries.last
            VStack(spacing: 12) {
                FitnessProgressRow(label: "ムーブ (kcal)",
                                   value: latest?.activeEnergy ?? viewModel.averageMoveMinutes * 10,
                                   goal: 600,
                                   accent: .red)
                FitnessProgressRow(label: "エクササイズ (分)",
                                   value: latest?.exerciseMinutes ?? viewModel.averageExerciseMinutes,
                                   goal: 30,
                                   accent: .green)
                FitnessProgressRow(label: "スタンド (時間)",
                                   value: latest?.standHours ?? viewModel.averageStandHours,
                                   goal: 12,
                                   accent: .blue)
                Text("実機ではAppleフィットネスのリング情報と同期できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func barHeight(for steps: Int, in summaries: [HealthSummary]) -> CGFloat {
        let maxSteps = max(summaries.compactMap { $0.steps }.max() ?? 1, 1)
        guard maxSteps > 0 else { return 0 }
        return CGFloat(steps) / CGFloat(maxSteps) * 160
    }

    private func sleepBarHeight(for hours: Double, in summaries: [HealthSummary]) -> CGFloat {
        let maxHours = max(summaries.compactMap { $0.sleepHours }.max() ?? 1, 1)
        guard maxHours > 0 else { return 0 }
        return CGFloat(hours) / CGFloat(maxHours) * 160
    }

    private func color(for condition: Int?) -> Color {
        switch condition ?? 3 {
        case 5: return .green
        case 4: return .mint
        case 3: return .orange
        case 2: return .pink
        default: return .red
        }
    }

}

private struct FitnessProgressRow: View {
    var label: String
    var value: Double
    var goal: Double
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value))/\(Int(goal))")
            }
            .font(.caption)
            GeometryReader { proxy in
                Capsule()
                    .fill(accent.opacity(0.2))
                    .frame(height: 10)
                Capsule()
                    .fill(accent)
                    .frame(width: proxy.size.width * CGFloat(min(value / max(goal, 1), 1)),
                           height: 10)
            }
            .frame(height: 10)
        }
    }
}


