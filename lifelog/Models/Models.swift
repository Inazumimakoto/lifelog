//
//  Models.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import SwiftUI
import EventKit
import CoreLocation
#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - Enumerations

enum TaskPriority: Int, Codable, CaseIterable, Identifiable, Comparable {
    case high = 3
    case medium = 2
    case low = 1

    var id: Int { rawValue }

    static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }

    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

enum HabitSchedule: Codable, Identifiable, Hashable {
    case daily
    case weekdays
    case custom(days: [Weekday])

    var id: String {
        switch self {
        case .daily: return "daily"
        case .weekdays: return "weekdays"
        case .custom(let days): return "custom-\(days.map { String($0.rawValue) }.joined(separator: "-"))"
        }
    }

    func isActive(on date: Date) -> Bool {
        switch self {
        case .daily:
            return true
        case .weekdays:
            return Calendar.current.isDateInWeekend(date) == false
        case .custom(let days):
            let weekday = Weekday(date: date)
            return days.contains(weekday)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case days
    }

    private enum ScheduleType: String, Codable {
        case daily, weekdays, custom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ScheduleType.self, forKey: .type)
        switch type {
        case .daily:
            self = .daily
        case .weekdays:
            self = .weekdays
        case .custom:
            let days = try container.decode([Weekday].self, forKey: .days)
            self = .custom(days: days)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .daily:
            try container.encode(ScheduleType.daily, forKey: .type)
        case .weekdays:
            try container.encode(ScheduleType.weekdays, forKey: .type)
        case .custom(let days):
            try container.encode(ScheduleType.custom, forKey: .type)
            try container.encode(days, forKey: .days)
        }
    }
}

enum AnniversaryType: String, Codable, CaseIterable, Identifiable {
    case countdown
    case since

    var id: String { rawValue }
}

enum MoodLevel: Int, Codable, CaseIterable, Identifiable {
    case veryLow = 1
    case low = 2
    case neutral = 3
    case high = 4
    case veryHigh = 5

    var id: Int { rawValue }

    var emoji: String {
        switch self {
        case .veryLow: return "😢"
        case .low: return "🙁"
        case .neutral: return "😐"
        case .high: return "🙂"
        case .veryHigh: return "😄"
        }
    }
}

enum Weekday: Int, CaseIterable, Identifiable, Codable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    init(date: Date) {
        let weekday = Calendar.current.component(.weekday, from: date)
        self = Weekday(rawValue: weekday) ?? .monday
    }

    var id: Int { rawValue }

    var shortLabel: String {
        switch self {
        case .sunday: return "日"
        case .monday: return "月"
        case .tuesday: return "火"
        case .wednesday: return "水"
        case .thursday: return "木"
        case .friday: return "金"
        case .saturday: return "土"
        }
    }
}

struct MorningRoutineStep: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var durationMinutes: Int

    init(id: UUID = UUID(), title: String, durationMinutes: Int) {
        self.id = id
        self.title = title
        self.durationMinutes = max(1, durationMinutes)
    }
}

struct MorningRoutinePreset: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var steps: [MorningRoutineStep]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        steps: [MorningRoutineStep],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.steps = Self.normalizedSteps(steps)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func normalizedSteps(_ steps: [MorningRoutineStep]) -> [MorningRoutineStep] {
        steps.map {
            MorningRoutineStep(
                id: $0.id,
                title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                durationMinutes: max(1, $0.durationMinutes)
            )
        }
        .filter { $0.title.isEmpty == false }
    }

    static func defaultTemplateSteps() -> [MorningRoutineStep] {
        [
            MorningRoutineStep(title: "ベッドメイク", durationMinutes: 2),
            MorningRoutineStep(title: "トイレ", durationMinutes: 2),
            MorningRoutineStep(title: "水分補給", durationMinutes: 1),
            MorningRoutineStep(title: "シャワー", durationMinutes: 10),
            MorningRoutineStep(title: "ヘアセット", durationMinutes: 10),
            MorningRoutineStep(title: "服を着る", durationMinutes: 5),
            MorningRoutineStep(title: "朝ごはん", durationMinutes: 30),
        ]
    }

    var totalDurationMinutes: Int {
        steps.reduce(0) { $0 + $1.durationMinutes }
    }

    var summaryText: String {
        "\(steps.count)ステップ・\(totalDurationMinutes)分"
    }

    var previewText: String {
        steps.prefix(3).map(\.title).joined(separator: " → ")
    }
}

struct MorningRoutineTimelineStep: Identifiable, Hashable {
    let id: UUID
    let index: Int
    let title: String
    let durationMinutes: Int
    let startAt: Date
    let endAt: Date
}

struct MorningRoutineProgress: Hashable {
    let timeline: [MorningRoutineTimelineStep]
    let currentStep: MorningRoutineTimelineStep?
    let completedStepCount: Int
    let totalDuration: TimeInterval
    let elapsedDuration: TimeInterval

    var overallEndAt: Date? {
        timeline.last?.endAt
    }

    var isFinished: Bool {
        currentStep == nil && timeline.isEmpty == false && completedStepCount >= timeline.count
    }

    var remainingSteps: [MorningRoutineTimelineStep] {
        guard let currentStep else { return [] }
        return timeline.filter { $0.index > currentStep.index }
    }

    var completionFraction: Double {
        guard totalDuration > 0 else { return 1 }
        return min(max(elapsedDuration / totalDuration, 0), 1)
    }
}

enum MorningRoutineRuntime {
    static func timeline(steps: [MorningRoutineStep], startingAt startDate: Date) -> [MorningRoutineTimelineStep] {
        var cursor = startDate
        return steps.enumerated().map { index, step in
            let endDate = cursor.addingTimeInterval(TimeInterval(step.durationMinutes * 60))
            defer { cursor = endDate }
            return MorningRoutineTimelineStep(
                id: step.id,
                index: index,
                title: step.title,
                durationMinutes: step.durationMinutes,
                startAt: cursor,
                endAt: endDate
            )
        }
    }

    static func progress(steps: [MorningRoutineStep], startingAt startDate: Date, at date: Date = Date()) -> MorningRoutineProgress {
        let timeline = timeline(steps: steps, startingAt: startDate)
        let totalDuration = max(0, (timeline.last?.endAt.timeIntervalSince(startDate)) ?? 0)
        let elapsedDuration = min(max(date.timeIntervalSince(startDate), 0), totalDuration)
        let currentStep = timeline.first(where: { date < $0.endAt })
        let completedStepCount = timeline.filter { $0.endAt <= date }.count

        return MorningRoutineProgress(
            timeline: timeline,
            currentStep: currentStep,
            completedStepCount: completedStepCount,
            totalDuration: totalDuration,
            elapsedDuration: elapsedDuration
        )
    }
}

struct MorningRoutineSession: Identifiable, Codable, Hashable {
    let id: UUID
    var presetID: UUID?
    var title: String
    var steps: [MorningRoutineStep]
    var sourceAlarmID: UUID?
    var startedAt: Date

    init(
        id: UUID = UUID(),
        presetID: UUID? = nil,
        title: String,
        steps: [MorningRoutineStep],
        sourceAlarmID: UUID? = nil,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.presetID = presetID
        self.title = title
        self.steps = MorningRoutinePreset.normalizedSteps(steps)
        self.sourceAlarmID = sourceAlarmID
        self.startedAt = startedAt
    }

    init(preset: MorningRoutinePreset, sourceAlarmID: UUID? = nil, startedAt: Date = Date()) {
        self.init(
            presetID: preset.id,
            title: preset.title,
            steps: preset.steps,
            sourceAlarmID: sourceAlarmID,
            startedAt: startedAt
        )
    }

    var progress: MorningRoutineProgress {
        progress(at: Date())
    }

    func progress(at date: Date) -> MorningRoutineProgress {
        MorningRoutineRuntime.progress(steps: steps, startingAt: startedAt, at: date)
    }

    var plannedEndAt: Date {
        progress(at: startedAt).overallEndAt ?? startedAt
    }

    func isFinished(at date: Date = Date()) -> Bool {
        progress(at: date).isFinished
    }
}

enum MorningRoutineError: LocalizedError {
    case presetNotFound
    case emptyPreset

    var errorDescription: String? {
        switch self {
        case .presetNotFound:
            return "指定したルーティンプリセットが見つかりません。"
        case .emptyPreset:
            return "ルーティンには最低1つのステップが必要です。"
        }
    }
}

#if canImport(ActivityKit)
@available(iOS 17.0, *)
struct MorningRoutineActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isRunning: Bool
    }

    var sessionID: UUID
    var routineTitle: String
    var startedAt: Date
    var steps: [MorningRoutineStep]
}
#endif

// MARK: - Core Models

struct CalendarCategoryLink: Identifiable, Codable, Equatable {
    /// EventKit の EKCalendar.calendarIdentifier
    let calendarIdentifier: String
    /// 表示用タイトル
    var calendarTitle: String
    /// 対応させる lifelog カテゴリ名（nilなら取り込まない）
    var categoryId: String?
    /// iOSカレンダーの色 (hex)
    var colorHex: String?

    var id: String { calendarIdentifier }
}

struct MemoPad: Codable, Hashable {
    var text: String
    var lastUpdatedAt: Date?

    init(text: String = "", lastUpdatedAt: Date? = nil) {
        self.text = text
        self.lastUpdatedAt = lastUpdatedAt
    }
}

struct Task: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var detail: String
    var startDate: Date?
    var endDate: Date?
    var priority: TaskPriority
    var isCompleted: Bool
    var reminderDate: Date?
    var completedAt: Date?

    init(id: UUID = UUID(),
         title: String,
         detail: String = "",
         startDate: Date? = nil,
         endDate: Date? = nil,
         priority: TaskPriority = .medium,
         isCompleted: Bool = false,
         reminderDate: Date? = nil,
         completedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.startDate = startDate
        self.endDate = endDate
        self.priority = priority
        self.isCompleted = isCompleted
        self.reminderDate = reminderDate
        self.completedAt = completedAt
    }
}

struct DiaryLocation: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var address: String?
    var latitude: Double
    var longitude: Double
    var mapItemURL: String?
    var photoPaths: [String]
    var visitTags: [String]

    init(id: UUID = UUID(),
         name: String,
         address: String?,
         latitude: Double,
         longitude: Double,
         mapItemURL: String?,
         photoPaths: [String] = [],
         visitTags: [String] = []) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.mapItemURL = mapItemURL
        self.photoPaths = photoPaths
        self.visitTags = visitTags
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, address, latitude, longitude, mapItemURL, photoPaths, visitTags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        mapItemURL = try container.decodeIfPresent(String.self, forKey: .mapItemURL)
        photoPaths = try container.decodeIfPresent([String].self, forKey: .photoPaths) ?? []
        visitTags = try container.decodeIfPresent([String].self, forKey: .visitTags) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(address, forKey: .address)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encodeIfPresent(mapItemURL, forKey: .mapItemURL)
        try container.encode(photoPaths, forKey: .photoPaths)
        try container.encode(visitTags, forKey: .visitTags)
    }
}

struct LocationVisitTagDefinition: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var sortOrder: Int
    var createdAt: Date

    init(id: UUID = UUID(),
         name: String,
         sortOrder: Int,
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

struct DiaryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var date: Date
    var text: String
    var mood: MoodLevel?
    var conditionScore: Int?
    var locations: [DiaryLocation]
    var locationName: String?
    var latitude: Double?
    var longitude: Double?
    var photoPaths: [String]
    var locationPhotoPaths: [String]
    // Will be used later to surface a day's favorite shot in the calendar/album view.
    var favoritePhotoPath: String?

    init(id: UUID = UUID(),
         date: Date,
         text: String,
         mood: MoodLevel? = .neutral,
         conditionScore: Int? = 3,
         locations: [DiaryLocation] = [],
         locationName: String? = nil,
         latitude: Double? = nil,
         longitude: Double? = nil,
         photoPaths: [String] = [],
         locationPhotoPaths: [String] = [],
         favoritePhotoPath: String? = nil) {
        self.id = id
        self.date = date
        self.text = text
        self.mood = mood
        self.conditionScore = conditionScore
        if locations.isEmpty, let name = locationName, let lat = latitude, let lon = longitude {
            self.locations = [
                DiaryLocation(name: name,
                              address: nil,
                              latitude: lat,
                              longitude: lon,
                              mapItemURL: nil,
                              photoPaths: [])
            ]
        } else {
            self.locations = locations
        }
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.photoPaths = photoPaths
        self.locationPhotoPaths = locationPhotoPaths
        self.favoritePhotoPath = favoritePhotoPath
    }
}

struct Habit: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var iconName: String
    var colorHex: String
    var schedule: HabitSchedule
    var isArchived: Bool
    var createdAt: Date
    var archivedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, iconName, colorHex, schedule, isArchived, createdAt, archivedAt
    }

    init(id: UUID = UUID(),
         title: String,
         iconName: String,
         colorHex: String,
         schedule: HabitSchedule,
         isArchived: Bool = false,
         createdAt: Date = Date(),
         archivedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.colorHex = colorHex
        self.schedule = schedule
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        iconName = try container.decode(String.self, forKey: .iconName)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        schedule = try container.decode(HabitSchedule.self, forKey: .schedule)
        // New fields: use defaults if missing
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date.distantPast
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
    }
}

struct HabitRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var habitID: UUID
    var date: Date
    var isCompleted: Bool

    init(id: UUID = UUID(),
         habitID: UUID,
         date: Date,
         isCompleted: Bool) {
        self.id = id
        self.habitID = habitID
        self.date = date
        self.isCompleted = isCompleted
    }
}

struct Anniversary: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var targetDate: Date
    var type: AnniversaryType
    var repeatsYearly: Bool
    var startDate: Date?              // 開始日（プログレスバー用）
    var startLabel: String?           // 開始ラベル（例：「生まれてから」）
    var endLabel: String?             // 終了ラベル（例：「100歳まで」）
    var reminderDaysBefore: Int?
    var reminderTime: Date?
    var reminderDate: Date?

    init(id: UUID = UUID(),
         title: String,
         targetDate: Date,
         type: AnniversaryType,
         repeatsYearly: Bool,
         startDate: Date? = nil,
         startLabel: String? = nil,
         endLabel: String? = nil,
         reminderDaysBefore: Int? = nil,
         reminderTime: Date? = nil,
         reminderDate: Date? = nil) {
        self.id = id
        self.title = title
        self.targetDate = targetDate
        self.type = type
        self.repeatsYearly = repeatsYearly
        self.startDate = startDate
        self.startLabel = startLabel
        self.endLabel = endLabel
        self.reminderDaysBefore = reminderDaysBefore
        self.reminderTime = reminderTime
        self.reminderDate = reminderDate
    }

    func daysRelative(to date: Date) -> Int {
        let calendar = Calendar.current
        let reference = repeatsYearly
            ? calendar.nextDate(after: date, matching: calendar.dateComponents([.month, .day], from: targetDate), matchingPolicy: .nextTimePreservingSmallerComponents) ?? targetDate
            : targetDate
        let startOfToday = calendar.startOfDay(for: date)
        let startOfTarget = calendar.startOfDay(for: reference)
        guard let days = calendar.dateComponents([.day], from: startOfToday, to: startOfTarget).day else {
            return 0
        }
        return days
    }
    
    /// 開始日からの進捗（0.0〜1.0）、開始日が未設定の場合はnil
    func progress(on date: Date) -> Double? {
        guard let start = startDate else { return nil }
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let targetDay = calendar.startOfDay(for: targetDate)
        let today = calendar.startOfDay(for: date)
        
        let totalDays = calendar.dateComponents([.day], from: startDay, to: targetDay).day ?? 0
        guard totalDays > 0 else { return nil }
        
        let elapsedDays = calendar.dateComponents([.day], from: startDay, to: today).day ?? 0
        let progress = Double(elapsedDays) / Double(totalDays)
        return min(max(progress, 0), 1)  // 0〜1にクランプ
    }
    
    /// 全期間の日数
    var totalDays: Int? {
        guard let start = startDate else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: targetDate)).day
    }
    
    /// 開始日からの経過日数
    func elapsedDays(on date: Date) -> Int? {
        guard let start = startDate else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: date)).day
    }
    
    /// 終了日までの残り日数
    func remainingDays(on date: Date) -> Int? {
        guard startDate != nil else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: targetDate)).day
    }
}

struct HealthSummary: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var date: Date
    var steps: Int?
    var sleepHours: Double?
    var activeEnergy: Double?
    var moveMinutes: Double?
    var exerciseMinutes: Double?
    var standHours: Double?
    var sleepStart: Date?
    var sleepEnd: Date?
    var sleepStages: [SleepStage] = []
    
    // 天気データ
    var weatherCondition: String?      // 天気状態（晴れ、曇り、雨など）
    var highTemperature: Double?       // 最高気温
    var lowTemperature: Double?        // 最低気温
    
    init(date: Date) {
        self.date = date
    }
    
    /// 天気の説明文（AI分析用）
    var weatherDescription: String? {
        guard let condition = weatherCondition else { return nil }
        var parts = [condition]
        if let high = highTemperature, let low = lowTemperature {
            parts.append("最高\(Int(high))°C/最低\(Int(low))°C")
        }
        return parts.joined(separator: "、")
    }
}

struct CalendarEvent: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var calendarName: String
    var isAllDay: Bool
    var sourceCalendarIdentifier: String?
    var reminderMinutes: Int?
    var reminderDate: Date?

    init(id: UUID = UUID(),
         title: String,
         startDate: Date,
         endDate: Date,
         calendarName: String,
         isAllDay: Bool = false,
         sourceCalendarIdentifier: String? = nil,
         reminderMinutes: Int? = nil,
         reminderDate: Date? = nil) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.calendarName = calendarName
        self.isAllDay = isAllDay
        self.sourceCalendarIdentifier = sourceCalendarIdentifier
        self.reminderMinutes = reminderMinutes
        self.reminderDate = reminderDate
    }
}

extension CalendarEvent {
    init(event: EKEvent, categoryName: String) {
        self.init(id: UUID(),
                  title: event.title,
                  startDate: event.startDate,
                  endDate: event.endDate,
                  calendarName: categoryName,
                  isAllDay: event.isAllDay,
                  sourceCalendarIdentifier: event.calendar.calendarIdentifier)
    }
}

enum SleepStageType: String, Codable, CaseIterable, Identifiable {
    case awake
    case rem
    case core
    case deep

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .awake: return "覚醒"
        case .rem: return "レム"
        case .core: return "コア"
        case .deep: return "深い"
        }
    }

    var color: Color {
        switch self {
        case .awake: return .orange
        case .rem: return .pink
        case .core: return .blue
        case .deep: return .indigo
        }
    }

    static var timelineOrder: [SleepStageType] { [.awake, .rem, .core, .deep] }
}

struct SleepStage: Identifiable, Codable, Hashable {
    let id = UUID()
    var start: Date
    var end: Date
    var stage: SleepStageType

    var durationMinutes: Double {
        end.timeIntervalSince(start) / 60
    }
}

extension SleepStage {
    static func demoSequence(referenceDate: Date = Date()) -> [SleepStage] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: referenceDate)
        guard
            let previousEvening = calendar.date(byAdding: .hour, value: -3, to: startOfDay),
            let bedtime = calendar.date(byAdding: .hour, value: -1, to: startOfDay),
            let midnight = calendar.date(byAdding: .hour, value: 0, to: startOfDay),
            let earlyMorning = calendar.date(byAdding: .hour, value: 3, to: startOfDay),
            let wakeUp = calendar.date(byAdding: .hour, value: 6, to: startOfDay)
        else {
            return []
        }

        return [
            SleepStage(start: previousEvening,
                       end: bedtime,
                       stage: .awake),
            SleepStage(start: bedtime,
                       end: midnight,
                       stage: .core),
            SleepStage(start: midnight,
                       end: earlyMorning,
                       stage: .deep),
            SleepStage(start: earlyMorning,
                       end: earlyMorning.addingTimeInterval(60 * 60),
                       stage: .rem),
            SleepStage(start: earlyMorning.addingTimeInterval(60 * 60),
                       end: wakeUp,
                       stage: .core)
        ]
    }
}

// MARK: - Letter to the Future

enum LetterDeliveryType: String, Codable, CaseIterable, Identifiable {
    case fixed
    case random
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .fixed: return "固定"
        case .random: return "ランダム"
        }
    }
}

enum LetterStatus: String, Codable, CaseIterable, Identifiable {
    case draft       // 下書き
    case sealed      // 封印済み（開封待ち）
    case deliverable // 開封可能
    case opened      // 開封済み
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .draft: return "下書き"
        case .sealed: return "送信済み"
        case .deliverable: return "開封可能"
        case .opened: return "開封済み"
        }
    }
}

struct LetterRandomSettings: Codable, Hashable {
    var useDateRange: Bool
    var startDate: Date?
    var endDate: Date?
    var useTimeRange: Bool
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    
    // 新規追加: 日付固定・時間ランダム or 日付ランダム・時間固定 のサポート
    var fixedDate: Date?      // 日付が固定の場合
    var fixedHour: Int?       // 時刻が固定の場合
    var fixedMinute: Int?     // 時刻が固定の場合
    
    init(useDateRange: Bool = false,
         startDate: Date? = nil,
         endDate: Date? = nil,
         useTimeRange: Bool = false,
         startHour: Int = 9,
         startMinute: Int = 0,
         endHour: Int = 21,
         endMinute: Int = 0,
         fixedDate: Date? = nil,
         fixedHour: Int? = nil,
         fixedMinute: Int? = nil) {
        self.useDateRange = useDateRange
        self.startDate = startDate
        self.endDate = endDate
        self.useTimeRange = useTimeRange
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.fixedDate = fixedDate
        self.fixedHour = fixedHour
        self.fixedMinute = fixedMinute
    }
    
    /// ランダムな配達日時を生成
    func generateDeliveryDate() -> Date {
        let calendar = Calendar.current
        let now = Date()
        
        // 日付の決定
        let deliveryDay: Date
        
        if let fixed = fixedDate {
            // 日付固定
            deliveryDay = fixed
        } else if useDateRange, let start = startDate, let end = endDate {
            // 期間指定ランダム
            let dayRange = calendar.dateComponents([.day], from: start, to: end).day ?? 1
            let randomDays = Int.random(in: 0...max(0, dayRange))
            deliveryDay = calendar.date(byAdding: .day, value: randomDays, to: start) ?? start
        } else {
            // 完全ランダム: 1日後 〜 3年後
            let rangeStart = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            let rangeEnd = calendar.date(byAdding: .year, value: 3, to: now) ?? now
            let dayRange = calendar.dateComponents([.day], from: rangeStart, to: rangeEnd).day ?? 1
            let randomDays = Int.random(in: 0...max(0, dayRange))
            deliveryDay = calendar.date(byAdding: .day, value: randomDays, to: rangeStart) ?? rangeStart
        }
        
        // 時間の決定
        let hour: Int
        let minute: Int
        
        if let fh = fixedHour, let fm = fixedMinute {
            // 時刻固定
            hour = fh
            minute = fm
        } else if useTimeRange {
            // 時間帯ランダム
            let startTotalMinutes = startHour * 60 + startMinute
            let endTotalMinutes = endHour * 60 + endMinute
            let randomTotalMinutes = Int.random(in: startTotalMinutes..<max(startTotalMinutes + 1, endTotalMinutes))
            hour = randomTotalMinutes / 60
            minute = randomTotalMinutes % 60
        } else {
            // 終日ランダム
            hour = Int.random(in: 0...23)
            minute = Int.random(in: 0...59)
        }
        
        let deliveryDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: deliveryDay) ?? deliveryDay
        
        return deliveryDate
    }
}

struct Letter: Identifiable, Codable, Hashable {
    let id: UUID
    var content: String
    var photoPaths: [String]
    var createdAt: Date
    var deliveryType: LetterDeliveryType
    var deliveryDate: Date
    var randomSettings: LetterRandomSettings?
    var status: LetterStatus
    var openedAt: Date?
    var dismissedFromHome: Bool  // ホームから非表示にしたか
    
    init(id: UUID = UUID(),
         content: String = "",
         photoPaths: [String] = [],
         createdAt: Date = Date(),
         deliveryType: LetterDeliveryType = .fixed,
         deliveryDate: Date = Date().addingTimeInterval(60 * 60 * 24), // 1日後デフォルト
         randomSettings: LetterRandomSettings? = nil,
         status: LetterStatus = .draft,
         openedAt: Date? = nil,
         dismissedFromHome: Bool = false) {
        self.id = id
        self.content = content
        self.photoPaths = photoPaths
        self.createdAt = createdAt
        self.deliveryType = deliveryType
        self.deliveryDate = deliveryDate
        self.randomSettings = randomSettings
        self.status = status
        self.openedAt = openedAt
        self.dismissedFromHome = dismissedFromHome
    }
    
    /// 開封可能かどうか
    var isDeliverable: Bool {
        status == .sealed && Date() >= deliveryDate
    }
    
    /// ホームに表示すべきかどうか
    /// - 開封可能（未開封）な手紙
    /// - または、開封済みだが配達日が今日の手紙
    /// - ただし、ユーザーが非表示にした場合は除く
    var shouldShowOnHome: Bool {
        if dismissedFromHome { return false }
        
        // 開封可能（未開封）
        if isDeliverable { return true }
        
        // 開封済みだが配達日が今日
        if status == .opened {
            let calendar = Calendar.current
            return calendar.isDateInToday(deliveryDate)
        }
        
        return false
    }
    
    /// 手紙を封印する
    mutating func seal() {
        if deliveryType == .random, let settings = randomSettings {
            deliveryDate = settings.generateDeliveryDate()
        }
        status = .sealed
    }
    
    /// 手紙を開封する
    mutating func open() {
        status = .opened
        openedAt = Date()
    }
    
    /// ホームから非表示にする
    mutating func dismissFromHome() {
        dismissedFromHome = true
    }
}

// MARK: - SharedLetter (Letter from Others)

/// 他のユーザーから受け取った手紙（復号済み、ローカル保存）
struct SharedLetter: Identifiable, Codable, Equatable {
    var id: String  // FirestoreのdocumentID
    var senderId: String
    var senderEmoji: String
    var senderName: String
    var content: String
    var photoPaths: [String]  // ローカル保存された写真パス
    var deliveredAt: Date
    var openedAt: Date
}
