//
//  AppDataStore.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import Combine
import HealthKit
import EventKit
import UserNotifications
import SwiftUI
import SwiftData
import WidgetKit
import os

@MainActor
final class AppDataStore: ObservableObject {

    // MARK: - Published Sources

    @Published var tasks: [Task] = []
    @Published var diaryEntries: [DiaryEntry] = []
    @Published var habits: [Habit] = []
    @Published var habitRecords: [HabitRecord] = []
    @Published var anniversaries: [Anniversary] = []
    @Published private(set) var healthSummaries: [HealthSummary] = []
    @Published var calendarEvents: [CalendarEvent] = []
    @Published var memoPad: MemoPad = MemoPad()
    @Published var externalCalendarEvents: [CalendarEvent] = []
    @Published var letters: [Letter] = []
    @Published var sharedLetters: [SharedLetter] = []  // 他ユーザーからの手紙
    @Published var appState: AppState = AppState()
    @Published var locationVisitTagDefinitions: [LocationVisitTagDefinition] = []

    // MARK: - Cache
    var eventsCache: [Date: [CalendarEvent]] = [:]
    var externalCalendarRange: ExternalCalendarRange? = nil
    var externalReminderRescheduleGeneration: UInt = 0
    private(set) var hasExistingUserFootprintForInitialPermissions = false

    // MARK: - Legacy Persistence Keys
    static let tasksDefaultsKey = "Tasks_Storage_V1"
    static let diaryDefaultsKey = "DiaryEntries_Storage_V1"
    static let habitsDefaultsKey = "Habits_Storage_V1"
    static let habitRecordsDefaultsKey = "HabitRecords_Storage_V1"
    static let anniversariesDefaultsKey = "Anniversaries_Storage_V1"
    static let calendarEventsDefaultsKey = "CalendarEvents_Storage_V1"
    // キー文字列の正は共有 EventQuerying。値は不変のまま参照だけ集約する。
    static let externalCalendarEventsDefaultsKey = EventQuerying.externalCalendarEventsDefaultsKey
    static let externalCalendarRangeDefaultsKey = EventQuerying.externalCalendarRangeDefaultsKey
    static let memoPadDefaultsKey = "MemoPad_Storage_V1"
    static let appStateDefaultsKey = "AppState_Storage_V1"
    static let healthSummariesDefaultsKey = "HealthSummaries_Storage_V1"
    static let locationVisitTagsDefaultsKey = "LocationVisitTags_Storage_V1"
    static let locationVisitTagsSeededDefaultsKey = "LocationVisitTagsSeeded_Storage_V1"
    static let defaultLocationVisitTagNames: [String] = [
        "ご飯", "カフェ", "仕事", "勉強", "買い物", "旅行", "観光", "運動", "用事", "友人", "家族", "デート"
    ]
    #if DEBUG
    static let screenshotsModeLaunchArguments: Set<String> = [
        "-screenshots-mode",
        "-ScreenshotsMode",
    ]
    #endif

    // MARK: - SwiftData Context
    let modelContext: ModelContext

    static let maxLocationVisitTagsPerVisit = 8
    static let maxLocationVisitTagNameLength = 15

    enum LocationVisitTagError: LocalizedError {
        case emptyName
        case nameTooLong(max: Int)
        case duplicateName
        case tagNotFound

        var errorDescription: String? {
            switch self {
            case .emptyName:
                return "タグ名を入力してください。"
            case .nameTooLong(let max):
                return "タグ名は\(max)文字以内で入力してください。"
            case .duplicateName:
                return "同じ名前のタグが既にあります。"
            case .tagNotFound:
                return "対象のタグが見つかりませんでした。"
            }
        }
    }

    // MARK: - Init

    init() {
        // Setup SwiftData
        let container = PersistenceController.shared.container
        self.modelContext = container.mainContext

        // 1. Run Migration (if needed)
        MigrationManager.shared.migrate(modelContext: modelContext)

        // 2. Load Data from SwiftData
        // We load into the existing @Published properties to maintain View compatibility
        // Note: We use helper methods to fetch and map SD models to structs

        do {
            // Tasks
            let sdTasks = try modelContext.fetch(FetchDescriptor<SDTask>())
            self.tasks = sdTasks.map { Task(sd: $0) }

            // DiaryEntries
            let sdDiaries = try modelContext.fetch(FetchDescriptor<SDDiaryEntry>())
            let mappedDiaries = sdDiaries.map { DiaryEntry(sd: $0) }
            self.diaryEntries = Self.normalizeDiaryEntries(mappedDiaries)

            // Habits
            let sdHabits = try modelContext.fetch(FetchDescriptor<SDHabit>(sortBy: [SortDescriptor(\.orderIndex)]))
            self.habits = sdHabits.map { Habit(sd: $0) }

            // HabitRecords
            let sdRecords = try modelContext.fetch(FetchDescriptor<SDHabitRecord>())
            self.habitRecords = sdRecords.map { HabitRecord(sd: $0) }

            // Anniversaries
            let sdAnniversaries = try modelContext.fetch(FetchDescriptor<SDAnniversary>(sortBy: [SortDescriptor(\.orderIndex)]))
            self.anniversaries = sdAnniversaries.map { Anniversary(sd: $0) }

            // CalendarEvents (Internal)
            let sdEvents = try modelContext.fetch(FetchDescriptor<SDCalendarEvent>())
            self.calendarEvents = sdEvents.map { CalendarEvent(sd: $0) }

            // Letters
            let sdLetters = try modelContext.fetch(FetchDescriptor<SDLetter>())
            self.letters = sdLetters.map { Letter(sd: $0) }

            // SharedLetters (他ユーザーからの手紙)
            let sdSharedLetters = try modelContext.fetch(FetchDescriptor<SDSharedLetter>(sortBy: [SortDescriptor(\.openedAt, order: .reverse)]))
            self.sharedLetters = sdSharedLetters.map { SharedLetter(sd: $0) }

            // HealthSummaries (Cache)
            let sdHealth = try modelContext.fetch(FetchDescriptor<SDHealthSummary>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
            self.healthSummaries = sdHealth.map { HealthSummary(sd: $0) }

            // MemoPad
            let sdMemos = try modelContext.fetch(FetchDescriptor<SDMemoPad>())
            if let first = sdMemos.first {
                self.memoPad = MemoPad(sd: first)
            } else {
                self.memoPad = MemoPad()
            }

            // AppState
            let sdStates = try modelContext.fetch(FetchDescriptor<SDAppState>())
            if let first = sdStates.first {
                self.appState = AppState(sd: first)
            } else {
                self.appState = AppState()
            }

        } catch {
            AppLogger.data.error("Failed to fetch initial data from SwiftData: \(error)")
        }

        self.externalCalendarEvents = Self.loadValue(forKey: Self.externalCalendarEventsDefaultsKey, defaultValue: [])
        let storedRange: ExternalCalendarRange? = Self.loadValue(forKey: Self.externalCalendarRangeDefaultsKey, defaultValue: nil)
        self.externalCalendarRange = storedRange
        self.locationVisitTagDefinitions = Self.loadValue(forKey: Self.locationVisitTagsDefaultsKey, defaultValue: [])
        normalizeLocationVisitTagOrderIfNeeded()
        let hasSeenInitialPermissionsFeature = UserDefaults.standard.bool(forKey: InitialPermissionsState.featureSeenKey)
        hasExistingUserFootprintForInitialPermissions = hasUserContentForInitialPermissions ||
            Self.hasStoredUserDefaultsFootprintForInitialPermissions(
                includeAutoSeededKeys: hasSeenInitialPermissionsFeature == false
            )
        UserDefaults.standard.set(true, forKey: InitialPermissionsState.featureSeenKey)
        seedDefaultLocationVisitTagsIfNeeded()

        reapplyEventCategoryNotificationSettings()
        rescheduleTodayOverviewReminderIfNeeded()

        #if DEBUG
        seedSampleDataIfNeeded()
        seedJapaneseScheduleForScreenshotsIfNeeded()
        #endif
        _Concurrency.Task {
            await backfillHealthRequestedFlagIfNeeded()
            await loadHealthData()
        }
        _Concurrency.Task {
            // 起動直後の描画やデータ読込と競合しないよう少し待ってから、
            // 許可済みの場合のみ外部カレンダーを再読込する(権限ダイアログは出さない)
            try? await _Concurrency.Task.sleep(nanoseconds: 2_000_000_000)
            if await syncExternalCalendarsIfAuthorized() {
                WidgetCenter.shared.reloadTimelines(ofKind: "ScheduleWidget")
            }
        }
    }

    private var hasUserContentForInitialPermissions: Bool {
        !tasks.isEmpty ||
        !diaryEntries.isEmpty ||
        !habits.isEmpty ||
        !habitRecords.isEmpty ||
        !anniversaries.isEmpty ||
        !calendarEvents.isEmpty ||
        !externalCalendarEvents.isEmpty ||
        !letters.isEmpty ||
        !sharedLetters.isEmpty ||
        !healthSummaries.isEmpty ||
        memoPad.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
        memoPad.lastUpdatedAt != nil ||
        appState.lastCalendarSyncDate != nil ||
        appState.calendarCategoryLinks.isEmpty == false ||
        appState.diaryReminderEnabled
    }

    /// 初期権限セットアップ導入(v1.14)以前からのユーザーはセットアップ画面を
    /// スキップするため healthRequestedKey が立たず、起動時のヘルスデータ取得が
    /// 止まっていた。HealthKit に権限ダイアログ表示済みかを問い合わせて埋め戻す。
    private func backfillHealthRequestedFlagIfNeeded() async {
        guard UserDefaults.standard.bool(forKey: InitialPermissionsState.healthRequestedKey) == false else { return }
        guard await HealthKitManager.shared.hasPreviouslyRequestedAuthorization() else { return }
        UserDefaults.standard.set(true, forKey: InitialPermissionsState.healthRequestedKey)
    }

    @discardableResult
    func loadHealthData(requestAuthorizationIfNeeded: Bool = false) async -> Bool {
        if requestAuthorizationIfNeeded {
            UserDefaults.standard.set(true, forKey: InitialPermissionsState.healthRequestedKey)
            let authorizationCompleted = await HealthKitManager.shared.requestAuthorization()
            guard authorizationCompleted else { return false }
        } else {
            guard UserDefaults.standard.bool(forKey: InitialPermissionsState.healthRequestedKey) else {
                return false
            }
        }

        // Fetch recent 7 days for quick update, then full year in background.
        let recentFetched = await HealthKitManager.shared.fetchHealthData(for: 7)
        if !recentFetched.isEmpty {
            mergeHealthSummaries(recentFetched)
        }

        let fullFetched = await HealthKitManager.shared.fetchHealthData(for: 365)
        if !fullFetched.isEmpty {
            mergeHealthSummaries(fullFetched)
            persistHealthSummaries()
        }

        return true
    }

    private func mergeHealthSummaries(_ newData: [HealthSummary]) {
        var summaryDict = Dictionary(uniqueKeysWithValues: healthSummaries.map { ($0.date, $0) })
        for summary in newData {
            if var existing = summaryDict[summary.date] {
                // 既存データがある場合は、天気データを保持しながらマージ
                // HealthKitデータで更新
                existing.steps = summary.steps ?? existing.steps
                existing.sleepHours = summary.sleepHours ?? existing.sleepHours
                existing.sleepStart = summary.sleepStart ?? existing.sleepStart
                existing.sleepEnd = summary.sleepEnd ?? existing.sleepEnd
                existing.activeEnergy = summary.activeEnergy ?? existing.activeEnergy
                existing.moveMinutes = summary.moveMinutes ?? existing.moveMinutes
                existing.exerciseMinutes = summary.exerciseMinutes ?? existing.exerciseMinutes
                existing.standHours = summary.standHours ?? existing.standHours
                if !summary.sleepStages.isEmpty {
                    existing.sleepStages = summary.sleepStages
                }
                // 天気データは新データにある場合のみ更新（nilで上書きしない）
                if summary.weatherCondition != nil {
                    existing.weatherCondition = summary.weatherCondition
                }
                if summary.highTemperature != nil {
                    existing.highTemperature = summary.highTemperature
                }
                if summary.lowTemperature != nil {
                    existing.lowTemperature = summary.lowTemperature
                }
                summaryDict[summary.date] = existing
            } else {
                // 新規データ
                summaryDict[summary.date] = summary
            }
        }
        healthSummaries = Array(summaryDict.values).sorted { $0.date > $1.date }
    }

    private func persistHealthSummaries() {
        // Full Sync to SwiftData (keyed by Date to avoid duplication if IDs change)
        // 1. Fetch all existing SDHealthSummaries
        let descriptor = FetchDescriptor<SDHealthSummary>()
        if let existingItems = try? modelContext.fetch(descriptor) {
            // Map by Date (start of day) for matching
            let calendar = Calendar.current
            var existingMap = Dictionary(grouping: existingItems, by: { calendar.startOfDay(for: $0.date) })
                .mapValues { $0.first! } // Assume uniqueness by day

            // 2. Iterate memory items
            for item in healthSummaries {
                let dateKey = calendar.startOfDay(for: item.date)
                if let existing = existingMap[dateKey] {
                    // Update
                    existing.update(from: item)
                    existingMap.removeValue(forKey: dateKey)
                } else {
                    // Insert
                    let newItem = SDHealthSummary(domain: item)
                    modelContext.insert(newItem)
                }
            }

            // 3. Delete remaining (orphaned) items
            // Health data usually isn't deleted, but if it was removed from memory, we sync that.
            for orphaned in existingMap.values {
                modelContext.delete(orphaned)
            }

            saveContext()
        }
    }

    /// 指定日の天気データを更新
    func updateWeather(for date: Date, condition: String, high: Double?, low: Double?) {
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)

        if let index = healthSummaries.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: targetDate) }) {
            healthSummaries[index].weatherCondition = condition
            healthSummaries[index].highTemperature = high
            healthSummaries[index].lowTemperature = low
        } else {
            var summary = HealthSummary(date: targetDate)
            summary.weatherCondition = condition
            summary.highTemperature = high
            summary.lowTemperature = low
            healthSummaries.append(summary)
            healthSummaries.sort { $0.date > $1.date }
        }
        persistHealthSummaries()
    }

    // MARK: - Core Persistence Helpers

    /// SwiftData への保存を一元化する。
    /// 以前は全保存箇所が `try? modelContext.save()` で失敗を黙殺しており、
    /// メモリ上の @Published 配列と DB が乖離しても気づく手段がなかった。
    /// クラッシュはさせない(UI 上は操作が成功して見えるため、落とすより
    /// ログに残して次回起動時の SwiftData 再読込に委ねる方が被害が小さい)。
    func saveContext(operation: StaticString = #function) {
        do {
            try modelContext.save()
        } catch {
            AppLogger.data.error("SwiftData保存に失敗 (\(operation)): \(error)")
        }
    }

    static func loadValue<T: Decodable>(forKey key: String, defaultValue: T) -> T {
        // Use Shared Defaults if possible
        let defaults = UserDefaults(suiteName: PersistenceController.appGroupIdentifier) ?? UserDefaults.standard
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(T.self, from: data) {
            return decoded
        }
        return defaultValue
    }

    static func hasStoredUserDefaultsFootprintForInitialPermissions(includeAutoSeededKeys: Bool) -> Bool {
        var keys = [
            tasksDefaultsKey,
            diaryDefaultsKey,
            habitsDefaultsKey,
            habitRecordsDefaultsKey,
            anniversariesDefaultsKey,
            calendarEventsDefaultsKey,
            externalCalendarEventsDefaultsKey,
            externalCalendarRangeDefaultsKey,
            memoPadDefaultsKey,
            appStateDefaultsKey,
            healthSummariesDefaultsKey
        ]
        if includeAutoSeededKeys {
            keys.append(contentsOf: [
                locationVisitTagsDefaultsKey,
                locationVisitTagsSeededDefaultsKey
            ])
        }

        let sharedDefaults = UserDefaults(suiteName: PersistenceController.appGroupIdentifier)
        return keys.contains { key in
            sharedDefaults?.object(forKey: key) != nil || UserDefaults.standard.object(forKey: key) != nil
        }
    }

    func persist<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            let defaults = UserDefaults(suiteName: PersistenceController.appGroupIdentifier) ?? UserDefaults.standard
            defaults.set(data, forKey: key)
            // Backup to standard for safety? Not strictly needed if we fully migrate, but good for now.
        }
    }

}
