import SwiftUI
import Charts

/// Real units for every health chart (§4.8). Missing measurements stay optional.
enum HealthChartMeasure: String, CaseIterable, Identifiable {
    case steps, sleep, mood, condition, activeEnergy, moveMinutes, exercise, stand

    var id: Self { self }

    var title: String {
        switch self {
        case .steps: return String(localized: "歩数")
        case .sleep: return String(localized: "睡眠")
        case .mood: return String(localized: "気分")
        case .condition: return String(localized: "体調")
        case .activeEnergy: return String(localized: "ムーブ (kcal)")
        case .moveMinutes: return String(localized: "ムーブ (分)")
        case .exercise: return String(localized: "エクササイズ (分)")
        case .stand: return String(localized: "スタンド (時間)")
        }
    }

    var unit: String {
        switch self {
        case .steps: return String(localized: "歩")
        case .sleep, .stand: return String(localized: "時間")
        case .mood, .condition: return "1–5"
        case .activeEnergy: return "kcal"
        case .moveMinutes, .exercise: return String(localized: "分")
        }
    }

    var color: Color {
        switch self {
        case .steps: return .accentColor
        case .sleep: return .purple
        case .mood: return .orange
        case .condition: return .teal
        case .activeEnergy, .moveMinutes: return .pink
        case .exercise: return .green
        case .stand: return .cyan
        }
    }

    var isScore: Bool { self == .mood || self == .condition }

    func formatted(_ value: Double?) -> String {
        guard let value else { return "—" }
        let number: String
        switch self {
        case .steps, .activeEnergy, .moveMinutes, .exercise:
            number = value.formatted(.number.precision(.fractionLength(0)))
        default:
            number = value.formatted(.number.precision(.fractionLength(1)))
        }
        return isScore ? number + " / 5" : number + " " + unit
    }

    func value(in summary: HealthSummary) -> Double? {
        switch self {
        case .steps: return summary.steps.map(Double.init)
        case .sleep: return summary.sleepHours
        case .activeEnergy: return summary.fitnessMoveMode == .time ? nil : summary.activeEnergy
        case .moveMinutes: return summary.fitnessMoveMode == .time ? summary.moveMinutes : nil
        case .exercise: return summary.exerciseMinutes
        case .stand: return summary.standHours
        case .mood, .condition: return nil
        }
    }

    func value(in point: DailyWellnessPoint) -> Double? {
        switch self {
        case .steps: return point.steps.map(Double.init)
        case .sleep: return point.sleepHours
        case .mood: return point.mood.map { Double($0.rawValue) }
        case .condition: return point.condition.map(Double.init)
        default: return nil
        }
    }
}

struct HealthChartBucket: Identifiable {
    var id: Date { range.lowerBound }
    let range: Range<Date>
    var date: Date { range.lowerBound.addingTimeInterval(range.upperBound.timeIntervalSince(range.lowerBound) / 2) }

    static func make(range: Range<Date>, period: HealthHistoryPeriod, calendar: Calendar = .current) -> [Self] {
        var buckets: [Self] = []
        var start = range.lowerBound
        while start < range.upperBound {
            let next: Date
            switch period {
            case .week, .month:
                next = calendar.date(byAdding: .day, value: 1, to: start) ?? range.upperBound
            case .halfYear:
                next = calendar.date(byAdding: .day, value: 7, to: start) ?? range.upperBound
            case .year:
                next = calendar.dateInterval(of: .month, for: start)?.end ?? range.upperBound
            }
            let end = min(next, range.upperBound)
            guard end > start else { break }
            buckets.append(Self(range: start..<end))
            start = end
        }
        return buckets
    }
}

struct HealthChartSample: Identifiable {
    var id: Date { bucket.id }
    let bucket: HealthChartBucket
    let value: Double?
    let recordedDays: Int

    static func make(buckets: [HealthChartBucket], values: [(date: Date, value: Double?)]) -> [Self] {
        buckets.map { bucket in
            let measurements = values.compactMap { bucket.range.contains($0.date) ? $0.value : nil }
            return Self(bucket: bucket,
                        value: measurements.isEmpty ? nil : measurements.reduce(0, +) / Double(measurements.count),
                        recordedDays: measurements.count)
        }
    }
}

struct HealthValueChart: View {
    let measure: HealthChartMeasure
    let samples: [HealthChartSample]
    let range: Range<Date>
    let period: HealthHistoryPeriod
    @Binding var selectedDate: Date?
    var compact = false

    private var selectedBucket: HealthChartBucket? {
        guard let selectedDate else { return nil }
        return samples.first { $0.bucket.range.contains(selectedDate) }?.bucket
    }

    private var yDomain: ClosedRange<Double> {
        if measure.isScore { return 0.5...5.5 }
        let maximum = samples.compactMap(\.value).max() ?? 0
        let minimumMaximum: Double = measure == .sleep ? 8 : measure == .stand ? 12 : 1
        return 0...max(maximum * 1.15, minimumMaximum)
    }

    private var axisDates: [Date] {
        let stride = max(1, Int(ceil(Double(samples.count) / 6)))
        var dates = samples.enumerated().compactMap { index, sample in
            index.isMultiple(of: stride) ? sample.bucket.date : nil
        }
        if let last = samples.last?.bucket.date, dates.last != last {
            let minimumSpacing = range.upperBound.timeIntervalSince(range.lowerBound) / 8
            if let previous = dates.last, dates.count > 1, last.timeIntervalSince(previous) < minimumSpacing {
                dates.removeLast()
            }
            dates.append(last)
        }
        return dates
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(measure.color).frame(width: 7, height: 7)
                    Text(measure.title).font(.subheadline.weight(.medium))
                }
                Spacer()
                Text(measure.unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Chart {
                ForEach(samples) { sample in
                    if let value = sample.value {
                        if measure.isScore {
                            PointMark(x: .value(String(localized: "日付"), sample.bucket.date),
                                      y: .value(measure.title, value))
                                .foregroundStyle(measure.color)
                                .symbolSize(compact ? 28 : 40)
                                .accessibilityLabel(Text(sample.bucket.range.lowerBound, format: .dateTime.month().day()))
                                .accessibilityValue(Text(measure.formatted(value)))
                        } else {
                            let duration = sample.bucket.range.upperBound.timeIntervalSince(sample.bucket.range.lowerBound)
                            RectangleMark(xStart: .value(String(localized: "開始"), sample.bucket.range.lowerBound.addingTimeInterval(duration * 0.12)),
                                          xEnd: .value(String(localized: "終了"), sample.bucket.range.upperBound.addingTimeInterval(-duration * 0.12)),
                                          yStart: .value(measure.title, 0),
                                          yEnd: .value(measure.title, value))
                                .foregroundStyle(measure.color.opacity(selectedBucket?.id == sample.id ? 1 : 0.7))
                                .cornerRadius(2)
                                .annotation(position: .top) {
                                    if period == .week, !compact {
                                        Text(value, format: .number.precision(.fractionLength(measure == .sleep ? 1 : 0)))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .accessibilityLabel(Text(sample.bucket.range.lowerBound, format: .dateTime.month().day()))
                                .accessibilityValue(Text(measure.formatted(value)))
                            if value == 0 {
                                PointMark(x: .value(String(localized: "日付"), sample.bucket.date),
                                          y: .value(measure.title, 0))
                                    .foregroundStyle(measure.color)
                                    .symbolSize(18)
                                    .accessibilityLabel(Text(sample.bucket.range.lowerBound, format: .dateTime.month().day()))
                                    .accessibilityValue(Text(measure.formatted(value)))
                            }
                        }
                    }
                }
                if let selectedBucket {
                    RuleMark(x: .value(String(localized: "選択日"), selectedBucket.date))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .accessibilityHidden(true)
                }
            }
            .chartXScale(domain: range.lowerBound...range.upperBound)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: axisDates) { value in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                    if let date = value.as(Date.self) {
                        let anchor: UnitPoint = date == axisDates.first ? .topLeading : date == axisDates.last ? .topTrailing : .top
                        AxisValueLabel(anchor: anchor) {
                            Text(date, format: period == .year ? .dateTime.month(.abbreviated) : .dateTime.month(.defaultDigits).day())
                                .font(.caption2)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
            }
            .chartYAxis {
                if measure.isScore {
                    AxisMarks(position: .leading, values: [1.0, 3.0, 5.0]) { value in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                        if let number = value.as(Double.self) {
                            AxisValueLabel {
                                Text(number, format: .number.precision(.fractionLength(0)))
                                    .font(.caption2)
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                    }
                } else {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                        if let number = value.as(Double.self) {
                            AxisValueLabel {
                                Text(number, format: .number.notation(.compactName).precision(.fractionLength(0...1)))
                                    .font(.caption2)
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            // A tap selects a date without taking vertical drags from the enclosing ScrollView.
            .chartGesture { proxy in
                SpatialTapGesture().onEnded { event in
                    proxy.selectXValue(at: event.location.x)
                }
            }
            .frame(height: compact ? 100 : 150)
            .overlay {
                if !samples.contains(where: { $0.value != nil }) {
                    Text("記録なし")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(.regularMaterial, in: Capsule())
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel(measure.title)
        }
    }
}

struct HealthWellnessCharts: View {
    let points: [DailyWellnessPoint]
    let range: Range<Date>
    let period: HealthHistoryPeriod
    @Binding var selectedDate: Date?
    var compact = false

    var body: some View {
        let buckets = HealthChartBucket.make(range: range, period: period)
        VStack(spacing: 14) {
            ForEach([HealthChartMeasure.steps, .sleep, .mood, .condition]) { measure in
                HealthValueChart(measure: measure,
                                 samples: HealthChartSample.make(buckets: buckets, values: points.map { ($0.date, measure.value(in: $0)) }),
                                 range: range,
                                 period: period,
                                 selectedDate: $selectedDate,
                                 compact: compact)
            }
        }
    }
}

struct HealthFitnessValuesView: View {
    let summary: HealthSummary?

    private var moveMeasure: HealthChartMeasure {
        summary?.fitnessMoveMode == .time ? .moveMinutes : .activeEnergy
    }

    var body: some View {
        VStack(spacing: 16) {
            progressRow(measure: moveMeasure,
                        value: summary.flatMap { moveMeasure.value(in: $0) },
                        goal: moveMeasure == .moveMinutes ? summary?.moveMinutesGoal : summary?.activeEnergyGoal)
            progressRow(measure: .exercise, value: summary?.exerciseMinutes, goal: summary?.exerciseMinutesGoal)
            progressRow(measure: .stand, value: summary?.standHours, goal: summary?.standHoursGoal)
        }
    }

    private func progressRow(measure: HealthChartMeasure, value: Double?, goal: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(measure.title)
                    .font(.subheadline)
                Spacer()
                Text(measure.formatted(value))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            if let goal, goal > 0 {
                if let value {
                    ProgressView(value: min(max(value, 0), goal), total: goal)
                        .tint(measure.color)
                        .accessibilityLabel(measure.title)
                        .accessibilityValue(measure.formatted(value))
                }
                HStack {
                    Text("目標")
                    Spacer()
                    Text(measure.formatted(goal))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if goal == 0 {
                Text("目標なし")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("目標未取得")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct HealthDailyValuesView: View {
    let date: Date
    let summary: HealthSummary?
    let wellness: DailyWellnessPoint?
    let metric: HealthMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(date, format: .dateTime.year().month().day().weekday())
                .font(.subheadline.weight(.semibold))
            if metric == .fitness {
                HealthFitnessValuesView(summary: summary)
            } else if metric == .sleep {
                HealthSleepDetailsView(summary: summary, date: date, showsDate: false)
            } else {
                ForEach(measures) { measure in
                    HStack {
                        Text(measure.title).foregroundStyle(.secondary)
                        Spacer()
                        Text(measure.formatted(value(for: measure)))
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var measures: [HealthChartMeasure] {
        metric == .steps ? [.steps] : [.steps, .sleep, .mood, .condition]
    }

    private func value(for measure: HealthChartMeasure) -> Double? {
        if let wellness { return measure.value(in: wellness) }
        return summary.flatMap { measure.value(in: $0) }
    }
}
