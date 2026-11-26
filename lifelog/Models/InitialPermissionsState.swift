import Foundation

enum InitialPermissionsState {
    static let completedKey = "initialPermissionsSetupCompletedV1"
    static let featureSeenKey = "initialPermissionsSetupFeatureSeenV1"
    private static let firstLaunchFootprintKey = "initialPermissionsFirstLaunchHadExistingDataV1"

    /// Take a snapshot before this version seeds data or refreshes integrations.
    /// Only an explicit skip or finish marks a new user's setup as complete.
    static func recordLaunch(standard: UserDefaults, shared: UserDefaults?,
                             hasUserRecords: Bool, hasIntegrationData: Bool) -> Bool {
        if standard.bool(forKey: completedKey) { return true }
        if let snapshot = standard.object(forKey: firstLaunchFootprintKey) as? Bool { return snapshot }

        // Older releases used both suites. Empty legacy collections still identify
        // an installation which was in use before the first-run flow was introduced.
        let userKeys = [
            "Tasks_Storage_V1", "DiaryEntries_Storage_V1", "Habits_Storage_V1",
            "HabitRecords_Storage_V1", "Anniversaries_Storage_V1", "CalendarEvents_Storage_V1",
            "MemoPad_Storage_V1", "AppState_Storage_V1"
        ]
        let automaticKeys = [
            AppDataStore.locationVisitTagsDefaultsKey, AppDataStore.locationVisitTagsSeededDefaultsKey,
            AppDataStore.externalCalendarEventsDefaultsKey, AppDataStore.externalCalendarRangeDefaultsKey,
            "HealthSummaries_Storage_V1"
        ]
        let predatesSetup = !standard.bool(forKey: featureSeenKey)
        let keys = predatesSetup ? userKeys + automaticKeys : userKeys
        let hasLegacyRecords = keys.contains { standard.object(forKey: $0) != nil || shared?.object(forKey: $0) != nil }
        let existing = hasUserRecords || hasLegacyRecords || (predatesSetup && hasIntegrationData)
        standard.set(existing, forKey: firstLaunchFootprintKey)
        standard.set(true, forKey: featureSeenKey)
        return existing
    }
}
