//
//  Persistence.swift
//  lifelog
//
//  Created for SwiftData Migration
//

import SwiftData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

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
            SDAppState.self
        ])
        
        // Define ModelConfiguration
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)

        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Typical error handling during development
            // In a production app, you might handle this differently (e.g., fallback or alert)
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
    
    // For SwiftUI Previews
    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.mainContext
        // Add sample data logic here if needed for previews
        return result
    }()
}
