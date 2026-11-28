import Combine
import Foundation
import os

/// Own the store for the scene lifetime without forwarding its broad change
/// publisher into the App/TabView. Feature view models subscribe to their inputs.
/// See docs/requirements.md §6 (responsive UI).
@MainActor
final class AppDataStoreOwner: ObservableObject {
    @Published private(set) var store: AppDataStore?

    init() {
        openIfNeeded()
    }

    func openIfNeeded() {
        guard store == nil else { return }
        do {
            StartupProfiler.shared.mark("storeOwner.openIfNeeded.start")
            let container = try StartupProfiler.shared.measure("store.openContainer") {
                try PersistenceController.sharedContainer()
            }
            store = StartupProfiler.shared.measure("store.appDataStoreInit") {
                AppDataStore(container: container,
                             defersNotificationUpdatesUntilStartup: true,
                             defersFullHistoryLoad: !PersistenceController.isSimulatorDemoMode)
            }
            StartupProfiler.shared.recordDatabaseSizes()
            StartupProfiler.shared.mark("storeOwner.openIfNeeded.end")
        } catch {
            let failure = error as NSError
            AppLogger.data.error("Unable to open the store: \(failure.domain, privacy: .public) (\(failure.code)) – \(error)")
        }
    }

    // The store has no actor-bound teardown; avoid the same older-runtime
    // implicit isolated-deinit path as AppDataStore and ShoppingStore.
    nonisolated deinit {}
}
