import Combine
import SwiftData
import XCTest
@testable import lifelify

@MainActor
final class AppDataStorePerformanceTests: XCTestCase {
    func testSavingUnchangedDiary_skipsPublicationAndPreservesStoredText() throws {
        let store = PerformanceTestStore.make()
        let entry = DiaryEntry(date: Date(), text: "Original", mood: .neutral, conditionScore: 3)
        store.upsert(entry: entry)
        var publications = 0
        let subscription = store.$diaryEntries.dropFirst().sink { _ in publications += 1 }

        store.upsert(entry: entry)

        XCTAssertEqual(publications, 0)
        XCTAssertFalse(store.modelContext.hasChanges)
        XCTAssertEqual(try store.modelContext.fetch(FetchDescriptor<SDDiaryEntry>()).first?.text, "Original")
        withExtendedLifetime(subscription) {}
    }

    func testEditingDiaryAfterNoOp_persistsChangedText() throws {
        let store = PerformanceTestStore.make()
        var entry = DiaryEntry(date: Date(), text: "Original", mood: .neutral, conditionScore: 3)
        store.upsert(entry: entry)
        store.upsert(entry: entry)
        entry.text = "Changed"
        store.upsert(entry: entry)

        XCTAssertEqual(store.diaryEntries.first?.text, "Changed")
        XCTAssertEqual(try store.modelContext.fetch(FetchDescriptor<SDDiaryEntry>()).first?.text, "Changed")
    }

    func testSameDiaryWithPendingContextChanges_flushesUnsavedChanges() throws {
        let store = PerformanceTestStore.make()
        let entry = DiaryEntry(date: Date(), text: "Original", mood: .neutral, conditionScore: 3)
        store.upsert(entry: entry)
        let stored = try XCTUnwrap(store.modelContext.fetch(FetchDescriptor<SDDiaryEntry>()).first)
        stored.text = "Pending"
        XCTAssertTrue(store.modelContext.hasChanges)

        store.upsert(entry: entry)

        XCTAssertFalse(store.modelContext.hasChanges)
        XCTAssertEqual(stored.text, "Original")
    }

    func testIdenticalWeatherRefresh_skipsHealthPublication() {
        let store = PerformanceTestStore.make()
        let day = Calendar.current.startOfDay(for: Date())
        store.updateWeather(for: day, condition: "Clear", high: 25, low: 15)
        var publications = 0
        let subscription = store.$healthSummaries.dropFirst().sink { _ in publications += 1 }

        store.updateWeather(for: day, condition: "Clear", high: 25, low: 15)

        XCTAssertEqual(publications, 0)
        XCTAssertFalse(store.modelContext.hasChanges)
        withExtendedLifetime(subscription) {}
    }

    func testIdenticalWeatherWithPendingChanges_retriesPersistence() throws {
        let store = PerformanceTestStore.make()
        let day = Calendar.current.startOfDay(for: Date())
        store.updateWeather(for: day, condition: "Clear", high: 25, low: 15)
        let stored = try XCTUnwrap(store.modelContext.fetch(FetchDescriptor<SDHealthSummary>()).first)
        stored.weatherCondition = "Unsaved"
        XCTAssertTrue(store.modelContext.hasChanges)

        store.updateWeather(for: day, condition: "Clear", high: 25, low: 15)

        XCTAssertEqual(stored.weatherCondition, "Clear")
        XCTAssertFalse(store.modelContext.hasChanges)
    }
}
