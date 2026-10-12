import Combine

/// Own the store for the scene lifetime without forwarding its broad change
/// publisher into the App/TabView. Feature view models subscribe to their inputs.
/// See docs/requirements.md §6 (responsive UI).
@MainActor
final class AppDataStoreOwner: ObservableObject {
    let store = AppDataStore()

    // The store has no actor-bound teardown; avoid the same older-runtime
    // implicit isolated-deinit path as AppDataStore and ShoppingStore.
    nonisolated deinit {}
}
