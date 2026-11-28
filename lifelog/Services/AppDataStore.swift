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
    @Published var habitRecords: [HabitRecord] = [] {
        didSet {
            // Bulk loading/replacement needs a new index; checkbox edits update it in place.
            guard !isUpdatingHabitCompletion else { return }
            habitRecordLookup = nil
            habitRecordChanges.send(.reset)
        }
    }
    @Published var anniversaries: [Anniversary] = []
    @Published private(set) var healthSummaries: [HealthSummary] = []
    @Published var calendarEvents: [CalendarEvent] = [] {
        didSet { eventsCache.removeAll() }
    }
    @Published var calendarExceptions: [CalendarEventException] = [] {
        didSet { eventsCache.removeAll() }
    }
    @Published var memoPad: MemoPad = MemoPad()
    @Published var externalCalendarEvents: [CalendarEvent] = [] {
        didSet { eventsCache.removeAll() }
    }
    @Published var letters: [Letter] = []
    @Published var sharedLetters: [SharedLetter] = []  // 他ユーザーからの手紙
    @Published var appState: AppState = AppState()
    @Published var locationVisitTagDefinitions: [LocationVisitTagDefinition] = []

    // MARK: - Cache

    enum HabitRecordChange {
        case reset
        case completion(habitID: UUID, day: Date)
    }

    // Emit after mutation so subscribers can read the indexed record immediately.
    let habitRecordChanges = PassthroughSubject<HabitRecordChange, Never>()
    var habitRecordLookup: HabitRecordLookup?
    var isUpdatingHabitCompletion = false
    var eventsCache: [Date: [CalendarEvent]] = [:]
    var eventsCacheCalendar: Calendar?
    var needsDiaryPhotoSyncRefresh = false
    var externalCalendarRange: ExternalCalendarRange? = nil
    var externalReminderRescheduleGeneration: UInt = 0
    var nextExternalReminderRefreshDate: Date?
    private(set) var hasExistingUserFootprintForInitialPermissions = false
    private(set) var hasLoadedAppState = false
    private var healthLoadTask: _Concurrency.Task<Bool, Never>?
    private var healthAuthorizationTask: _Concurrency.Task<Bool, Never>?
    private var hasLoadedHealthSummaries = false
    private(set) var hasLoadedFullHistory = true
    private var hasHydratedTasks = true
    private var hasHydratedDiaries = true
    private var hasHydratedHabitRecords = true
    private var hasHydratedCalendarEvents = true
    private var hasHydratedHealthSummaries = true
    private var hasHydratedShopping = true
    private var hasStartedDeferredHealthLoad = false
    private var needsHealthPersistence = false
    private var categoryPaletteObservation: AnyCancellable?

    // Avoid Swift's implicit isolated-deinit back-deployment crash on iOS 26.1.
    // Same workaround as ShoppingStore; no custom actor-bound teardown is needed.
    nonisolated deinit {}

    // MARK: - Legacy Persistence Keys
    #if DEBUG && targetEnvironment(simulator)
    func reloadSimulatorDemoHealthSummaries() throws {
        healthSummaries = try modelContext.fetch(FetchDescriptor<SDHealthSummary>())
            .map { HealthSummary(sd: $0) }
    }
    #endif

    // キー文字列の正は共有 EventQuerying。値は不変のまま参照だけ集約する。
    static let externalCalendarEventsDefaultsKey = EventQuerying.externalCalendarEventsDefaultsKey
    static let externalCalendarRangeDefaultsKey = EventQuerying.externalCalendarRangeDefaultsKey
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
    private(set) var modelContext: ModelContext
    let shoppingStore: ShoppingStore
    let taskNotificationService: NotificationService
    let calendarNotificationService: NotificationService
    let anniversaryNotificationService: NotificationService
    let dailyNotificationService: NotificationService
    let diaryReminderDefaults: UserDefaults?
    private(set) var areNotificationUpdatesEnabled = true
    private var hasRefreshedStartupNotifications = false

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

    init(container: ModelContainer, startsBackgroundServices: Bool = true,
         taskNotificationService: NotificationService? = nil,
         calendarNotificationService: NotificationService? = nil,
         anniversaryNotificationService: NotificationService? = nil,
         dailyNotificationService: NotificationService? = nil,
         diaryReminderDefaults: UserDefaults? = nil,
         defersNotificationUpdatesUntilStartup: Bool = false,
         defersFullHistoryLoad: Bool = false) {
        // Setup SwiftData
        self.modelContext = container.mainContext
        self.taskNotificationService = taskNotificationService ?? NotificationService.shared
        self.calendarNotificationService = calendarNotificationService ?? NotificationService.shared
        self.anniversaryNotificationService = anniversaryNotificationService ?? NotificationService.shared
        self.dailyNotificationService = dailyNotificationService ?? NotificationService.shared
        self.diaryReminderDefaults = diaryReminderDefaults ?? (startsBackgroundServices ? .standard : nil)
        self.areNotificationUpdatesEnabled = !defersNotificationUpdatesUntilStartup
        let useStagedStartup = defersFullHistoryLoad && startsBackgroundServices && !PersistenceController.isSimulatorDemoMode
        let shouldProfile = startsBackgroundServices && StartupProfiler.shared.shouldRecordPrimaryStoreLoad
        let profiler = StartupProfiler.shared

        self.shoppingStore = shouldProfile
            ? profiler.measure("store.shoppingStoreInit") {
                ShoppingStore(container: container, deferInitialLoad: useStagedStartup)
            }
            : ShoppingStore(container: container, deferInitialLoad: useStagedStartup)
        if shouldProfile && !useStagedStartup {
            profiler.setMetadata("Shopping", value: "items=\(shoppingStore.items.count), places=\(shoppingStore.places.count)")
        }

        // docs/ui-guidelines.md §カレンダー: color-only edits must refresh rows
        // without rewriting events or fetching the external calendar again.
        categoryPaletteObservation = CategoryPalette.changes
            .sink { [weak self] in self?.objectWillChange.send() }

        // 1. Run Migration (if needed)
        if startsBackgroundServices && !PersistenceController.isSimulatorDemoMode {
            if shouldProfile {
                profiler.measure("store.migrationCheck") {
                    MigrationManager.shared.migrate(modelContext: modelContext)
                }
            } else {
                MigrationManager.shared.migrate(modelContext: modelContext)
            }
        }

        if shouldProfile {
            profiler.measure("store.loadAppState") {
                _ = loadAppState()
            }
        } else {
            loadAppState()
        }
        do {
            if useStagedStartup {
                try loadInitialStartupRecords(profile: shouldProfile)
                self.hasLoadedFullHistory = false
                self.hasHydratedTasks = false
                self.hasHydratedDiaries = false
                self.hasHydratedHabitRecords = false
                self.hasHydratedCalendarEvents = false
                self.hasHydratedHealthSummaries = false
                self.hasHydratedShopping = false
            } else {
                try loadStoredRecords(profile: shouldProfile)
                self.hasLoadedFullHistory = true
            }
        } catch {
            AppLogger.data.error("Failed to fetch initial data from SwiftData: \(error)")
        }

        // Deterministic in-memory tests load only their injected store. They do
        // not migrate defaults, seed user data, request integrations or notify.
        guard startsBackgroundServices else { return }

        if shouldProfile {
            let defaults = UserDefaults(suiteName: PersistenceController.appGroupIdentifier) ?? UserDefaults.standard
            let extBytes = defaults.data(forKey: Self.externalCalendarEventsDefaultsKey)?.count ?? 0
            self.externalCalendarEvents = profiler.measure("store.externalCalJSON", detail: {
                let kb = String(format: "%.1fKB", Double(extBytes) / 1024.0)
                return "raw=\(kb)"
            }) {
                Self.loadValue(forKey: Self.externalCalendarEventsDefaultsKey, defaultValue: [])
            }
            profiler.setMetadata("ExternalCalendar", value: "events=\(externalCalendarEvents.count), json=\(String(format: "%.1fKB", Double(extBytes) / 1024.0))")
        } else {
            self.externalCalendarEvents = Self.loadValue(forKey: Self.externalCalendarEventsDefaultsKey, defaultValue: [])
        }
        let storedRange: ExternalCalendarRange? = Self.loadValue(forKey: Self.externalCalendarRangeDefaultsKey, defaultValue: nil)
        self.externalCalendarRange = storedRange
        if PersistenceController.isSimulatorDemoMode {
            self.externalCalendarEvents = []
            self.externalCalendarRange = nil
        }
        if shouldProfile {
            profiler.measure("store.postLoadDefaults") {
                self.locationVisitTagDefinitions = Self.loadValue(forKey: Self.locationVisitTagsDefaultsKey, defaultValue: [])
                recordInitialPermissionsFootprint(standard: .standard, shared: UserDefaults(suiteName: PersistenceController.appGroupIdentifier))
                normalizeLocationVisitTagOrderIfNeeded()
                seedDefaultLocationVisitTagsIfNeeded()
            }
            profiler.finishPrimaryStoreLoad()
        } else {
            self.locationVisitTagDefinitions = Self.loadValue(forKey: Self.locationVisitTagsDefaultsKey, defaultValue: [])
            recordInitialPermissionsFootprint(standard: .standard, shared: UserDefaults(suiteName: PersistenceController.appGroupIdentifier))
            normalizeLocationVisitTagOrderIfNeeded()
            seedDefaultLocationVisitTagsIfNeeded()
        }

        #if DEBUG && targetEnvironment(simulator)
        if ASOScreenshotShowcase.isEnabled {
            seedASOScreenshotShowcase()
        } else if PersistenceController.isSimulatorDemoMode {
            seedSimulatorDemoDataIfNeeded()
        }
        #endif
        if !useStagedStartup {
            startDeferredHealthSyncIfNeeded()
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

    /// Stage 1 startup load: fetches only what Home (Today) needs immediately,
    /// deferring multi-year history until after the startup logo reveals Home.
    private func loadInitialStartupRecords(profile: Bool) throws {
        let profiler = StartupProfiler.shared
        func run<T>(_ name: String, detail: (() -> String?)? = nil, _ body: () throws -> T) rethrows -> T {
            if profile {
                return try profiler.measure(name, detail: detail, body)
            } else {
                return try body()
            }
        }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: todayStart) ?? todayStart
        let sixtyDaysAgo = calendar.date(byAdding: .day, value: -60, to: todayStart) ?? todayStart

        // Tasks: incomplete or completed today
        let sdTasks = try run("stage1.SDTask") {
            try modelContext.fetch(FetchDescriptor<SDTask>(predicate: #Predicate {
                if $0.isCompleted == false {
                    return true
                } else if let completedAt = $0.completedAt {
                    return completedAt >= todayStart
                } else {
                    return false
                }
            }))
        }
        self.tasks = sdTasks.map { Task(sd: $0) }

        // DiaryEntries: last 7 days
        let sdDiaries = try run("stage1.SDDiaryEntry") {
            try modelContext.fetch(FetchDescriptor<SDDiaryEntry>(predicate: #Predicate {
                $0.date >= weekAgo
            }))
        }
        self.diaryEntries = Self.normalizeDiaryEntries(sdDiaries.map { DiaryEntry(sd: $0) })

        // Habits (all; tiny) + HabitRecords (last 60 days for immediate streaks)
        let sdHabits = try run("stage1.SDHabit") {
            try modelContext.fetch(FetchDescriptor<SDHabit>(sortBy: [SortDescriptor(\.orderIndex)]))
        }
        self.habits = sdHabits.map { Habit(sd: $0) }

        let sdRecords = try run("stage1.SDHabitRecord") {
            try modelContext.fetch(FetchDescriptor<SDHabitRecord>(predicate: #Predicate {
                $0.date >= sixtyDaysAgo
            }))
        }
        self.habitRecords = sdRecords.map { HabitRecord(sd: $0) }
        self.habitRecordLookup = HabitRecordLookup(records: habitRecords)

        // Anniversaries (all; tiny)
        let sdAnniversaries = try run("stage1.SDAnniversary") {
            try modelContext.fetch(FetchDescriptor<SDAnniversary>(sortBy: [SortDescriptor(\.orderIndex)]))
        }
        self.anniversaries = sdAnniversaries.map { Anniversary(sd: $0) }

        // CalendarEvents: recurring series + events ending within/after last 7 days
        let sdEvents = try run("stage1.SDCalendarEvent") {
            try modelContext.fetch(FetchDescriptor<SDCalendarEvent>(predicate: #Predicate {
                $0.recurrenceRuleData != nil || $0.endDate >= weekAgo
            }))
        }
        self.calendarEvents = sdEvents.map { CalendarEvent(sd: $0) }
        self.calendarExceptions = try run("stage1.SDCalendarEventException") {
            try modelContext.fetch(FetchDescriptor<SDCalendarEventException>())
                .map { CalendarEventException(sd: $0) }
        }

        // Letters & SharedLetters (all; tiny)
        let sdLetters = try run("stage1.SDLetter") {
            try modelContext.fetch(FetchDescriptor<SDLetter>())
        }
        self.letters = sdLetters.map { Letter(sd: $0) }
        let sdSharedLetters = try run("stage1.SDSharedLetter") {
            try modelContext.fetch(FetchDescriptor<SDSharedLetter>(sortBy: [SortDescriptor(\.openedAt, order: .reverse)]))
        }
        self.sharedLetters = sdSharedLetters.map { SharedLetter(sd: $0) }

        // HealthSummaries: last 7 days only; full history loads in Stage 2 before any persistence.
        let sdHealth = try run("stage1.SDHealthSummary") {
            try modelContext.fetch(FetchDescriptor<SDHealthSummary>(
                predicate: #Predicate { $0.date >= weekAgo },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            ))
        }
        self.healthSummaries = sdHealth.map { HealthSummary(sd: $0) }
        self.hasLoadedHealthSummaries = false

        // MemoPad
        let sdMemos = try run("stage1.SDMemoPad") {
            try modelContext.fetch(FetchDescriptor<SDMemoPad>())
        }
        self.memoPad = sdMemos.first.map { MemoPad(sd: $0) } ?? MemoPad()

        if profile {
            profiler.setMetadata(
                "Stage1Loaded",
                value: "tasks=\(tasks.count), diary=\(diaryEntries.count), habitRecs=\(habitRecords.count), events=\(calendarEvents.count), health=\(healthSummaries.count)"
            )
        }
    }

    /// Stage 2 (async incremental): hydrate remaining multi-year history one table
    /// per runloop turn so Home remains responsive at 60fps right after launch.
    func loadRemainingHistoryIncrementally() async {
        guard !hasLoadedFullHistory else { return }
        saveContext()
        let start = CFAbsoluteTimeGetCurrent()
        do {
            if !hasHydratedTasks {
                let sdTasks = try modelContext.fetch(FetchDescriptor<SDTask>())
                self.tasks = sdTasks.map { Task(sd: $0) }
                hasHydratedTasks = true
                await _Concurrency.Task.yield()
            }
            if !hasHydratedDiaries {
                let sdDiaries = try modelContext.fetch(FetchDescriptor<SDDiaryEntry>())
                self.diaryEntries = Self.normalizeDiaryEntries(sdDiaries.map { DiaryEntry(sd: $0) })
                hasHydratedDiaries = true
                await _Concurrency.Task.yield()
            }
            if !hasHydratedHabitRecords {
                let sdRecords = try modelContext.fetch(FetchDescriptor<SDHabitRecord>())
                self.habitRecords = sdRecords.map { HabitRecord(sd: $0) }
                self.habitRecordLookup = HabitRecordLookup(records: habitRecords)
                hasHydratedHabitRecords = true
                await _Concurrency.Task.yield()
            }
            if !hasHydratedCalendarEvents {
                let sdEvents = try modelContext.fetch(FetchDescriptor<SDCalendarEvent>())
                self.calendarEvents = sdEvents.map { CalendarEvent(sd: $0) }
                hasHydratedCalendarEvents = true
                await _Concurrency.Task.yield()
            }
            if !hasHydratedHealthSummaries {
                let sdHealth = try modelContext.fetch(FetchDescriptor<SDHealthSummary>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
                self.healthSummaries = sdHealth.map { HealthSummary(sd: $0) }
                self.hasLoadedHealthSummaries = true
                hasHydratedHealthSummaries = true
                await _Concurrency.Task.yield()
            }
            if !hasHydratedShopping {
                self.shoppingStore.reloadIfNeeded()
                hasHydratedShopping = true
            }
            finishFullHistoryHydration(elapsedMs: (CFAbsoluteTimeGetCurrent() - start) * 1000.0,
                                       spanName: "stage2.incrementalHistory")
        } catch {
            AppLogger.data.error("Failed to incrementally hydrate full history from SwiftData: \(error)")
        }
    }

    /// Stage 2 (synchronous fallback): immediately finishes any remaining unhydrated
    /// tables when the user switches tabs or triggers an action requiring full history.
    func loadRemainingHistoryIfNeeded() {
        guard !hasLoadedFullHistory else { return }
        saveContext()
        let start = CFAbsoluteTimeGetCurrent()
        do {
            if !hasHydratedTasks {
                let sdTasks = try modelContext.fetch(FetchDescriptor<SDTask>())
                self.tasks = sdTasks.map { Task(sd: $0) }
                hasHydratedTasks = true
            }
            if !hasHydratedDiaries {
                let sdDiaries = try modelContext.fetch(FetchDescriptor<SDDiaryEntry>())
                self.diaryEntries = Self.normalizeDiaryEntries(sdDiaries.map { DiaryEntry(sd: $0) })
                hasHydratedDiaries = true
            }
            if !hasHydratedHabitRecords {
                let sdRecords = try modelContext.fetch(FetchDescriptor<SDHabitRecord>())
                self.habitRecords = sdRecords.map { HabitRecord(sd: $0) }
                self.habitRecordLookup = HabitRecordLookup(records: habitRecords)
                hasHydratedHabitRecords = true
            }
            if !hasHydratedCalendarEvents {
                let sdEvents = try modelContext.fetch(FetchDescriptor<SDCalendarEvent>())
                self.calendarEvents = sdEvents.map { CalendarEvent(sd: $0) }
                hasHydratedCalendarEvents = true
            }
            if !hasHydratedHealthSummaries {
                let sdHealth = try modelContext.fetch(FetchDescriptor<SDHealthSummary>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
                self.healthSummaries = sdHealth.map { HealthSummary(sd: $0) }
                self.hasLoadedHealthSummaries = true
                hasHydratedHealthSummaries = true
            }
            if !hasHydratedShopping {
                self.shoppingStore.reloadIfNeeded()
                hasHydratedShopping = true
            }
            finishFullHistoryHydration(elapsedMs: (CFAbsoluteTimeGetCurrent() - start) * 1000.0,
                                       spanName: "stage2.loadRemainingHistory")
        } catch {
            AppLogger.data.error("Failed to hydrate full history from SwiftData: \(error)")
        }
    }

    private func finishFullHistoryHydration(elapsedMs: Double, spanName: String) {
        guard !hasLoadedFullHistory else { return }
        hasLoadedFullHistory = true
        let profiler = StartupProfiler.shared
        profiler.recordSpan(spanName, durationMs: elapsedMs)
        let incompleteTasks = tasks.filter { !$0.isCompleted }.count
        let photoPathsCount = diaryEntries.reduce(0) { $0 + $1.photoPaths.count + $1.locationPhotoPaths.count }
        let locationsCount = diaryEntries.reduce(0) { $0 + $1.locations.count }
        let archivedHabits = habits.filter(\.isArchived).count
        let recurringEvents = calendarEvents.filter { $0.recurrenceRule != nil }.count
        let sleepStagesCount = healthSummaries.reduce(0) { $0 + $1.sleepStages.count }
        profiler.setMetadata("Shopping", value: "items=\(shoppingStore.items.count), places=\(shoppingStore.places.count)")
        profiler.setMetadata("Tasks", value: "total=\(tasks.count), incomplete=\(incompleteTasks)")
        profiler.setMetadata("Diary", value: "entries=\(diaryEntries.count), photos=\(photoPathsCount), locations=\(locationsCount)")
        profiler.setMetadata("Habits", value: "total=\(habits.count) (active=\(habits.count - archivedHabits), archived=\(archivedHabits)), records=\(habitRecords.count)")
        profiler.setMetadata("Calendar", value: "events=\(calendarEvents.count) (recurring=\(recurringEvents)), exceptions=\(calendarExceptions.count)")
        profiler.setMetadata("Health", value: "summaries=\(healthSummaries.count), sleepStages=\(sleepStagesCount)")
        profiler.setMetadata("Other", value: "anniversaries=\(anniversaries.count), letters=\(letters.count), sharedLetters=\(sharedLetters.count)")
    }

    func startDeferredHealthSyncIfNeeded() {
        guard !hasStartedDeferredHealthLoad else { return }
        hasStartedDeferredHealthLoad = true
        _Concurrency.Task {
            await backfillHealthRequestedFlagIfNeeded()
            await loadHealthData()
        }
    }

    func recordInitialPermissionsFootprint(standard: UserDefaults, shared: UserDefaults?) {
        let hasUserRecords = !tasks.isEmpty || !shoppingStore.items.isEmpty || !shoppingStore.places.isEmpty ||
            !diaryEntries.isEmpty || !habits.isEmpty || !habitRecords.isEmpty || !anniversaries.isEmpty ||
            !calendarEvents.isEmpty || !letters.isEmpty || !sharedLetters.isEmpty ||
            !memoPad.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || memoPad.lastUpdatedAt != nil ||
            diaryReminderEnabled
        let hasIntegrationData = !externalCalendarEvents.isEmpty || !healthSummaries.isEmpty ||
            appState.lastCalendarSyncDate != nil || !appState.calendarCategoryLinks.isEmpty ||
            !appState.unavailableCalendarCategoryLinks.isEmpty
        hasExistingUserFootprintForInitialPermissions = InitialPermissionsState.recordLaunch(
            standard: standard, shared: shared, hasUserRecords: hasUserRecords, hasIntegrationData: hasIntegrationData
        )
    }

    /// The importer commits in its own context. Use fresh contexts so a previously fetched
    /// diary or memo immediately shows both the existing and the recovered content.
    func reloadAfterStoreRecovery() throws {
        // A weather/HealthKit refresh must not reconcile an old snapshot with the restored rows.
        hasLoadedHealthSummaries = false
        modelContext = ModelContext(modelContext.container)
        guard loadAppState() else { throw CocoaError(.fileReadUnknown) }
        try loadStoredRecords()
        hasLoadedFullHistory = true
        hasHydratedTasks = true
        hasHydratedDiaries = true
        hasHydratedHabitRecords = true
        hasHydratedCalendarEvents = true
        hasHydratedHealthSummaries = true
        hasHydratedShopping = true
        try shoppingStore.reloadAfterStoreRecovery()
        refreshNotificationsAfterStartup()
        resumeDiaryPhotoSync()
    }

    private func loadStoredRecords(profile: Bool = false) throws {
        let profiler = StartupProfiler.shared
        func run<T>(_ name: String, detail: (() -> String?)? = nil, _ body: () throws -> T) rethrows -> T {
            if profile {
                return try profiler.measure(name, detail: detail, body)
            } else {
                return try body()
            }
        }

        // Tasks
        let sdTasks = try run("load.SDTask.fetch") {
            try modelContext.fetch(FetchDescriptor<SDTask>())
        }
        self.tasks = run("load.SDTask.map", detail: { "\(sdTasks.count)件" }) {
            sdTasks.map { Task(sd: $0) }
        }

        // DiaryEntries
        let sdDiaries = try run("load.SDDiaryEntry.fetch") {
            try modelContext.fetch(FetchDescriptor<SDDiaryEntry>())
        }
        let mappedDiaries = run("load.SDDiaryEntry.map+JSON", detail: { "\(sdDiaries.count)件" }) {
            sdDiaries.map { DiaryEntry(sd: $0) }
        }
        self.diaryEntries = run("load.SDDiaryEntry.normalize") {
            Self.normalizeDiaryEntries(mappedDiaries)
        }

        // Habits
        let sdHabits = try run("load.SDHabit") {
            try modelContext.fetch(FetchDescriptor<SDHabit>(sortBy: [SortDescriptor(\.orderIndex)]))
        }
        self.habits = sdHabits.map { Habit(sd: $0) }

        // HabitRecords
        let sdRecords = try run("load.SDHabitRecord.fetch") {
            try modelContext.fetch(FetchDescriptor<SDHabitRecord>())
        }
        self.habitRecords = run("load.SDHabitRecord.map", detail: { "\(sdRecords.count)件" }) {
            sdRecords.map { HabitRecord(sd: $0) }
        }
        self.habitRecordLookup = run("load.HabitRecordLookup", detail: { "\(self.habitRecords.count)件" }) {
            HabitRecordLookup(records: habitRecords)
        }

        // Anniversaries
        let sdAnniversaries = try run("load.SDAnniversary") {
            try modelContext.fetch(FetchDescriptor<SDAnniversary>(sortBy: [SortDescriptor(\.orderIndex)]))
        }
        self.anniversaries = sdAnniversaries.map { Anniversary(sd: $0) }

        // CalendarEvents (Internal)
        let sdEvents = try run("load.SDCalendarEvent.fetch") {
            try modelContext.fetch(FetchDescriptor<SDCalendarEvent>())
        }
        self.calendarEvents = run("load.SDCalendarEvent.map", detail: { "\(sdEvents.count)件" }) {
            sdEvents.map { CalendarEvent(sd: $0) }
        }
        self.calendarExceptions = try run("load.SDCalendarEventException") {
            try modelContext.fetch(FetchDescriptor<SDCalendarEventException>())
                .map { CalendarEventException(sd: $0) }
        }

        // Letters
        let sdLetters = try run("load.SDLetter") {
            try modelContext.fetch(FetchDescriptor<SDLetter>())
        }
        self.letters = sdLetters.map { Letter(sd: $0) }

        // SharedLetters (他ユーザーからの手紙)
        let sdSharedLetters = try run("load.SDSharedLetter") {
            try modelContext.fetch(FetchDescriptor<SDSharedLetter>(sortBy: [SortDescriptor(\.openedAt, order: .reverse)]))
        }
        self.sharedLetters = sdSharedLetters.map { SharedLetter(sd: $0) }

        // HealthSummaries (Cache)
        let sdHealth = try run("load.SDHealthSummary.fetch") {
            try modelContext.fetch(FetchDescriptor<SDHealthSummary>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
        }
        self.healthSummaries = run("load.SDHealthSummary.map+stages", detail: { "\(sdHealth.count)件" }) {
            sdHealth.map { HealthSummary(sd: $0) }
        }
        hasLoadedHealthSummaries = true

        // MemoPad
        let sdMemos = try run("load.SDMemoPad") {
            try modelContext.fetch(FetchDescriptor<SDMemoPad>())
        }
        if let first = sdMemos.first {
            self.memoPad = MemoPad(sd: first)
        } else {
            self.memoPad = MemoPad()
        }

        if profile {
            let incompleteTasks = tasks.filter { !$0.isCompleted }.count
            let photoPathsCount = diaryEntries.reduce(0) { $0 + $1.photoPaths.count + $1.locationPhotoPaths.count }
            let locationsCount = diaryEntries.reduce(0) { $0 + $1.locations.count }
            let archivedHabits = habits.filter(\.isArchived).count
            let recurringEvents = calendarEvents.filter { $0.recurrenceRule != nil }.count
            let sleepStagesCount = healthSummaries.reduce(0) { $0 + $1.sleepStages.count }
            profiler.setMetadata("Tasks", value: "total=\(tasks.count), incomplete=\(incompleteTasks)")
            profiler.setMetadata("Diary", value: "entries=\(diaryEntries.count), photos=\(photoPathsCount), locations=\(locationsCount)")
            profiler.setMetadata("Habits", value: "total=\(habits.count) (active=\(habits.count - archivedHabits), archived=\(archivedHabits)), records=\(habitRecords.count)")
            profiler.setMetadata("Calendar", value: "events=\(calendarEvents.count) (recurring=\(recurringEvents)), exceptions=\(calendarExceptions.count)")
            profiler.setMetadata("Health", value: "summaries=\(healthSummaries.count), sleepStages=\(sleepStagesCount)")
            profiler.setMetadata("Other", value: "anniversaries=\(anniversaries.count), letters=\(letters.count), sharedLetters=\(sharedLetters.count)")
        }
    }

    /// A failed read is unknown state, not an empty installation. Preserve the
    /// current snapshot and block calendar reconciliation/writes until retry.
    /// The fetch hook exercises failures without touching the user's store.
    @discardableResult
    func loadAppState(fetch: (() throws -> [SDAppState])? = nil) -> Bool {
        do {
            let states: [SDAppState]
            if let fetch {
                states = try fetch()
            } else {
                states = try modelContext.fetch(FetchDescriptor<SDAppState>())
            }
            appState = states.first.map { AppState(sd: $0) } ?? AppState()
            hasLoadedAppState = true
            return true
        } catch {
            hasLoadedAppState = false
            AppLogger.data.error("Failed to fetch app state from SwiftData: \(error)")
            return false
        }
    }

    /// The live scene opens this gate after the home/lock transition finishes.
    /// Calendar fetches may finish under the logo; use their latest snapshots here.
    /// See docs/ui-guidelines.md §起動時の表示.
    func refreshNotificationsAfterStartup(referenceDate: Date = Date()) {
        loadRemainingHistoryIfNeeded()
        areNotificationUpdatesEnabled = true
        if hasRefreshedStartupNotifications {
            refreshCalendarRemindersIfNeeded(referenceDate: referenceDate)
        } else {
            hasRefreshedStartupNotifications = true
            reapplyEventCategoryNotificationSettings(referenceDate: referenceDate)
        }
        rescheduleDiaryReminderIfNeeded(referenceDate: referenceDate)
        rescheduleTodayOverviewReminderIfNeeded(referenceDate: referenceDate)
    }

    // Keep the stored key so upgrades continue to refresh previously linked Health data.
    static let healthAccessRequestedKey = "initialPermissionsHealthRequestedV1"

    private func backfillHealthRequestedFlagIfNeeded() async {
        guard !PersistenceController.isSimulatorDemoMode else { return }
        guard UserDefaults.standard.bool(forKey: Self.healthAccessRequestedKey) == false else { return }
        guard await HealthKitManager.shared.hasPreviouslyRequestedAuthorization() else { return }
        UserDefaults.standard.set(true, forKey: Self.healthAccessRequestedKey)
    }

    @discardableResult
    func loadHealthData(requestAuthorizationIfNeeded: Bool = false) async -> Bool {
        guard !PersistenceController.isSimulatorDemoMode else { return false }
        loadRemainingHistoryIfNeeded()
        if requestAuthorizationIfNeeded {
            let preAuthorizationLoadTask = healthLoadTask
            let authorizationTask: _Concurrency.Task<Bool, Never>
            if let pending = healthAuthorizationTask {
                authorizationTask = pending
            } else {
                authorizationTask = _Concurrency.Task { @MainActor [self] in
                    defer { healthAuthorizationTask = nil }
                    return await HealthKitManager.shared.requestAuthorization()
                }
                healthAuthorizationTask = authorizationTask
            }
            let authorizationCompleted = await authorizationTask.value
            guard authorizationCompleted else { return false }
            UserDefaults.standard.set(true, forKey: Self.healthAccessRequestedKey)
            // A refresh that started before granting access may have queried an
            // empty HealthKit store. Finish it, then fetch using the new grant.
            if let pending = preAuthorizationLoadTask { _ = await pending.value }
        } else {
            if let authorizationTask = healthAuthorizationTask {
                guard await authorizationTask.value else { return false }
            }
            guard UserDefaults.standard.bool(forKey: Self.healthAccessRequestedKey) else {
                return false
            }
        }

        // Startup, permission completion and pull-to-refresh can overlap. Share
        // one fetch so they do not issue the same year of HealthKit queries.
        if let healthLoadTask { return await healthLoadTask.value }
        let task = _Concurrency.Task { @MainActor [self] in
            defer { healthLoadTask = nil }
            let recentFetched = await HealthKitManager.shared.fetchHealthData(for: 7)
            let recentChanged = mergeHealthSummaries(recentFetched)
            let fullFetched = await HealthKitManager.shared.fetchHealthData(for: 365)
            let fullChanged = mergeHealthSummaries(fullFetched)
            if recentChanged || fullChanged || needsHealthPersistence || modelContext.hasChanges {
                persistHealthSummaries()
            }
            return true
        }
        healthLoadTask = task
        return await task.value
    }

    @discardableResult
    private func mergeHealthSummaries(_ newData: [HealthSummary]) -> Bool {
        guard !newData.isEmpty else { return false }
        let merged = HealthSummaryMerging.merge(existing: healthSummaries, incoming: newData)
        guard merged != healthSummaries else { return false }
        healthSummaries = merged
        return true
    }

    private func persistHealthSummaries() {
        guard hasLoadedHealthSummaries else { return }
        needsHealthPersistence = true
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
                    if !HealthSummaryMerging.hasSameContent(HealthSummary(sd: existing), item) {
                        existing.update(from: item)
                    }
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
            if !modelContext.hasChanges { needsHealthPersistence = false }
        }
    }

    /// 指定日の天気データを更新
    func updateWeather(for date: Date, condition: String, high: Double?, low: Double?) {
        loadRemainingHistoryIfNeeded()
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)

        if let index = healthSummaries.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: targetDate) }) {
            var summary = healthSummaries[index]
            guard summary.weatherCondition != condition || summary.highTemperature != high ||
                  summary.lowTemperature != low else {
                if needsHealthPersistence || modelContext.hasChanges { persistHealthSummaries() }
                return
            }
            summary.weatherCondition = condition
            summary.highTemperature = high
            summary.lowTemperature = low
            healthSummaries[index] = summary
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
        guard modelContext.hasChanges else { return }
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

    func persist<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            let defaults = UserDefaults(suiteName: PersistenceController.appGroupIdentifier) ?? UserDefaults.standard
            defaults.set(data, forKey: key)
            // Backup to standard for safety? Not strictly needed if we fully migrate, but good for now.
        }
    }

}
