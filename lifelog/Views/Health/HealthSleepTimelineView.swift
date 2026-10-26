import SwiftUI
import Charts

private struct HealthSleepBand: Identifiable {
    let id: String
    let date: Date
    let coordinate: HealthSleepTimelineLayout.Segment
    let stage: SleepStageType
}

/// Nightly time coordinates are local wall-clock hours relative to the wake-up day.
/// Negating the axis puts the previous evening at the top and the next evening below.
struct HealthSleepTimelineChart: View {
    let summaries: [HealthSummary]
    let range: Range<Date>
    @Binding var selectedDate: Date?

    private var bands: [HealthSleepBand] {
        let calendar = Calendar.current
        return summaries.flatMap { summary -> [HealthSleepBand] in
            let day = calendar.startOfDay(for: summary.date)
            guard range.contains(day) else { return [] }
            if !summary.sleepStages.isEmpty {
                return summary.sleepStages.flatMap { stage in
                    makeBands(id: stage.id.uuidString, day: day, start: stage.start, end: stage.end, stage: stage.stage)
                }
            }
            guard let start = summary.sleepStart, let end = summary.sleepEnd else { return [] }
            return makeBands(id: summary.id.uuidString, day: day, start: start, end: end, stage: .unspecified)
        }
    }

    private var axisDates: [Date] {
        let buckets = HealthChartBucket.make(range: range, period: .month)
        let stride = max(1, Int(ceil(Double(buckets.count) / 7)))
        var dates = buckets.enumerated().compactMap { index, bucket in
            index.isMultiple(of: stride) ? bucket.date : nil
        }
        if let last = buckets.last?.date, dates.last != last {
            let minimumSpacing = range.upperBound.timeIntervalSince(range.lowerBound) / 8
            if let previous = dates.last, dates.count > 1, last.timeIntervalSince(previous) < minimumSpacing {
                dates.removeLast()
            }
            dates.append(last)
        }
        return dates
    }

    var body: some View {
        let chartBands = bands
        let axis = HealthSleepTimelineLayout.axis(for: chartBands.map(\.coordinate))
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(chartBands) { band in
                    let bounds = horizontalBounds(for: band.date, lane: band.coordinate.lane)
                    RectangleMark(xStart: .value(String(localized: "開始日"), bounds.lowerBound),
                                  xEnd: .value(String(localized: "終了日"), bounds.upperBound),
                                  yStart: .value(String(localized: "起床"), -band.coordinate.endHour),
                                  yEnd: .value(String(localized: "就寝"), -band.coordinate.startHour))
                        .foregroundStyle(band.stage.color)
                        .cornerRadius(1)
                        .accessibilityLabel(Text(band.date, format: .dateTime.month().day()) + Text(" ") + Text(LocalizedStringKey(band.stage.displayName)))
                        .accessibilityValue(Text(accessibilityValue(for: band)))
                }
                if let selectedDate, range.contains(selectedDate) {
                    let day = Calendar.current.startOfDay(for: selectedDate)
                    let middle = horizontalBounds(for: day)
                    RuleMark(x: .value(String(localized: "選択日"), middle.lowerBound.addingTimeInterval(middle.upperBound.timeIntervalSince(middle.lowerBound) / 2)))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .accessibilityHidden(true)
                }
            }
            .chartXScale(domain: range.lowerBound...range.upperBound)
            .chartYScale(domain: axis.yDomain)
            .chartXAxis {
                AxisMarks(values: axisDates) { value in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                    if let date = value.as(Date.self) {
                        AxisValueLabel(centered: false, collisionResolution: .disabled) {
                            Text(date, format: .dateTime.month(.defaultDigits).day())
                                .font(.caption2)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: axis.tickHours.map { -$0 }.sorted()) { value in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                    if let hour = value.as(Double.self) {
                        AxisValueLabel {
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(relativeDayText(hour: -hour))
                                    .foregroundStyle(.secondary)
                                Text(HealthSleepTimelineLayout.clockText(for: -hour))
                                    .monospacedDigit()
                            }
                            .font(.caption2)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartGesture { proxy in
                SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }
            }
            .frame(height: 250)
            .overlay {
                if chartBands.isEmpty {
                    Text("まだ睡眠データがありません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(.regularMaterial, in: Capsule())
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("睡眠のリズムと段階")
            Text("日付は起床した日です。昼寝を含む睡眠段階を表示します。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if chartBands.contains(where: { $0.coordinate.lane != .full }) {
                Text("時刻が戻る日は、変更前を左、変更後を右に表示します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func horizontalBounds(for day: Date, lane: HealthSleepTimelineLayout.Lane = .full) -> Range<Date> {
        let next = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        let duration = next.timeIntervalSince(day)
        let fullStart = day.addingTimeInterval(duration * 0.18)
        let width = duration * 0.64
        return fullStart.addingTimeInterval(width * lane.fractions.lowerBound)..<fullStart.addingTimeInterval(width * lane.fractions.upperBound)
    }

    private func makeBands(id: String, day: Date, start: Date, end: Date, stage: SleepStageType) -> [HealthSleepBand] {
        HealthSleepTimelineLayout.segments(from: start, to: end, relativeTo: day).enumerated().map { index, segment in
            HealthSleepBand(id: "\(id)-\(index)", date: day, coordinate: segment, stage: stage)
        }
    }

    private func relativeDayText(hour: Double) -> String {
        let offset = HealthSleepTimelineLayout.clockComponents(for: hour).dayOffset
        switch offset {
        case -1: return String(localized: "前日")
        case 0: return String(localized: "当日")
        case 1: return String(localized: "翌日")
        case ..<(-1): return String(format: String(localized: "%lld日前"), Int64(-offset))
        default: return String(format: String(localized: "%lld日後"), Int64(offset))
        }
    }

    private func accessibilityValue(for band: HealthSleepBand) -> String {
        let format = Date.FormatStyle.dateTime.hour().minute().timeZone(.specificName(.short))
        let coordinate = band.coordinate
        let minutes = coordinate.endDate.timeIntervalSince(coordinate.startDate) / 60
        return coordinate.startDate.formatted(format) + "–" + coordinate.endDate.formatted(format)
            + ", " + HealthChartMeasure.moveMinutes.formatted(minutes)
    }
}

struct HealthSleepStageLegend: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { legendItems }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    legendItem(.awake)
                    legendItem(.rem)
                    legendItem(.core)
                }
                HStack(spacing: 10) {
                    legendItem(.deep)
                    legendItem(.unspecified)
                }
            }
        }
    }

    @ViewBuilder private var legendItems: some View {
        ForEach(SleepStageType.timelineOrder) { stage in
            legendItem(stage)
        }
    }

    private func legendItem(_ stage: SleepStageType) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(stage.color).frame(width: 9, height: 9)
            Text(LocalizedStringKey(stage.displayName)).font(.caption2)
        }
    }
}

struct HealthSleepDetailsView: View {
    let summary: HealthSummary?
    let date: Date
    var showsDate = true

    private var stageMinutes: [(stage: SleepStageType, minutes: Double)] {
        guard let summary else { return [] }
        return SleepStageType.timelineOrder.compactMap { type in
            let stages = summary.sleepStages.filter { $0.stage == type }
            guard !stages.isEmpty else { return nil }
            return (type, stages.reduce(0) { $0 + max($1.durationMinutes, 0) })
        }
    }

    private var asleepMinutes: Double {
        stageMinutes.filter { $0.stage != .awake }.reduce(0) { $0 + $1.minutes }
    }

    private var hasKnownSleepStages: Bool {
        stageMinutes.contains { $0.stage == .rem || $0.stage == .core || $0.stage == .deep }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsDate {
                Text(date, format: .dateTime.year().month().day().weekday())
                    .font(.subheadline.weight(.semibold))
            }
            HStack {
                Text("合計睡眠").foregroundStyle(.secondary)
                Spacer()
                Text(HealthChartMeasure.sleep.formatted(summary?.sleepHours))
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            HStack(spacing: 18) {
                sleepTime(label: String(localized: "就寝"), date: summary?.sleepStart, icon: "moon.fill")
                sleepTime(label: String(localized: "起床"), date: summary?.sleepEnd, icon: "sun.max.fill")
            }
            Text("睡眠時間は昼寝を含みます。就寝・起床は主な睡眠の時刻です。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !hasKnownSleepStages {
                Text("睡眠段階の記録がありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !stageMinutes.isEmpty {
                Divider()
                Text("睡眠段階")
                    .font(.subheadline.weight(.semibold))
                ForEach(stageMinutes, id: \.stage) { item in
                    stageRow(item.stage, minutes: item.minutes)
                }
                if hasKnownSleepStages {
                    Text("割合は睡眠段階が記録された時間に対する比率です。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
    }

    private func sleepTime(label: String, date: Date?, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let date {
                Text(date, format: .dateTime.hour().minute())
                    .font(.title3.weight(.medium))
                    .monospacedDigit()
            } else {
                Text("—").font(.title3.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stageRow(_ stage: SleepStageType, minutes: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label {
                    Text(LocalizedStringKey(stage.displayName))
                } icon: {
                    Circle().fill(stage.color).frame(width: 7, height: 7)
                }
                Spacer()
                Text(HealthChartMeasure.moveMinutes.formatted(minutes))
                    .monospacedDigit()
                if hasKnownSleepStages, stage != .awake, asleepMinutes > 0 {
                    Text((minutes / asleepMinutes).formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
            }
            if hasKnownSleepStages, stage != .awake, asleepMinutes > 0 {
                ProgressView(value: minutes, total: asleepMinutes)
                    .tint(stage.color)
            }
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }
}
