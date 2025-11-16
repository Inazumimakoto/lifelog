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
    @Published private(set) var sleepQualityPoints: [SleepQualityPoint] = []
    @Published private(set) var sleepQualityScore: Int = 0

    var wellnessPoints: [DailyWellnessPoint] {
        let calendar = Calendar.current
        let points = correlationPoints
            .sorted(by: { $0.date < $1.date })
            .map { point -> (Date, HealthCorrelationPoint) in
                (calendar.startOfDay(for: point.date), point)
            }
        guard points.isEmpty == false else { return [] }
        let maxSteps = Double(points.map { $0.1.steps }.max() ?? 0)
        let maxSleep = points.map { $0.1.sleepHours }.max() ?? 0
        let stepsDenominator = max(maxSteps, 1)
        let sleepDenominator = max(maxSleep, 1)

        return points.map { entry in
            let date = entry.0
            let point = entry.1
            let stepsPercent = Double(point.steps) / stepsDenominator * 100
            let sleepPercent = point.sleepHours / sleepDenominator * 100
            var moodPercent: Double?
            if let mood = point.mood {
                moodPercent = Double(mood.rawValue - 1) / 4 * 100
            }
            var conditionPercent: Double?
            if let condition = point.condition {
                conditionPercent = Double(condition - 1) / 4 * 100
            }
            return DailyWellnessPoint(date: date,
                                      steps: point.steps,
                                      sleepHours: point.sleepHours,
                                      mood: point.mood,
                                      condition: point.condition,
                                      stepsPercent: stepsPercent,
                                      sleepPercent: sleepPercent,
                                      moodPercent: moodPercent,
                                      conditionPercent: conditionPercent)
        }
    }

    private let store: AppDataStore
    private var cancellables = Set<AnyCancellable>()

    init(store: AppDataStore) {
        self.store = store
        bind()
        refresh()
    }

    func requestHealthKitAuthorization() async {
        await store.loadHealthData()
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
        updateSleepQuality()
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

    private func updateSleepQuality() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todaySegment = sleepSegments.first { calendar.isDate($0.date, inSameDayAs: today) }
        let latestSegment = todaySegment ?? sleepSegments.max(by: { $0.date < $1.date })

        guard let segment = latestSegment,
              segment.durationHours > 0 else {
            sleepQualityPoints = []
            sleepQualityScore = 0
            return
        }

        let curve = generateQualityCurve(for: segment)
        sleepQualityPoints = curve

        guard curve.isEmpty == false else {
            sleepQualityScore = 0
            return
        }

        let average = curve.map(\.quality).reduce(0, +) / Double(curve.count)
        sleepQualityScore = Int(average.rounded())
    }

    private func generateQualityCurve(for segment: SleepSegment) -> [SleepQualityPoint] {
        let duration = segment.end.timeIntervalSince(segment.start)
        guard duration > 0 else { return [] }

        let step = max(duration / 12, 15 * 60) // ensure at least 15 min granularity
        var points: [SleepQualityPoint] = []
        var current = segment.start

        let durationPenalty = max(0, 7 - segment.durationHours) * 3

        while current <= segment.end {
            let elapsed = current.timeIntervalSince(segment.start)
            let progress = elapsed / duration // 0...1
            let circadian = sin(progress * .pi) // peaks mid-sleep

            let depthBonus: Double
            switch progress {
            case 0.15..<0.45:
                depthBonus = 10
            case 0.45..<0.75:
                depthBonus = 18
            default:
                depthBonus = 0
            }

            let rawScore = 60 + (25 * circadian) + depthBonus - durationPenalty
            let clampedScore = max(35, min(100, rawScore))

            points.append(SleepQualityPoint(timestamp: current, quality: clampedScore))
            current = current.addingTimeInterval(step)
        }

        if let last = points.last, last.timestamp < segment.end {
            points.append(SleepQualityPoint(timestamp: segment.end, quality: last.quality))
        }

        return points
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

struct SleepQualityPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let quality: Double
}

struct DailyWellnessPoint: Identifiable {
    let id = UUID()
    let date: Date
    let steps: Int
    let sleepHours: Double
    let mood: MoodLevel?
    let condition: Int?
    let stepsPercent: Double
    let sleepPercent: Double
    let moodPercent: Double?
    let conditionPercent: Double?
}
