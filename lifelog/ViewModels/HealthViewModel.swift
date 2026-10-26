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

    @Published private(set) var wellnessPoints: [DailyWellnessPoint] = []

    private static func makeWellnessPoints(
        health: [HealthSummary],
        diaryMetrics: [Date: DiaryMetrics],
        calendar: Calendar
    ) -> [DailyWellnessPoint] {
        // §4.8: align all four measurements by calendar day. A missing
        // HealthKit measurement or diary score must stay missing in every row.
        var healthByDay: [Date: HealthSummary] = [:]
        for summary in health {
            let day = calendar.startOfDay(for: summary.date)
            if healthByDay[day] == nil { healthByDay[day] = summary }
        }
        let days = Set(healthByDay.keys).union(diaryMetrics.keys).sorted()
        return days.map { date in
            let summary = healthByDay[date]
            let diary = diaryMetrics[date]
            return DailyWellnessPoint(date: date,
                                      steps: summary?.steps,
                                      sleepHours: summary?.sleepHours,
                                      mood: diary?.mood,
                                      condition: diary?.condition)
        }
    }

    private struct DiaryMetrics: Equatable {
        let mood: MoodLevel?
        let condition: Int?
    }

    private struct CalendarEnvironment: Equatable {
        let calendar: Calendar
        let day: Date
        let localeIdentifier: String
    }

    @Published private var calendarEnvironment: CalendarEnvironment

    private let store: AppDataStore
    private let calendarProvider: () -> Calendar
    private let dateProvider: () -> Date
    private var cancellables = Set<AnyCancellable>()
    private var lastHealthInput: [HealthSummary]?
    private var lastHealthCalendar: Calendar?

    // Avoid the Swift 6.2 back-deployment crash while synthesizing an isolated
    // deinitializer: https://github.com/swiftlang/swift/issues/88036
    nonisolated deinit {}

    init(store: AppDataStore,
         calendarProvider: @escaping () -> Calendar = { .current },
         dateProvider: @escaping () -> Date = Date.init,
         notificationCenter: NotificationCenter = .default) {
        self.store = store
        self.calendarProvider = calendarProvider
        self.dateProvider = dateProvider
        let calendar = calendarProvider()
        self.calendarEnvironment = Self.environment(for: calendar, referenceDate: dateProvider())
        bind(notificationCenter: notificationCenter)
        refresh(health: store.healthSummaries,
                diaryMetrics: Self.diaryMetrics(from: store.diaryEntries, calendar: calendar),
                environment: calendarEnvironment)
    }

    func requestHealthKitAuthorization() async {
        await store.loadHealthData(requestAuthorizationIfNeeded: true)
    }

    func refreshHealthData() async {
        await store.loadHealthData()
    }

    func loadHealthHistory() async {
        guard summaries.isEmpty else { return }
        await store.loadHealthData()
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
                let environment = Self.environment(for: self.calendarProvider(), referenceDate: self.dateProvider())
                if self.calendarEnvironment != environment {
                    self.calendarEnvironment = environment
                }
            }
            .store(in: &cancellables)
    }

    private static func environment(for calendar: Calendar, referenceDate: Date) -> CalendarEnvironment {
        CalendarEnvironment(calendar: calendar,
                            day: calendar.startOfDay(for: referenceDate),
                            localeIdentifier: Locale.current.identifier)
    }

    private static func diaryMetrics(from entries: [DiaryEntry], calendar: Calendar) -> [Date: DiaryMetrics] {
        var result: [Date: DiaryMetrics] = [:]
        // Preserve the old first(where:) behavior for duplicate local dates.
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            if result[day] == nil {
                result[day] = DiaryMetrics(mood: entry.mood,
                                          condition: entry.conditionScore)
            }
        }
        return result
    }

    private static func normalizedSummaries(_ health: [HealthSummary], calendar: Calendar) -> [HealthSummary] {
        // docs/requirements.md §4.8: time-zone changes can leave two stored
        // midnight instants on one current calendar day. Count that day once.
        // Apply the newest non-nil measurement last, retaining older goals and
        // measurements when the newer record contains only missing fields.
        let normalized = health.sorted { $0.date < $1.date }.map { summary in
            var daily = summary
            daily.date = calendar.startOfDay(for: summary.date)
            return daily
        }
        return HealthSummaryMerging.merge(existing: [], incoming: normalized)
            .sorted { $0.date < $1.date }
    }

    private func refresh(health: [HealthSummary],
                         diaryMetrics: [Date: DiaryMetrics],
                         environment: CalendarEnvironment) {
        let calendar = environment.calendar
        if lastHealthInput != health || lastHealthCalendar != calendar {
            lastHealthInput = health
            lastHealthCalendar = calendar
            let normalized = Self.normalizedSummaries(health, calendar: calendar)
            if summaries != normalized { summaries = normalized }
        }
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
        let wellness = Self.makeWellnessPoints(health: summaries, diaryMetrics: diaryMetrics, calendar: calendar)
        if wellnessPoints != wellness { wellnessPoints = wellness }
        let segments = summaries.compactMap { summary -> SleepSegment? in
            guard let start = summary.sleepStart,
                  let end = summary.sleepEnd else { return nil }
            return SleepSegment(date: summary.date, start: start, end: end)
        }
        if sleepSegments != segments { sleepSegments = segments }
    }

    var weeklySummaries: [HealthSummary] {
        let range = HealthHistoryPeriod.week.dateRange(endingOn: calendarEnvironment.day,
                                                       calendar: calendarEnvironment.calendar)
        return summaries.filter { range.contains($0.date) }
    }

    var weeklyWellnessPoints: [DailyWellnessPoint] {
        let range = HealthHistoryPeriod.week.dateRange(endingOn: calendarEnvironment.day,
                                                       calendar: calendarEnvironment.calendar)
        return wellnessPoints.filter { range.contains($0.date) }
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

    var averageActiveEnergy: Double {
        let values = weeklySummaries.compactMap { $0.activeEnergy }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
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
        max(end.timeIntervalSince(start) / 3_600, 0)
    }

    var durationText: String {
        String(format: "%.1fh", durationHours)
    }
}

struct DailyWellnessPoint: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let steps: Int?
    let sleepHours: Double?
    let mood: MoodLevel?
    let condition: Int?
}
