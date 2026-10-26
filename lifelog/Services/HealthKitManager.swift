//
//  HealthKitManager.swift
//  lifelog
//
//  Created by Codex on 2025/11/15.
//

import Foundation
import HealthKit
import os

@MainActor
class HealthKitManager {
    
    static let shared = HealthKitManager()
    let healthStore = HKHealthStore()
    
    private let legacyReadTypes: Set<HKObjectType> = [
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
        HKObjectType.categoryType(forIdentifier: .appleStandHour)!
    ]

    private var readTypes: Set<HKObjectType> {
        legacyReadTypes.union([HKObjectType.activitySummaryType()])
    }
    
    private init() { }
    
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            return false
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            AppLogger.health.error("Error requesting HealthKit authorization: \(error.localizedDescription)")
            return false
        }
    }

    /// 権限ダイアログを表示済みかどうか(読み取り権限の許可/拒否そのものは HealthKit が公開しない)
    func hasPreviouslyRequestedAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            return false
        }

        do {
            // Backfill old grants without treating the newly added ring-summary
            // type as evidence that legacy sleep/steps were never requested.
            let status = try await healthStore.statusForAuthorizationRequest(toShare: [], read: legacyReadTypes)
            return status == .unnecessary
        } catch {
            AppLogger.health.error("Error checking HealthKit authorization request status: \(error.localizedDescription)")
            return false
        }
    }
    
    func fetchHealthData(for lastNDays: Int) async -> [HealthSummary] {
        guard let window = HealthQueryWindow(lastNDays: lastNDays) else { return [] }

        var summaries: [Date: HealthSummary] = [:]
        for date in window.summaryDays {
            summaries[date] = HealthSummary(date: date)
        }

        // Independent queries run together, then ring summaries supply the
        // actual per-day goals (§4.8).
        async let sleepResult = fetchSleepData(from: window.start, to: window.endExclusive)
        async let stepsResult = fetchCumulativeQuantity(for: .stepCount, from: window.start, to: window.endExclusive)
        async let energyResult = fetchCumulativeQuantity(for: .activeEnergyBurned, from: window.start, to: window.endExclusive)
        async let exerciseResult = fetchCumulativeQuantity(for: .appleExerciseTime, from: window.start, to: window.endExclusive)
        async let standResult = fetchStandHours(from: window.start, to: window.endExclusive)
        async let fitnessResult = fetchFitnessData(from: window.start, to: window.endExclusive)
        let (sleepData, steps, activeEnergy, exerciseTime, standHours) = await (
            sleepResult, stepsResult, energyResult, exerciseResult, standResult
        )

        for (date, sleepInfo) in sleepData {
            summaries[date]?.sleepStart = sleepInfo.start
            summaries[date]?.sleepEnd = sleepInfo.end
            summaries[date]?.sleepHours = sleepInfo.duration
            summaries[date]?.sleepStages = sleepInfo.stages.compactMap { interval in
                guard let stage = Self.sleepStageType(for: interval.state) else { return nil }
                return SleepStage(start: interval.start, end: interval.end, stage: stage)
            }
        }
        
        for (date, value) in steps {
            summaries[date]?.steps = Int(value)
        }
        
        for (date, value) in activeEnergy {
            summaries[date]?.activeEnergy = value
        }
        
        for (date, value) in exerciseTime {
            summaries[date]?.exerciseMinutes = value
        }
        
        for (date, value) in standHours {
            summaries[date]?.standHours = value
        }

        for fitness in await fitnessResult {
            summaries[fitness.date]?.activeEnergy = fitness.activeEnergy
            summaries[fitness.date]?.moveMinutes = fitness.moveMinutes
            summaries[fitness.date]?.exerciseMinutes = fitness.exerciseMinutes
            summaries[fitness.date]?.standHours = fitness.standHours
            summaries[fitness.date]?.activeEnergyGoal = fitness.activeEnergyGoal
            summaries[fitness.date]?.moveMinutesGoal = fitness.moveMinutesGoal
            summaries[fitness.date]?.exerciseMinutesGoal = fitness.exerciseMinutesGoal
            summaries[fitness.date]?.standHoursGoal = fitness.standHoursGoal
            summaries[fitness.date]?.fitnessMoveMode = fitness.fitnessMoveMode
        }
        
        return Array(summaries.values).sorted(by: { $0.date > $1.date })
    }
    
    private func fetchSleepData(from startDate: Date, to endDate: Date) async -> [Date: SleepSampleAggregation.DailySummary] {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let calendar = Calendar.current
        guard let bounds = SleepSampleAggregation.queryBounds(from: startDate, to: endDate, calendar: calendar) else {
            return [:]
        }
        // Read whole boundary samples plus the adjacent nights. Session wake-up
        // days, rather than individual stage end dates, select the requested days.
        let predicate = HKQuery.predicateForSamples(withStart: bounds.start, end: bounds.end, options: [])
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                guard let samples = samples as? [HKCategorySample], error == nil else {
                    continuation.resume(returning: [:])
                    return
                }
                
                let normalized = samples.compactMap(Self.sleepSample(for:))
                continuation.resume(returning: SleepSampleAggregation.aggregate(
                    normalized, from: startDate, to: endDate, calendar: calendar
                ))
            }
            healthStore.execute(query)
        }
    }

    nonisolated private static func sleepSample(for sample: HKCategorySample) -> SleepSampleAggregation.Sample? {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
        let state: SleepSampleAggregation.State
        switch value {
        case .inBed: state = .inBed
        case .awake: state = .awake
        case .asleepUnspecified: state = .unspecified
        case .asleepCore: state = .core
        case .asleepDeep: state = .deep
        case .asleepREM: state = .rem
        default:
            return nil
        }
        let deviceIdentifier = sample.device?.localIdentifier ?? sample.sourceRevision.productType ?? ""
        let sourceIdentifier = sample.sourceRevision.source.bundleIdentifier + "|" + deviceIdentifier
        return SleepSampleAggregation.Sample(start: sample.startDate,
                                             end: sample.endDate,
                                             state: state,
                                             sourceIdentifier: sourceIdentifier)
    }

    private static func sleepStageType(for state: SleepSampleAggregation.State) -> SleepStageType? {
        switch state {
        case .awake:
            return .awake
        case .rem:
            return .rem
        case .deep:
            return .deep
        case .core:
            return .core
        case .unspecified:
            return .unspecified
        case .inBed:
            return nil
        }
    }
    
    private func fetchCumulativeQuantity(for identifier: HKQuantityTypeIdentifier, from startDate: Date, to endDate: Date) async -> [Date: Double] {
        let quantityType = HKQuantityType.quantityType(forIdentifier: identifier)!
        let anchorDate = Calendar.current.startOfDay(for: startDate)
        let dailyInterval = DateComponents(day: 1)
        
        let query = HKStatisticsCollectionQuery(quantityType: quantityType,
                                                quantitySamplePredicate: HKQuery.predicateForSamples(
                                                    withStart: startDate, end: endDate, options: []
                                                ),
                                                options: .cumulativeSum,
                                                anchorDate: anchorDate,
                                                intervalComponents: dailyInterval)
        
        return await withCheckedContinuation { continuation in
            query.initialResultsHandler = { query, results, error in
                guard let results = results else {
                    continuation.resume(returning: [:])
                    return
                }
                
                var dailyData: [Date: Double] = [:]
                // enumerateStatistics includes the bucket containing its end
                // date; stop before tomorrow to avoid creating an extra bucket.
                results.enumerateStatistics(from: startDate, to: endDate.addingTimeInterval(-1)) { statistics, stop in
                    if let sum = statistics.sumQuantity() {
                        let unit: HKUnit
                        switch identifier {
                        case .stepCount: unit = .count()
                        case .activeEnergyBurned: unit = .kilocalorie()
                        case .appleExerciseTime: unit = .minute()
                        default: unit = .count()
                        }
                        dailyData[statistics.startDate] = sum.doubleValue(for: unit)
                    }
                }
                continuation.resume(returning: dailyData)
            }
            healthStore.execute(query)
        }
    }
    
    private func fetchStandHours(from startDate: Date, to endDate: Date) async -> [Date: Double] {
        let standType = HKObjectType.categoryType(forIdentifier: .appleStandHour)!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: standType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                guard let samples = samples as? [HKCategorySample], error == nil else {
                    continuation.resume(returning: [:])
                    return
                }
                
                var standDataByDay: [Date: Set<Int>] = [:]
                let calendar = Calendar.current
                
                for sample in samples where sample.value == HKCategoryValueAppleStandHour.stood.rawValue {
                    let day = calendar.startOfDay(for: sample.startDate)
                    let hour = calendar.component(.hour, from: sample.startDate)
                    
                    if standDataByDay[day] != nil {
                        standDataByDay[day]?.insert(hour)
                    } else {
                        standDataByDay[day] = [hour]
                    }
                }
                
                let standHours = standDataByDay.mapValues { Double($0.count) }
                continuation.resume(returning: standHours)
            }
            healthStore.execute(query)
        }
    }
}
