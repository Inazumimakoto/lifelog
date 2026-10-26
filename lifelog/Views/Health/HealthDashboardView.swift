//
//  HealthDashboardView.swift
//  lifelog
//

import SwiftUI
import HealthKit

struct HealthDashboardView: View {
    @StateObject private var viewModel: HealthViewModel
    @State private var showSettings = false
    @State private var selectedHistory: HealthMetric?
    @State private var selectedWellnessDate: Date?
    @State private var selectedSleepDate: Date?

    init(store: AppDataStore) {
        _viewModel = StateObject(wrappedValue: HealthViewModel(store: store))
    }

    private var weeklyRange: Range<Date> {
        HealthHistoryPeriod.week.dateRange(endingOn: Date(), calendar: .current)
    }

    private var weeklyWellness: [DailyWellnessPoint] {
        viewModel.wellnessPoints.filter { weeklyRange.contains($0.date) }
    }

    private var hasHealthMeasurements: Bool {
        viewModel.summaries.contains { summary in
            summary.steps != nil || summary.sleepHours != nil || summary.activeEnergy != nil ||
                summary.moveMinutes != nil || summary.exerciseMinutes != nil || summary.standHours != nil ||
                summary.sleepStart != nil || summary.sleepEnd != nil || !summary.sleepStages.isEmpty
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summarySection
                sleepSection
                fitnessSection
                wellnessTrendSection
                if !hasHealthMeasurements {
                    connectionSection
                }
            }
            .padding()
        }
        .navigationTitle("ヘルスケア")
        .refreshable {
            await viewModel.refreshHealthData()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    _Concurrency.Task { await viewModel.refreshHealthData() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("ヘルスケアデータを更新")
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("設定")
            }
        }
        .navigationDestination(item: $selectedHistory) { metric in
            HealthHistoryView(viewModel: viewModel, metric: metric)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
            }
        }
    }

    private var summarySection: some View {
        SectionCard(title: "直近1週間の平均") {
            HStack(spacing: 12) {
                summaryTile(metric: .steps,
                            value: averageText(for: .steps),
                            icon: "figure.walk",
                            color: .accentColor)
                summaryTile(metric: .sleep,
                            value: averageText(for: .sleep),
                            icon: "moon.fill",
                            color: .purple)
            }
            Text("記録のある日の平均です。未取得の日は含みません。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func summaryTile(metric: HealthMetric, value: String, icon: String, color: Color) -> some View {
        Button {
            selectedHistory = metric
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(metric.title, systemImage: icon)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(color)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(value)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                Text("履歴を見る")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func averageText(for metric: HealthMetric) -> String {
        switch metric {
        case .steps:
            guard viewModel.weeklySummaries.contains(where: { $0.steps != nil }) else { return "—" }
            return HealthChartMeasure.steps.formatted(Double(viewModel.averageSteps))
        case .sleep:
            guard viewModel.weeklySummaries.contains(where: { $0.sleepHours != nil }) else { return "—" }
            return HealthChartMeasure.sleep.formatted(viewModel.averageSleep)
        default:
            return "—"
        }
    }

    private var sleepSection: some View {
        SectionCard(title: "睡眠のリズムと段階", actionTitle: "履歴を見る", action: {
            selectedHistory = .sleep
        }) {
            HealthSleepTimelineChart(summaries: viewModel.weeklySummaries,
                                     range: weeklyRange,
                                     selectedDate: $selectedSleepDate)
            HealthSleepStageLegend()
            if let date = selectedSleepDate {
                HealthSleepDetailsView(summary: viewModel.summaries.first {
                    Calendar.current.isDate($0.date, inSameDayAs: date)
                }, date: date)
            }
            Text("色は記録された睡眠段階を表します。日付をタップすると詳しく確認できます。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // docs/ui-guidelines.md §Health: every row shares a date axis and uses its real unit.
    private var wellnessTrendSection: some View {
        SectionCard(title: "健康状態の推移", actionTitle: "履歴を見る", action: {
            selectedHistory = .wellness
        }) {
            Text("直近1週間")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HealthWellnessCharts(points: weeklyWellness,
                                 range: weeklyRange,
                                 period: .week,
                                 selectedDate: $selectedWellnessDate,
                                 compact: true)
            if let date = selectedWellnessDate {
                HealthDailyValuesView(date: date,
                                      summary: viewModel.summaries.first { Calendar.current.isDate($0.date, inSameDayAs: date) },
                                      wellness: weeklyWellness.first { Calendar.current.isDate($0.date, inSameDayAs: date) },
                                      metric: .wellness)
            }
            Text("空白は未記録です。日付をタップすると、その日の記録を確認できます。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var latestFitness: HealthSummary? {
        viewModel.summaries.last { summary in
            summary.activeEnergy != nil || summary.moveMinutes != nil ||
                summary.exerciseMinutes != nil || summary.standHours != nil
        }
    }

    private var fitnessSection: some View {
        SectionCard(title: "Appleフィットネス", actionTitle: "履歴を見る", action: {
            selectedHistory = .fitness
        }) {
            if let latest = latestFitness {
                HStack {
                    Text(Calendar.current.isDateInToday(latest.date) ? String(localized: "今日") : String(localized: "最新の記録"))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(latest.date, format: .dateTime.month().day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HealthFitnessValuesView(summary: latest)
            } else {
                HealthFitnessValuesView(summary: nil)
                Text("まだアクティビティのデータがありません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("ヘルスケア連携を確認") {
                _Concurrency.Task { await viewModel.requestHealthKitAuthorization() }
            }
            .font(.caption.weight(.medium))
        }
    }

    private var connectionSection: some View {
        SectionCard(title: "ヘルスケアデータがありません") {
            if HKHealthStore.isHealthDataAvailable() {
                Text("iPhoneの「ヘルスケア」アプリとの連携が必要です。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("ヘルスケアに接続") {
                    _Concurrency.Task { await viewModel.requestHealthKitAuthorization() }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("お使いのデバイスではヘルスケアを利用できません。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
