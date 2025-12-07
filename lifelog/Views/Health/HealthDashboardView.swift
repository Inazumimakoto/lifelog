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
    @State private var showSettings = false
    @State private var selectedStepsIndex: Int? = nil
    @State private var selectedSleepIndex: Int? = nil

    init(store: AppDataStore) {
        _viewModel = StateObject(wrappedValue: HealthViewModel(store: store))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summarySection
                stepsChart
                sleepDurationChart
                wellnessTrendSection
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
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.primary)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
            }
        }
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

    private var wellnessTrendSection: some View {
        SectionCard(title: "健康状態の推移") {
            let points = Array(viewModel.wellnessPoints.suffix(7))
            if points.isEmpty {
                Text("歩数・睡眠・日記が揃うと関係性を表示できます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                wellnessTrendChart(points: points)
                Text("棒＝歩数、線＝睡眠時間、🟡＝気分、🔵＝体調")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func wellnessTrendChart(points: [DailyWellnessPoint]) -> some View {
        guard let firstDate = points.first?.date,
              let lastDate = points.last?.date else {
            return AnyView(EmptyView())
        }
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: firstDate)
        let endDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDate)) ?? lastDate

        let indexedPoints = Array(points.enumerated())

        return AnyView(
            Chart {
                ForEach(indexedPoints, id: \.element.id) { _, point in
                    BarMark(
                        x: .value("日付", point.date, unit: .day),
                        y: .value("歩数(%)", point.stepsPercent)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.45))
                    .cornerRadius(6)
                }
                ForEach(indexedPoints, id: \.element.id) { _, point in
                    LineMark(
                        x: .value("日付", point.date, unit: .day),
                        y: .value("睡眠(%)", point.sleepPercent)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.purple)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                    PointMark(
                        x: .value("日付", point.date, unit: .day),
                        y: .value("睡眠(%)", point.sleepPercent)
                    )
                    .foregroundStyle(.purple)
                }
                ForEach(indexedPoints, id: \.element.id) { _, point in
                    if let moodPercent = point.moodPercent {
                        PointMark(
                            x: .value("日付", point.date, unit: .day),
                            y: .value("気分", moodPercent)
                        )
                        .foregroundStyle(.clear)
                        .annotation(position: .overlay) {
                            Circle()
                                .fill(Color.yellow.opacity(0.85))
                                .frame(width: 8, height: 8)
                                .blendMode(.plusLighter)
                        }
                        .zIndex(2)
                    }
                    if let conditionPercent = point.conditionPercent {
                        PointMark(
                            x: .value("日付", point.date, unit: .day),
                            y: .value("体調", conditionPercent)
                        )
                        .foregroundStyle(.clear)
                        .annotation(position: .overlay) {
                            Circle()
                                .fill(Color.blue.opacity(0.85))
                                .frame(width: 8, height: 8)
                                .blendMode(.plusLighter)
                        }
                        .zIndex(2)
                    }
                }
            }
            .chartXScale(domain: startDate...endDate)
            .chartYScale(domain: 0...110)
            .chartYAxis {
                AxisMarks(preset: .automatic, position: .leading) { value in
                    AxisGridLine()
                    AxisTick()
                    if let percent = value.as(Double.self) {
                        AxisValueLabel("\(Int(percent))%")
                    }
                }
            }
            .chartYAxis {
                AxisMarks(preset: .automatic, position: .trailing) { value in
                    AxisGridLine().foregroundStyle(Color.gray.opacity(0.2))
                    AxisTick()
                    if let raw = value.as(Double.self) {
                        let scaleValue = 1 + Int(round(raw / 25.0))
                        AxisValueLabel("\(min(scaleValue, 5))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisGridLine()
                    AxisTick()
                    if let date = value.as(Date.self) {
                        AxisValueLabel(date.formatted(
                            .dateTime
                                .month(.defaultDigits)
                                .day(.twoDigits)
                                .weekday(.abbreviated)
                        ))
                    }
                }
            }
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .frame(height: 260)
        )
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
                    ZStack(alignment: .top) {
                        HStack(alignment: .bottom, spacing: 8) {
                            ForEach(Array(summaries.enumerated()), id: \.offset) { index, summary in
                                let steps = summary.steps ?? 0
                                VStack(spacing: 4) {
                                    Text("\(steps)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedStepsIndex == index ? Color.accentColor.opacity(0.7) : Color.accentColor)
                                        .frame(height: barHeight(for: steps, in: summaries))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(selectedStepsIndex == index ? Color.white : Color.clear, lineWidth: 2)
                                        )
                                        .onTapGesture {
                                            HapticManager.light()
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                if selectedStepsIndex == index {
                                                    selectedStepsIndex = nil
                                                } else {
                                                    selectedStepsIndex = index
                                                }
                                            }
                                        }
                                    Text(summary.date.jaWeekdayNarrowString)
                                        .font(.caption2)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        
                        // ツールチップ
                        if let index = selectedStepsIndex, index < summaries.count {
                            stepsTooltip(for: summaries[index], allSummaries: summaries)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    Text("タップで詳細を表示")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onTapGesture {
            // 外側タップで閉じる
            if selectedStepsIndex != nil {
                withAnimation { selectedStepsIndex = nil }
            }
        }
    }
    
    private func stepsTooltip(for summary: HealthSummary, allSummaries: [HealthSummary]) -> some View {
        let steps = summary.steps ?? 0
        let average = allSummaries.compactMap { $0.steps }.reduce(0, +) / max(allSummaries.count, 1)
        let avgDiff = steps - average
        
        // 前週同曜日を取得
        let calendar = Calendar.current
        let lastWeekDate = calendar.date(byAdding: .day, value: -7, to: summary.date)
        let lastWeekSummary = viewModel.summaries.first { 
            lastWeekDate != nil && calendar.isDate($0.date, inSameDayAs: lastWeekDate!) 
        }
        let lastWeekSteps = lastWeekSummary?.steps ?? 0
        let weekDiff = lastWeekSteps > 0 ? steps - lastWeekSteps : nil
        
        return VStack(alignment: .leading, spacing: 6) {
            Text(summary.date.jaMonthDayWeekdayString)
                .font(.caption.bold())
            Text("\(steps.formatted()) 歩")
                .font(.subheadline.bold())
            
            Divider()
            
            HStack {
                Text("週平均比")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(avgDiff >= 0 ? "+\(avgDiff.formatted())" : "\(avgDiff.formatted())")
                    .font(.caption.bold())
                    .foregroundStyle(avgDiff >= 0 ? .green : .red)
            }
            
            if let diff = weekDiff {
                HStack {
                    Text("先週\(summary.date.jaWeekdayNarrowString)比")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(diff >= 0 ? "+\(diff.formatted())" : "\(diff.formatted())")
                        .font(.caption.bold())
                        .foregroundStyle(diff >= 0 ? .green : .red)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .frame(maxWidth: 180)
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
                    ZStack(alignment: .top) {
                        HStack(alignment: .bottom, spacing: 8) {
                            ForEach(Array(summaries.enumerated()), id: \.offset) { index, summary in
                                let hours = summary.sleepHours ?? 0
                                VStack(spacing: 4) {
                                    Text(String(format: "%.1f h", hours))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedSleepIndex == index ? Color.purple.opacity(0.7) : Color.purple)
                                        .frame(height: sleepBarHeight(for: hours, in: summaries))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(selectedSleepIndex == index ? Color.white : Color.clear, lineWidth: 2)
                                        )
                                        .onTapGesture {
                                            HapticManager.light()
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                if selectedSleepIndex == index {
                                                    selectedSleepIndex = nil
                                                } else {
                                                    selectedSleepIndex = index
                                                }
                                            }
                                        }
                                    Text(summary.date.jaWeekdayNarrowString)
                                        .font(.caption2)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        
                        // ツールチップ
                        if let index = selectedSleepIndex, index < summaries.count {
                            sleepTooltip(for: summaries[index], allSummaries: summaries)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                    Text("タップで詳細を表示")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onTapGesture {
            // 外側タップで閉じる
            if selectedSleepIndex != nil {
                withAnimation { selectedSleepIndex = nil }
            }
        }
    }
    
    private func sleepTooltip(for summary: HealthSummary, allSummaries: [HealthSummary]) -> some View {
        let hours = summary.sleepHours ?? 0
        let average = allSummaries.compactMap { $0.sleepHours }.reduce(0, +) / Double(max(allSummaries.count, 1))
        let avgDiff = hours - average
        
        // 前週同曜日を取得
        let calendar = Calendar.current
        let lastWeekDate = calendar.date(byAdding: .day, value: -7, to: summary.date)
        let lastWeekSummary = viewModel.summaries.first { 
            lastWeekDate != nil && calendar.isDate($0.date, inSameDayAs: lastWeekDate!) 
        }
        let lastWeekHours = lastWeekSummary?.sleepHours ?? 0
        let weekDiff = lastWeekHours > 0 ? hours - lastWeekHours : nil
        
        return VStack(alignment: .leading, spacing: 6) {
            Text(summary.date.jaMonthDayWeekdayString)
                .font(.caption.bold())
            Text(String(format: "%.1f 時間", hours))
                .font(.subheadline.bold())
            
            Divider()
            
            HStack {
                Text("週平均比")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: avgDiff >= 0 ? "+%.1f h" : "%.1f h", avgDiff))
                    .font(.caption.bold())
                    .foregroundStyle(avgDiff >= 0 ? .green : .red)
            }
            
            if let diff = weekDiff {
                HStack {
                    Text("先週\(summary.date.jaWeekdayNarrowString)比")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: diff >= 0 ? "+%.1f h" : "%.1f h", diff))
                        .font(.caption.bold())
                        .foregroundStyle(diff >= 0 ? .green : .red)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .frame(maxWidth: 180)
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
