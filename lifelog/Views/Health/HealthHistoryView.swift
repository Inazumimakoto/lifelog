//
//  HealthHistoryView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI
import Charts

struct HealthHistoryView: View {
    let metric: HealthMetric
    let summaries: [HealthSummary]

    @State private var selectedRange: HistoryRange = .week

    private var rows: [HealthSummary] {
        summaries.sorted { $0.date > $1.date }
    }

    private var filteredRows: [HealthSummary] {
        guard let latest = rows.first else { return rows }
        let lowerBound = Calendar.current.date(byAdding: .day, value: -selectedRange.dayWindow, to: latest.date) ?? latest.date
        return rows.filter { $0.date >= lowerBound }
    }

    private var chartPoints: [HistoryPoint] {
        filteredRows.compactMap { summary in
            switch metric {
            case .steps:
                guard let steps = summary.steps else { return nil }
                return HistoryPoint(date: summary.date, value: Double(steps))
            case .sleep:
                guard let hours = summary.sleepHours else { return nil }
                return HistoryPoint(date: summary.date, value: hours)
            }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Picker("範囲", selection: $selectedRange) {
                ForEach(HistoryRange.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.segmented)
            // 履歴タブ幅ルール: docs/requirements.md 4.8 + docs/ui-guidelines.md (Health)
            ScrollView(.horizontal, showsIndicators: false) {
                Chart(chartPoints) { point in
                    switch metric {
                    case .steps:
                        BarMark(
                            x: .value("日付", point.date, unit: .day),
                            y: .value("歩数", point.value)
                        )
                        .foregroundStyle(Color.accentColor)
                    case .sleep:
                        LineMark(
                            x: .value("日付", point.date, unit: .day),
                            y: .value("睡眠", point.value)
                        )
                        .foregroundStyle(Color.purple)
                        PointMark(
                            x: .value("日付", point.date, unit: .day),
                            y: .value("睡眠", point.value)
                        )
                        .foregroundStyle(Color.purple)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: selectedRange.tickCount))
                }
                .frame(width: chartWidth(for: selectedRange, count: chartPoints.count), height: 220)
            }
            Text("グラフは横にスワイプしてすべての履歴を確認できます。")
                .font(.caption)
                .foregroundStyle(.secondary)
            List(filteredRows) { summary in
                HStack {
                    Text(summary.date.jaYearMonthDayString)
                    Spacer()
                    Text(value(for: summary))
                        .font(.headline)
                }
            }
        }
        .navigationTitle(metric.title)
    }

    private func chartWidth(for range: HistoryRange, count: Int) -> CGFloat {
        let unitWidth: CGFloat
        switch range {
        case .week:
            unitWidth = 48
        case .month:
            unitWidth = 28
        case .halfYear:
            unitWidth = 18
        case .year:
            unitWidth = 12
        }
        return max(CGFloat(max(count, 1)) * unitWidth, 320)
    }

    private func value(for summary: HealthSummary) -> String {
        switch metric {
        case .steps:
            let steps = summary.steps ?? 0
            return "\(steps) \(metric.unit)"
        case .sleep:
            let hours = summary.sleepHours ?? 0
            return String(format: "%.1f %@", hours, metric.unit)
        }
    }
}

private struct HistoryPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

enum HistoryRange: String, CaseIterable, Identifiable {
    case week, month, halfYear, year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: return "1週"
        case .month: return "1か月"
        case .halfYear: return "6か月"
        case .year: return "1年"
        }
    }

    var dayWindow: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .halfYear: return 182
        case .year: return 365
        }
    }

    var tickCount: Int {
        switch self {
        case .week: return 7
        case .month: return 6
        case .halfYear: return 6
        case .year: return 6
        }
    }
}
