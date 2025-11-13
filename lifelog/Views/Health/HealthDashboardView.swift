//
//  HealthDashboardView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI
import Charts

struct HealthDashboardView: View {
    @StateObject private var viewModel: HealthViewModel
    @State private var presentedMetric: HealthMetric?

    init(store: AppDataStore) {
        _viewModel = StateObject(wrappedValue: HealthViewModel(store: store))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summarySection
                stepsChart
                sleepTimeline
                correlationSection
                fitnessSection
            }
            .padding()
        }
        .navigationTitle("ヘルスケア")
        .sheet(item: $presentedMetric) { metric in
            NavigationStack {
                HealthHistoryView(metric: metric,
                                  summaries: viewModel.summaries)
            }
        }
    }

    private var summarySection: some View {
        SectionCard(title: "直近1週間の平均") {
            HStack {
                StatTile(title: "歩数",
                         value: "\(viewModel.averageSteps)",
                         subtitle: "タップで履歴表示") {
                    presentedMetric = .steps
                }
                StatTile(title: "睡眠",
                         value: String(format: "%.1f h", viewModel.averageSleep),
                         subtitle: "タップで履歴表示") {
                    presentedMetric = .sleep
                }
            }
        }
    }

    private var stepsChart: some View {
        SectionCard(title: "歩数グラフ") {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(Array(viewModel.weeklySummaries.enumerated()), id: \.offset) { _, summary in
                            let steps = summary.steps ?? 0
                            VStack(spacing: 4) {
                                Text("\(steps)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor)
                                    .frame(height: barHeight(for: steps))
                                Text(summary.date, format: .dateTime.weekday(.narrow))
                                    .font(.caption2)
                            }
                            .frame(width: 44)
                        }
                    }
                }
                Text("バーを左右にスワイプして過去の週も確認できます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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

    // Apple Health 風タイムライン要件: docs/requirements.md 4.8 + docs/ui-guidelines.md (Health)
    private var sleepTimeline: some View {
        SectionCard(title: "就寝・起床のタイムライン") {
            Chart(viewModel.sleepSegments) { segment in
                RectangleMark(
                    x: .value("日付", segment.date, unit: .day),
                    yStart: .value("開始", segment.startHour),
                    yEnd: .value("終了", segment.endHour),
                    width: .fixed(20)
                )
                .foregroundStyle(Color.purple.opacity(0.6))
                .annotation(position: .overlay) {
                    Text(segment.durationText)
                        .font(.caption2)
                        .foregroundStyle(.white)
                }
            }
            .chartYScale(domain: viewModel.sleepYDomain)
            .chartYAxis {
                AxisMarks(position: .leading, values: viewModel.sleepYAxisTicks) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let raw = value.as(Double.self) {
                            Text(timeLabel(for: raw))
                        }
                    }
                }
            }
            .frame(height: 220)
            Text("縦方向が睡眠の時間帯です。24時を過ぎると翌日（24時以降）まで表示します。")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private func barHeight(for steps: Int) -> CGFloat {
        let maxSteps = max(viewModel.weeklySummaries.compactMap { $0.steps }.max() ?? 1, 1)
        guard maxSteps > 0 else { return 0 }
        return CGFloat(steps) / CGFloat(maxSteps) * 160
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

    private func timeLabel(for hourValue: Double) -> String {
        let hour = Int(floor(hourValue)) % 24
        let minutes = Int((hourValue - floor(hourValue)) * 60)
        return String(format: "%02d:%02d", hour, minutes)
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

enum HealthMetric: String, Identifiable {
    case steps
    case sleep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: return "歩数の履歴"
        case .sleep: return "睡眠の履歴"
        }
    }

    var unit: String {
        switch self {
        case .steps: return "歩"
        case .sleep: return "時間"
        }
    }
}
