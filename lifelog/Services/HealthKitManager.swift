//
//  HealthKitManager.swift
//  lifelog
//
//  Created by Codex on 2025/11/15.
//

import Foundation
import HealthKit

@MainActor
class HealthKitManager {
    
    static let shared = HealthKitManager()
    let healthStore = HKHealthStore()
    
    private let readTypes: Set<HKObjectType> = [
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
        HKObjectType.categoryType(forIdentifier: .appleStandHour)!
    ]
    
    private init() { }
    
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            return false
        }
        
        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            print("Error requesting HealthKit authorization: \(error.localizedDescription)")
            return false
        }
    }
    
    func fetchHealthData(for lastNDays: Int) async -> [HealthSummary] {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .day, value: -lastNDays, to: endDate) else {
            return []
        }
        
        var summaries: [Date: HealthSummary] = [:]
        for i in 0...lastNDays {
            if let date = calendar.date(byAdding: .day, value: -i, to: endDate) {
                summaries[date] = HealthSummary(date: date)
            }
        }
        
        let sleepData = await fetchSleepData(from: startDate, to: calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate)
        for (date, sleepInfo) in sleepData {
            summaries[date]?.sleepStart = sleepInfo.start
            summaries[date]?.sleepEnd = sleepInfo.end
            summaries[date]?.sleepHours = sleepInfo.duration
            summaries[date]?.sleepStages = sleepInfo.stages.sorted(by: { $0.start < $1.start })
        }
        
        let steps = await fetchCumulativeQuantity(for: .stepCount, from: startDate, to: endDate)
        for (date, value) in steps {
            summaries[date]?.steps = Int(value)
        }
        
        let activeEnergy = await fetchCumulativeQuantity(for: .activeEnergyBurned, from: startDate, to: endDate)
        for (date, value) in activeEnergy {
            summaries[date]?.activeEnergy = value
        }
        
        let exerciseTime = await fetchCumulativeQuantity(for: .appleExerciseTime, from: startDate, to: endDate)
        for (date, value) in exerciseTime {
            summaries[date]?.exerciseMinutes = value
        }
        
        let standHours = await fetchStandHours(from: startDate, to: endDate)
        for (date, value) in standHours {
            summaries[date]?.standHours = value
        }
        
        return Array(summaries.values).sorted(by: { $0.date > $1.date })
    }
    
    private func fetchSleepData(from startDate: Date, to endDate: Date) async -> [Date: SleepAggregate] {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictEndDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                guard let samples = samples as? [HKCategorySample], error == nil else {
                    continuation.resume(returning: [:])
                    return
                }
                
                var sleepDataByDay: [Date: SleepAggregate] = [:]
                let calendar = Calendar.current

                for sample in samples {
                    guard self.isAsleepSample(sample) else { continue }
                    let stageType = self.sleepStageType(for: sample)
                    var segmentStart = sample.startDate
                    let sampleEnd = sample.endDate

                    while segmentStart < sampleEnd {
                        let dayStart = calendar.startOfDay(for: segmentStart)
                        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
                        let clippedStart = max(segmentStart, dayStart)
                        let clippedEnd = min(sampleEnd, dayEnd)
                        let hours = clippedEnd.timeIntervalSince(clippedStart) / 3600

                        var aggregate = sleepDataByDay[dayStart] ?? SleepAggregate(start: clippedStart,
                                                                                   end: clippedEnd,
                                                                                   duration: 0,
                                                                                   stages: [])
                        aggregate.start = min(aggregate.start, clippedStart)
                        aggregate.end = max(aggregate.end, clippedEnd)
                        aggregate.duration += hours
                        if let stageType {
                            aggregate.stages.append(SleepStage(start: clippedStart,
                                                               end: clippedEnd,
                                                               stage: stageType))
                        }
                        sleepDataByDay[dayStart] = aggregate

                        segmentStart = clippedEnd
                    }
                }
                continuation.resume(returning: sleepDataByDay)
            }
            healthStore.execute(query)
        }
    }

    private func isAsleepSample(_ sample: HKCategorySample) -> Bool {
        guard let value = SleepStageValue(rawValue: sample.value) else { return false }
        switch value {
        case .asleep, .asleepUnspecified, .core, .deep, .rem:
            return true
        case .awake, .inBed:
            return false
        }
    }

    private func sleepStageType(for sample: HKCategorySample) -> SleepStageType? {
        guard let stageValue = SleepStageValue(rawValue: sample.value) else {
            return nil
        }

        switch stageValue {
        case .awake:
            return .awake
        case .rem:
            return .rem
        case .deep:
            return .deep
        case .core, .asleepUnspecified, .asleep:
            return .core
        case .inBed:
            return nil
        }
    }
    
    private func fetchCumulativeQuantity(for identifier: HKQuantityTypeIdentifier, from startDate: Date, to endDate: Date) async -> [Date: Double] {
        let quantityType = HKQuantityType.quantityType(forIdentifier: identifier)!
        let anchorDate = Calendar.current.startOfDay(for: startDate)
        let dailyInterval = DateComponents(day: 1)
        
        let query = HKStatisticsCollectionQuery(quantityType: quantityType,
                                                quantitySamplePredicate: nil,
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
                results.enumerateStatistics(from: startDate, to: endDate) { statistics, stop in
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

private struct SleepAggregate {
    var start: Date
    var end: Date
    var duration: Double
    var stages: [SleepStage]
}

private enum SleepStageValue: Int {
    case inBed
    case asleep
    case awake
    case asleepUnspecified
    case core
    case deep
    case rem
}
