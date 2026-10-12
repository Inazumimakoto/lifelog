import SwiftData
@testable import lifelify

@MainActor
enum PerformanceTestStore {
    static func make(health: [HealthSummary] = []) -> AppDataStore {
        let persistence = PersistenceController(inMemory: true)
        for summary in health {
            persistence.container.mainContext.insert(SDHealthSummary(domain: summary))
        }
        return AppDataStore(container: persistence.container, startsBackgroundServices: false)
    }
}
