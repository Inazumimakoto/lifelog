import Foundation

nonisolated enum ExternalReminderRefreshTiming {
    /// A plan with no upcoming reminders remains valid until its events or
    /// settings change. A nonempty plan expires when its first reminder fires.
    static func shouldRefresh(nextFireDate: Date?, at referenceDate: Date) -> Bool {
        guard let nextFireDate else { return false }
        return nextFireDate <= referenceDate
    }
}
