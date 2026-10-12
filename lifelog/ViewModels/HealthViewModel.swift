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

    @Published private(set) var wellnessPoints: [DailyWellnessPoint] = []

    private static func makeWellnessPoints(
        from correlationPoints: [HealthCorrelationPoint],
        calendar: Calendar
    ) -> [DailyWellnessPoint] {
        // Correlation points already follow the summaries' ascending date order.
        let points = correlationPoints
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

    private struct DiaryMetrics: Equatable {
        let mood: MoodLevel
        let condition: Int
    }

    private struct CalendarEnvironment: Equatable {
        let calendar: Calendar
        let day: Date
        let localeIdentifier: String
    }

    @Published private var calendarEnvironment: CalendarEnvironment

    private let store: AppDataStore
    private let calendarProvider: () -> Calendar
    private var cancellables = Set<AnyCancellable>()
    private var lastHealthInput: [HealthSummary]?
    private var lastCalendarEnvironment: CalendarEnvironment?
    private var sleepQualityReferenceDay: Date?

    // Avoid the Swift 6.2 back-deployment crash while synthesizing an isolated
    // deinitializer: https://github.com/swiftlang/swift/issues/88036
    nonisolated deinit {}

    init(store: AppDataStore,
         calendarProvider: @escaping () -> Calendar = { .current },
         notificationCenter: NotificationCenter = .default) {
        self.store = store
        self.calendarProvider = calendarProvider
        let calendar = calendarProvider()
        self.calendarEnvironment = Self.environment(for: calendar)
        bind(notificationCenter: notificationCenter)
        refresh(health: store.healthSummaries,
                diaryMetrics: Self.diaryMetrics(from: store.diaryEntries, calendar: calendar),
                environment: calendarEnvironment)
    }

    func requestHealthKitAuthorization() async {
        await store.loadHealthData(requestAuthorizationIfNeeded: true)
    }

    private func bind(notificationCenter: NotificationCenter) {
        // Health charts use diary dates/mood/condition only (§Health). Text,
        // photos and locations must not recalculate and replace every chart point.
        let diaryInputs = store.$diaryEntries
            .combineLatest($calendarEnvironment)
            .map { Self.diaryMetrics(from: $0.0, calendar: $0.1.calendar) }
            .removeDuplicates()
        store.$healthSummaries
            .removeDuplicates()
            .combineLatest(diaryInputs, $calendarEnvironment)
            .dropFirst() // init creates the initial chart snapshot.
            .debounce(for: .zero, scheduler: DispatchQueue.main)
            .sink { [weak self] health, diary, environment in
                self?.refresh(health: health, diaryMetrics: diary, environment: environment)
            }
            .store(in: &cancellables)

        // Day grouping is a cache input too. Reproject diary dates after system
        // changes even when the underlying health and diary values are equal.
        Publishers.MergeMany([
            Notification.Name.NSCalendarDayChanged,
            Notification.Name.NSSystemTimeZoneDidChange,
            NSLocale.currentLocaleDidChangeNotification
        ].map { notificationCenter.publisher(for: $0) })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let environment = Self.environment(for: self.calendarProvider())
                if self.calendarEnvironment != environment {
                    self.calendarEnvironment = environment
                }
            }
            .store(in: &cancellables)
    }

    private static func environment(for calendar: Calendar) -> CalendarEnvironment {
        CalendarEnvironment(calendar: calendar,
                            day: calendar.startOfDay(for: Date()),
                            localeIdentifier: Locale.current.identifier)
    }

    private static func diaryMetrics(from entries: [DiaryEntry], calendar: Calendar) -> [Date: DiaryMetrics] {
        var result: [Date: DiaryMetrics] = [:]
        // Preserve the old first(where:) behavior for duplicate local dates.
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            if result[day] == nil {
                result[day] = DiaryMetrics(mood: entry.mood ?? .neutral,
                                          condition: entry.conditionScore ?? 3)
            }
        }
        return result
    }

    private func refresh(health: [HealthSummary],
                         diaryMetrics: [Date: DiaryMetrics],
                         environment: CalendarEnvironment) {
        let environmentChanged = lastCalendarEnvironment != environment
        lastCalendarEnvironment = environment
        if lastHealthInput != health {
            lastHealthInput = health
            let sorted = health.sorted { $0.date < $1.date }
            if summaries != sorted { summaries = sorted }
        }
        let calendar = environment.calendar
        let correlations: [HealthCorrelationPoint] = summaries.compactMap { summary in
            guard let steps = summary.steps,
                  let sleep = summary.sleepHours else { return nil }
            let diary = diaryMetrics[calendar.startOfDay(for: summary.date)]
            return HealthCorrelationPoint(date: summary.date,
                                          steps: steps,
                                          sleepHours: sleep,
                                          mood: diary?.mood,
                                          condition: diary?.condition)
        }
        let correlationsChanged = correlationPoints != correlations
        if correlationsChanged {
            correlationPoints = correlations
        }
        if correlationsChanged || environmentChanged {
            let wellness = Self.makeWellnessPoints(from: correlations, calendar: calendar)
            if wellnessPoints != wellness { wellnessPoints = wellness }
        }
        let segments = summaries.compactMap { summary -> SleepSegment? in
            guard let start = summary.sleepStart,
                  let end = summary.sleepEnd else { return nil }
            return SleepSegment(date: summary.date, start: start, end: end)
        }
        let today = environment.day
        if sleepSegments != segments || sleepQualityReferenceDay != today || environmentChanged {
            if sleepSegments != segments { sleepSegments = segments }
            sleepQualityReferenceDay = today
            updateSleepQuality(calendar: calendar)
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

    private func updateSleepQuality(calendar: Calendar) {
        let today = calendar.startOfDay(for: Date())
        let todaySegment = sleepSegments.first { calendar.isDate($0.date, inSameDayAs: today) }
        let latestSegment = todaySegment ?? sleepSegments.max(by: { $0.date < $1.date })

        guard let segment = latestSegment,
              segment.durationHours > 0 else {
            if !sleepQualityPoints.isEmpty { sleepQualityPoints = [] }
            if sleepQualityScore != 0 { sleepQualityScore = 0 }
            return
        }

        let curve = generateQualityCurve(for: segment)
        if sleepQualityPoints != curve { sleepQualityPoints = curve }

        guard curve.isEmpty == false else {
            if sleepQualityScore != 0 { sleepQualityScore = 0 }
            return
        }

        let average = curve.map(\.quality).reduce(0, +) / Double(curve.count)
        let score = Int(average.rounded())
        if sleepQualityScore != score { sleepQualityScore = score }
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

struct HealthCorrelationPoint: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let steps: Int
    let sleepHours: Double
    let mood: MoodLevel?
    let condition: Int?
}

struct SleepSegment: Identifiable, Equatable {
    var id: Date { date }
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

struct SleepQualityPoint: Identifiable, Equatable {
    var id: Date { timestamp }
    let timestamp: Date
    let quality: Double
}

struct DailyWellnessPoint: Identifiable, Equatable {
    var id: Date { date }
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
