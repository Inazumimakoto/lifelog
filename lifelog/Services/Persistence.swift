//
//  Persistence.swift
//  lifelog
//
//  Created for SwiftData Migration
//

import Foundation
import SwiftData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    // App Group IDs (must be present in app/widget entitlements)
    private static let defaultAppGroupIdentifier = "group.lifelog.share"
    private static let screenshotsAppGroupIdentifier = "group.lifelog.screenshots"
    private static let activeAppGroupDefaultsKey = "lifelog.activeAppGroupIdentifier"
    private static let screenshotsLaunchArguments: Set<String> = [
        "-screenshots-mode",
        "-ScreenshotsMode",
    ]

    private static var isRunningInExtension: Bool {
        Bundle.main.bundleURL.pathExtension == "appex" ||
        Bundle.main.object(forInfoDictionaryKey: "NSExtension") != nil
    }

    private static var isScreenshotsModeLaunch: Bool {
        let arguments = Set(ProcessInfo.processInfo.arguments)
        return screenshotsLaunchArguments.isDisjoint(with: arguments) == false
    }

    /// Active App Group used by app + widgets.
    ///
    /// - App launch:
    ///   - `-screenshots-mode` -> screenshots group
    ///   - default -> normal group
    /// - Widget extension:
    ///   - follows the latest app selection stored in shared defaults.
    static var appGroupIdentifier: String {
        let selected: String
        if isScreenshotsModeLaunch {
            selected = screenshotsAppGroupIdentifier
        } else if isRunningInExtension {
            selected = persistedActiveAppGroupIdentifier ?? defaultAppGroupIdentifier
        } else {
            selected = defaultAppGroupIdentifier
        }

        persistActiveAppGroupIdentifierIfNeeded(selected)
        return selected
    }

    private static var persistedActiveAppGroupIdentifier: String? {
        guard let defaults = UserDefaults(suiteName: defaultAppGroupIdentifier) else { return nil }
        guard let value = defaults.string(forKey: activeAppGroupDefaultsKey) else { return nil }
        let allowed = [defaultAppGroupIdentifier, screenshotsAppGroupIdentifier]
        return allowed.contains(value) ? value : nil
    }

    private static func persistActiveAppGroupIdentifierIfNeeded(_ identifier: String) {
        guard isRunningInExtension == false else { return }
        guard let defaults = UserDefaults(suiteName: defaultAppGroupIdentifier) else { return }
        defaults.set(identifier, forKey: activeAppGroupDefaultsKey)
    }

    init(inMemory: Bool = false) {
        let schema = Schema([
            SDTask.self,
            SDDiaryEntry.self,
            SDHabit.self,
            SDHabitRecord.self,
            SDAnniversary.self,
            SDHealthSummary.self,
            SDCalendarEvent.self,
            SDMemoPad.self,
            SDAppState.self,
            SDLetter.self,
            SDSharedLetter.self
        ])
        
        if inMemory {
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create in-memory ModelContainer: \(error)")
            }
            return
        }
        
        // App Group Storage Logic
        let storeURL: URL
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) {
            storeURL = groupURL.appendingPathComponent("default.store")
            
            // Migration: Check if we need to move existing DB from Sandbox to App Group
            let fileManager = FileManager.default
            let sandboxURL = URL.applicationSupportDirectory.appendingPathComponent("default.store")
            
            // If App Group DB doesn't exist, but Sandbox DB does, move it.
            if !fileManager.fileExists(atPath: storeURL.path) && fileManager.fileExists(atPath: sandboxURL.path) {
                print("Moving SwiftData store from Sandbox to App Group...")
                do {
                    try fileManager.moveItem(at: sandboxURL, to: storeURL)
                    // Also move aux files if they exist (-shm, -wal)
                    let shmSource = sandboxURL.appendingPathExtension("shm")
                    let shmDest = storeURL.appendingPathExtension("shm")
                    if fileManager.fileExists(atPath: shmSource.path) {
                        try fileManager.moveItem(at: shmSource, to: shmDest)
                    }
                    
                    let walSource = sandboxURL.appendingPathExtension("wal")
                    let walDest = storeURL.appendingPathExtension("wal")
                    if fileManager.fileExists(atPath: walSource.path) {
                        try fileManager.moveItem(at: walSource, to: walDest)
                    }
                    print("Successfully moved SwiftData store.")
                } catch {
                    print("Failed to move SwiftData store: \(error)")
                    // Fallback to creating new or whatever system does
                }
            }
        } else {
            print("WARNING: App Group container not found. Falling back to default location.")
            storeURL = URL.applicationSupportDirectory.appendingPathComponent("default.store")
        }
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: storeURL
            // CloudKit同期は追加設定が必要 - 後日対応
        )

        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
    
    // For SwiftUI Previews
    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        return result
    }()
}
