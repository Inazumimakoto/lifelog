//
//  HealthViewModel.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import Combine

@MainActor
final class HealthViewModel: ObservableObject {

    @Published private(set) var summaries: [HealthSummary] = []
    @Published private(set) var correlationPoints: [HealthCorrelationPoint] = []
    @Published private(set) var sleepSegments: [SleepSegment] = []

    private let store: AppDataStore
    private var cancellables = Set<AnyCancellable>()

    init(store: AppDataStore) {
        self.store = store
        bind()
        refresh()
    }

    private func bind() {
        store.$healthSummaries
            .combineLatest(store.$diaryEntries)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    private func refresh() {
        summaries = store.healthSummaries.sorted(by: { $0.date < $1.date })
        correlationPoints = summaries.compactMap { summary in
            guard let steps = summary.steps,
                  let sleep = summary.sleepHours else { return nil }
            let diary = store.diaryEntries.first { Calendar.current.isDate($0.date, inSameDayAs: summary.date) }
            return HealthCorrelationPoint(date: summary.date,
                                          steps: steps,
                                          sleepHours: sleep,
                                          mood: diary?.mood,
                                          condition: diary?.conditionScore)
        }
        sleepSegments = summaries.compactMap { summary in
            guard let start = summary.sleepStart,
                  let end = summary.sleepEnd else { return nil }
            return SleepSegment(date: summary.date, start: start, end: end)
        }
    }

    var weeklySummaries: [HealthSummary] {
        Array(summaries.suffix(7))
    }

    var averageSteps: Int {
        let steps = weeklySummaries.compactMap { $0.steps }
        guard !steps.isEmpty else { return 0 }
        return steps.reduce(0, +) / steps.count
    }

    var averageSleep: Double {
        let sleeps = weeklySummaries.compactMap { $0.sleepHours }
        guard !sleeps.isEmpty else { return 0 }
        return sleeps.reduce(0, +) / Double(sleeps.count)
    }

    var averageMoveMinutes: Double {
        let values = weeklySummaries.compactMap { $0.moveMinutes }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageExerciseMinutes: Double {
        let values = weeklySummaries.compactMap { $0.exerciseMinutes }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageStandHours: Double {
        let values = weeklySummaries.compactMap { $0.standHours }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    // docs/ui-guidelines.md > Health で定義された就寝/起床レンジ算出ルール
    var sleepYDomain: ClosedRange<Double> {
        let startValues = sleepSegments.map { $0.startHour }
        let endValues = sleepSegments.map { $0.endHour }
        guard let minStart = startValues.min(),
              let maxEnd = endValues.max(),
              minStart < maxEnd else {
            return 0...24
        }
        return minStart...maxEnd
    }

    var sleepYAxisTicks: [Double] {
        let domain = sleepYDomain
        let range = domain.upperBound - domain.lowerBound
        guard range > 0 else { return [domain.lowerBound] }
        let step = max(range / 6, 1)
        var ticks: [Double] = []
        var current = domain.lowerBound
        while current <= domain.upperBound + 0.01 {
            ticks.append(current)
            current += step
        }
        return ticks
    }
}

struct HealthCorrelationPoint: Identifiable {
    let id = UUID()
    let date: Date
    let steps: Int
    let sleepHours: Double
    let mood: MoodLevel?
    let condition: Int?
}

struct SleepSegment: Identifiable {
    let id = UUID()
    let date: Date
    let start: Date
    let end: Date

    var startHour: Double {
        Double(Calendar.current.component(.hour, from: start)) + Double(Calendar.current.component(.minute, from: start)) / 60
    }

    var endHour: Double {
        var hour = Double(Calendar.current.component(.hour, from: end)) + Double(Calendar.current.component(.minute, from: end)) / 60
        if hour < startHour {
            hour += 24
        }
        return hour
    }

    var durationHours: Double {
        max(endHour - startHour, 0)
    }

    var durationText: String {
        String(format: "%.1fh", durationHours)
    }
}
