import XCTest
import SwiftData
@testable import lifelify

@MainActor
final class TaskDeletionPersistenceTests: XCTestCase {
    func testOffsetDeletion_removesOnlyValidIndicesAndPersistsRemainingTasks() throws {
        let tasks = [Task(title: "First"), Task(title: "Second"), Task(title: "Third")]
        let store = try makeStore(tasks: tasks)
        store.tasks = tasks

        store.deleteTasks(at: IndexSet([0, 2, 99]))

        XCTAssertEqual(store.tasks, [tasks[1]])
        XCTAssertEqual(try persistedTasks(in: store), [tasks[1]])
    }

    func testIdentifierDeletion_handlesRepeatedAndMissingIDsWithoutRemovingOtherRows() throws {
        let first = Task(title: "First")
        let second = Task(title: "Second")
        let store = try makeStore(tasks: [first, second])
        store.deleteTasks(withIDs: [first.id, UUID(), first.id])
        XCTAssertEqual(store.tasks, [second])
        XCTAssertEqual(try persistedTasks(in: store), [second])
        store.deleteTasks(at: IndexSet([99]))
        XCTAssertEqual(try persistedTasks(in: store), [second])
    }

    private func makeStore(tasks: [Task]) throws -> AppDataStore {
        let container = PersistenceController(inMemory: true).container
        for task in tasks { container.mainContext.insert(SDTask(domain: task)) }
        try container.mainContext.save()
        return AppDataStore(container: container, startsBackgroundServices: false)
    }

    private func persistedTasks(in store: AppDataStore) throws -> [Task] {
        try ModelContext(store.modelContext.container).fetch(FetchDescriptor<SDTask>()).map { Task(sd: $0) }
    }
}
