import Foundation

/// An asynchronous identity lookup may finish after a location was toggled.
/// Preserve those explicit choices while resolving all untouched locations.
nonisolated enum PhotoLocationSelection {
    static func merge(resolvedIDs: Set<UUID>, selectedIDs: Set<UUID>, touchedIDs: Set<UUID>) -> Set<UUID> {
        resolvedIDs.subtracting(touchedIDs).union(selectedIDs.intersection(touchedIDs))
    }
}
