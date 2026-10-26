import SwiftUI

struct HealthHistoryView: View {
    @ObservedObject var viewModel: HealthViewModel
    let metric: HealthMetric
    @State private var historyPosition = HealthHistoryPosition(endingOn: Date())
    @State private var selectedChartDate: Date?
    @State private var selectedSleepDate: Date?
    @State private var showsAllDailyRecords = false
    @State private var isLoading = false

    private var period: HealthHistoryPeriod { historyPosition.period }
    private var endingOn: Date { historyPosition.endingOn() }

    private var range: Range<Date> {
        period.dateRange(endingOn: endingOn, calendar: .current)
    }

    private var summaries: [HealthSummary] {
        viewModel.summaries.filter { range.contains($0.date) }
    }

    private var wellness: [DailyWellnessPoint] {
        viewModel.wellnessPoints.filter { range.contains($0.date) }
    }

    private var buckets: [HealthChartBucket] {
        HealthChartBucket.make(range: range, period: period)
    }

    private var selectedBucket: HealthChartBucket? {
        guard let selectedChartDate else { return nil }
        return buckets.first { $0.range.contains(selectedChartDate) }
    }

    private var recordRange: Range<Date> {
        selectedBucket?.range ?? range
    }

    private var measures: [HealthChartMeasure] {
        switch metric {
        case .steps: return [.steps]
        case .sleep: return [.sleep]
        case .wellness: return [.steps, .sleep, .mood, .condition]
        case .fitness:
            let hasTimeMove = summaries.contains { $0.fitnessMoveMode == .time }
            return hasTimeMove ? [.activeEnergy, .moveMinutes, .exercise, .stand] : [.activeEnergy, .exercise, .stand]
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                periodControls
                averagesSection
                chartsSection
                if let selectedBucket {
                    selectionSection(bucket: selectedBucket)
                }
                dailyRecordsSection
            }
            .padding()
        }
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadHistory()
        }
        .refreshable {
            await loadHistory(forceRefresh: true)
        }
        .onChange(of: period) { _, _ in resetSelection() }
        .onChange(of: endingOn) { _, _ in resetSelection() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isLoading {
                    ProgressView()
                } else {
                    Button {
                        _Concurrency.Task { await loadHistory(forceRefresh: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("ヘルスケアデータを更新")
                }
            }
        }
    }

    private var periodControls: some View {
        VStack(spacing: 12) {
            Picker("表示期間", selection: Binding(get: { historyPosition.period }, set: {
                historyPosition.changePeriod(to: $0)
            })) {
                ForEach(HealthHistoryPeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 12) {
                Button { movePeriod(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .disabled(!canMoveBackward)
                .accessibilityLabel("前の期間")
                Spacer(minLength: 0)
                Text(dateRangeText(range))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
                Button { movePeriod(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .disabled(Calendar.current.isDateInToday(endingOn))
                .accessibilityLabel("次の期間")
            }
            if !Calendar.current.isDateInToday(endingOn) {
                Button("最新の期間に戻る") { historyPosition.resetToLatest(Date()) }
                    .font(.caption.weight(.medium))
            }
        }
    }

    private var averagesSection: some View {
        SectionCard(title: "期間の平均") {
            averageGrid(for: range)
            Text("記録のある日の平均です。未取得の日は含みません。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var chartsSection: some View {
        SectionCard(title: chartTitle) {
            if metric == .sleep, period == .week || period == .month {
                HealthSleepTimelineChart(summaries: summaries, range: range, selectedDate: $selectedChartDate)
                HealthSleepStageLegend()
            } else if metric == .wellness {
                HealthWellnessCharts(points: wellness,
                                     range: range,
                                     period: period,
                                     selectedDate: $selectedChartDate)
            } else {
                VStack(spacing: 18) {
                    ForEach(measures) { measure in
                        HealthValueChart(measure: measure,
                                         samples: samples(for: measure),
                                         range: range,
                                         period: period,
                                         selectedDate: $selectedChartDate)
                    }
                }
            }
            Text(period == .week || period == .month
                 ? String(localized: "日付をタップすると、その日の記録を確認できます。")
                 : String(localized: "グラフは記録のある日の平均です。期間をタップすると日別の記録を確認できます。"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var chartTitle: String {
        if metric == .sleep, period == .week || period == .month {
            return String(localized: "睡眠のリズムと段階")
        }
        switch period {
        case .week, .month: return String(localized: "日別の推移")
        case .halfYear: return String(localized: "週ごとの日平均")
        case .year: return String(localized: "月ごとの日平均")
        }
    }

    private func selectionSection(bucket: HealthChartBucket) -> some View {
        SectionCard(title: period == .week || period == .month ? String(localized: "選択日の記録") : String(localized: "選択期間の平均")) {
            if period == .week || period == .month {
                dailyValues(for: bucket.range.lowerBound)
            } else {
                Text(dateRangeText(bucket.range))
                    .font(.subheadline.weight(.medium))
                averageGrid(for: bucket.range)
                if metric == .sleep {
                    Divider()
                    HealthSleepTimelineChart(summaries: summaries.filter { bucket.range.contains($0.date) },
                                             range: bucket.range,
                                             selectedDate: $selectedSleepDate)
                    HealthSleepStageLegend()
                    if let selectedSleepDate {
                        HealthSleepDetailsView(summary: summary(for: selectedSleepDate), date: selectedSleepDate)
                    }
                }
            }
            Button("選択を解除") {
                selectedChartDate = nil
                selectedSleepDate = nil
            }
            .font(.caption)
        }
    }

    private var dailyRecordsSection: some View {
        SectionCard(title: "日別の記録") {
            let allDates = recordedDates(in: recordRange)
            let shownDates = showsAllDailyRecords ? allDates : Array(allDates.prefix(14))
            if allDates.isEmpty {
                Text("この期間の記録はありません。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(shownDates, id: \.self) { date in
                        DisclosureGroup {
                            dailyValues(for: date)
                                .padding(.top, 8)
                                .padding(.bottom, 12)
                        } label: {
                            HStack {
                                Text(date, format: .dateTime.month().day().weekday(.abbreviated))
                                    .font(.subheadline)
                                Spacer()
                                Text(dailyRowValue(for: date))
                                    .font(.subheadline.weight(.medium))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 10)
                        }
                        if date != shownDates.last { Divider() }
                    }
                }
                if allDates.count > 14, !showsAllDailyRecords {
                    Button("すべての日別記録を表示") { showsAllDailyRecords = true }
                        .font(.subheadline)
                        .padding(.top, 6)
                }
            }
        }
    }

    private func averageGrid(for range: Range<Date>) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
            ForEach(measures) { measure in
                let values = measurements(for: measure).compactMap { range.contains($0.date) ? $0.value : nil }
                VStack(alignment: .leading, spacing: 5) {
                    Text(measure.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(measure.formatted(values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                    Text(String(localized: "記録 \(values.count)日"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func measurements(for measure: HealthChartMeasure) -> [(date: Date, value: Double?)] {
        if metric == .wellness {
            return wellness.map { ($0.date, measure.value(in: $0)) }
        }
        return summaries.map { ($0.date, measure.value(in: $0)) }
    }

    private func samples(for measure: HealthChartMeasure) -> [HealthChartSample] {
        HealthChartSample.make(buckets: buckets, values: measurements(for: measure))
    }

    private func summary(for date: Date) -> HealthSummary? {
        summaries.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    private func wellnessPoint(for date: Date) -> DailyWellnessPoint? {
        wellness.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    private func dailyValues(for date: Date) -> some View {
        HealthDailyValuesView(date: date,
                              summary: summary(for: date),
                              wellness: wellnessPoint(for: date),
                              metric: metric)
    }

    private func dailyRowValue(for date: Date) -> String {
        switch metric {
        case .steps: return HealthChartMeasure.steps.formatted(summary(for: date)?.steps.map(Double.init))
        case .sleep: return HealthChartMeasure.sleep.formatted(summary(for: date)?.sleepHours)
        case .fitness:
            guard let summary = summary(for: date) else { return "—" }
            let measure: HealthChartMeasure = summary.fitnessMoveMode == .time ? .moveMinutes : .activeEnergy
            return measure.formatted(measure.value(in: summary))
        case .wellness:
            let point = wellnessPoint(for: date)
            return [point?.mood?.emoji, point?.condition.map { HealthChartMeasure.condition.formatted(Double($0)) }]
                .compactMap { $0 }.joined(separator: "  ")
        }
    }

    private func recordedDates(in range: Range<Date>) -> [Date] {
        let calendar = Calendar.current
        let dates: [Date]
        if metric == .wellness {
            dates = wellness.filter { point in
                range.contains(point.date) && hasWellnessMeasurement(point)
            }.map(\.date)
        } else {
            dates = summaries.filter { summary in
                range.contains(summary.date) && hasHealthMeasurement(summary)
            }.map(\.date)
        }
        return Array(Set(dates.map { calendar.startOfDay(for: $0) })).sorted(by: >)
    }

    private func dateRangeText(_ range: Range<Date>) -> String {
        let last = Calendar.current.date(byAdding: .day, value: -1, to: range.upperBound) ?? range.lowerBound
        let format = Date.FormatStyle.dateTime.year().month(.defaultDigits).day()
        if Calendar.current.isDate(range.lowerBound, inSameDayAs: last) { return range.lowerBound.formatted(format) }
        return range.lowerBound.formatted(format) + " – " + last.formatted(format)
    }

    private func movePeriod(by direction: Int) {
        guard direction > 0 || canMoveBackward else { return }
        historyPosition.move(by: direction, latestDate: Date())
    }

    private var canMoveBackward: Bool {
        let earliest = metric == .wellness ? viewModel.wellnessPoints.first(where: hasWellnessMeasurement)?.date : viewModel.summaries.first(where: hasHealthMeasurement)?.date
        guard let earliest else { return false }
        return range.lowerBound > Calendar.current.startOfDay(for: earliest)
    }

    private func hasWellnessMeasurement(_ point: DailyWellnessPoint) -> Bool {
        point.steps != nil || point.sleepHours != nil || point.mood != nil || point.condition != nil
    }

    private func hasHealthMeasurement(_ summary: HealthSummary) -> Bool {
        switch metric {
        case .steps:
            return summary.steps != nil
        case .sleep:
            return summary.sleepHours != nil || summary.sleepStart != nil || !summary.sleepStages.isEmpty
        case .fitness:
            return [HealthChartMeasure.activeEnergy, .moveMinutes, .exercise, .stand].contains {
                $0.value(in: summary) != nil
            }
        case .wellness:
            return summary.steps != nil || summary.sleepHours != nil
        }
    }

    private func resetSelection() {
        selectedChartDate = nil
        selectedSleepDate = nil
        showsAllDailyRecords = false
    }

    private func loadHistory(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        if forceRefresh {
            await viewModel.refreshHealthData()
        } else {
            await viewModel.loadHealthHistory()
        }
        isLoading = false
    }
}
