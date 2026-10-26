import XCTest
import SwiftData
@testable import lifelify

#if DEBUG && targetEnvironment(simulator)
@MainActor
final class SimulatorDemoSeedingTests: XCTestCase {
    func testSeeding_requiresDemoModeAndDedicatedStore() throws {
        try withStore(filename: "default.store") { store, _, defaults in
            XCTAssertFalse(try store.seedSupplementalSimulatorDemoDataIfNeeded(referenceDate: fixtureDate, isDemoMode: true))
            XCTAssertFalse(try store.seedSimulatorReviewMapDataIfNeeded(today: fixtureDate, defaults: defaults, isDemoMode: true))
            XCTAssertFalse(try store.seedSimulatorScheduleDataIfNeeded(today: fixtureDate, defaults: defaults, isDemoMode: true))
            XCTAssertTrue(try store.modelContext.fetch(FetchDescriptor<SDHabit>()).isEmpty)
            XCTAssertTrue(try store.modelContext.fetch(FetchDescriptor<SDHealthSummary>()).isEmpty)
            XCTAssertTrue(try store.modelContext.fetch(FetchDescriptor<SDShoppingItem>()).isEmpty)
            XCTAssertTrue(try store.modelContext.fetch(FetchDescriptor<SDDiaryEntry>()).isEmpty)
            XCTAssertTrue(try store.modelContext.fetch(FetchDescriptor<SDTask>()).isEmpty)
            XCTAssertTrue(try store.modelContext.fetch(FetchDescriptor<SDCalendarEvent>()).isEmpty)
            XCTAssertNil(defaults.object(forKey: "demo.reviewMap.seededDay.v1"))
        }
        try withStore { store, _, defaults in
            XCTAssertFalse(try store.seedSupplementalSimulatorDemoDataIfNeeded(referenceDate: fixtureDate, isDemoMode: false))
            XCTAssertFalse(try store.seedSimulatorReviewMapDataIfNeeded(today: fixtureDate, defaults: defaults, isDemoMode: false))
            XCTAssertFalse(try store.seedSimulatorScheduleDataIfNeeded(today: fixtureDate, defaults: defaults, isDemoMode: false))
            XCTAssertTrue(try store.modelContext.fetch(FetchDescriptor<SDHabit>()).isEmpty)
            XCTAssertTrue(try store.modelContext.fetch(FetchDescriptor<SDMemoPad>()).isEmpty)
            XCTAssertTrue(try store.modelContext.fetch(FetchDescriptor<SDLetter>()).isEmpty)
            XCTAssertTrue(try store.modelContext.fetch(FetchDescriptor<SDDiaryEntry>()).isEmpty)
            XCTAssertTrue(try store.modelContext.fetch(FetchDescriptor<SDTask>()).isEmpty)
            XCTAssertTrue(try store.modelContext.fetch(FetchDescriptor<SDCalendarEvent>()).isEmpty)
            XCTAssertNil(defaults.object(forKey: "demo.reviewMap.seededDay.v1"))
        }
    }

    func testSeeding_persistsEveryHomeSectionAcrossStoreRecreation() throws {
        try withStore { store, storeURL, defaults in
            XCTAssertTrue(try store.seedSupplementalSimulatorDemoDataIfNeeded(referenceDate: fixtureDate, isDemoMode: true))
            XCTAssertTrue(try store.seedSimulatorReviewMapDataIfNeeded(today: fixtureDate, defaults: defaults, isDemoMode: true))
            XCTAssertTrue(try store.seedSimulatorScheduleDataIfNeeded(today: fixtureDate, defaults: defaults, isDemoMode: true))
            let expected = SimulatorDemoFixtures.snapshot(referenceDate: fixtureDate)
            let firstTasks = Set(store.tasks)
            let firstEvents = Set(store.calendarEvents)
            XCTAssertEqual(firstTasks.count, 4)
            XCTAssertEqual(firstEvents.count, 15)
            XCTAssertEqual(Set(store.habits), Set(expected.habits))
            XCTAssertEqual(Set(store.habitRecords), Set(expected.habitRecords))
            XCTAssertEqual(Set(store.anniversaries), Set(expected.anniversaries))
            XCTAssertEqual(Set(store.healthSummaries), Set(expected.healthSummaries))
            XCTAssertEqual(store.memoPad, expected.memo)
            XCTAssertEqual(store.letters, expected.letters)
            XCTAssertTrue(store.letters.allSatisfy { $0.status == .draft })
            XCTAssertEqual(Set(store.shoppingStore.items), Set(expected.shoppingItems))
            XCTAssertEqual(Set(store.shoppingStore.places), Set(expected.shoppingPlaces))
            let firstDiaries = Set(store.diaryEntries)
            XCTAssertEqual(firstDiaries.count, 6)
            XCTAssertEqual(Set(store.diaryEntries.flatMap(\.locations).map(\.id)).count, 1_000)
            let today = try XCTUnwrap(store.diaryEntries.first { Calendar.current.isDate($0.date, inSameDayAs: fixtureDate) })
            XCTAssertEqual(today.text, String(localized: "ランニングで気分がすっきり。ミーティングも穏やかに進んだ。"))
            XCTAssertEqual(today.mood, .veryHigh)
            XCTAssertEqual(today.conditionScore, 5)

            let recreated = AppDataStore(container: try makeContainer(url: storeURL), startsBackgroundServices: false)

            XCTAssertEqual(Set(recreated.habits), Set(expected.habits))
            XCTAssertEqual(Set(recreated.habitRecords), Set(expected.habitRecords))
            XCTAssertEqual(Set(recreated.anniversaries), Set(expected.anniversaries))
            XCTAssertEqual(Set(recreated.healthSummaries), Set(expected.healthSummaries))
            XCTAssertEqual(recreated.memoPad, expected.memo)
            XCTAssertEqual(recreated.letters, expected.letters)
            XCTAssertEqual(Set(recreated.shoppingStore.items), Set(expected.shoppingItems))
            XCTAssertEqual(Set(recreated.shoppingStore.places), Set(expected.shoppingPlaces))
            XCTAssertEqual(Set(recreated.diaryEntries), firstDiaries)
            XCTAssertEqual(Set(recreated.tasks), firstTasks)
            XCTAssertEqual(Set(recreated.calendarEvents), firstEvents)
        }
    }

    func testRepeatedSeeding_doesNotDuplicateAndRepairsMissingRowsDespiteTodaysMarker() throws {
        try withStore { store, _, defaults in
            try store.seedSupplementalSimulatorDemoDataIfNeeded(referenceDate: fixtureDate, isDemoMode: true)
            try store.seedSimulatorReviewMapDataIfNeeded(today: fixtureDate, defaults: defaults, isDemoMode: true)
            try store.seedSimulatorScheduleDataIfNeeded(today: fixtureDate, defaults: defaults, isDemoMode: true)
            let originalHabits = Set(store.habits)
            let originalRecords = Set(store.habitRecords)
            let originalItems = Set(store.shoppingStore.items)
            let originalDiaries = Set(store.diaryEntries)
            let originalTasks = Set(store.tasks)
            let originalEvents = Set(store.calendarEvents)

            XCTAssertFalse(try store.seedSupplementalSimulatorDemoDataIfNeeded(referenceDate: fixtureDate, isDemoMode: true))
            XCTAssertFalse(try store.seedSimulatorReviewMapDataIfNeeded(today: fixtureDate, defaults: defaults, isDemoMode: true))
            XCTAssertFalse(try store.seedSimulatorScheduleDataIfNeeded(today: fixtureDate, defaults: defaults, isDemoMode: true))
            XCTAssertFalse(store.modelContext.hasChanges)
            let deletedItem = try XCTUnwrap(try store.modelContext.fetch(FetchDescriptor<SDShoppingItem>()).first)
            let deletedDiary = try XCTUnwrap(try store.modelContext.fetch(FetchDescriptor<SDDiaryEntry>()).first)
            let truncatedDiary = try XCTUnwrap(try store.modelContext.fetch(FetchDescriptor<SDDiaryEntry>()).first {
                $0.id != deletedDiary.id
            })
            var truncatedEntry = DiaryEntry(sd: truncatedDiary)
            truncatedEntry.locations = Array(truncatedEntry.locations.prefix(1))
            truncatedDiary.update(from: truncatedEntry)
            let deletedTask = try XCTUnwrap(try store.modelContext.fetch(FetchDescriptor<SDTask>()).first)
            let deletedEvent = try XCTUnwrap(try store.modelContext.fetch(FetchDescriptor<SDCalendarEvent>()).first)
            store.modelContext.delete(deletedItem)
            store.modelContext.delete(deletedDiary)
            store.modelContext.delete(deletedTask)
            store.modelContext.delete(deletedEvent)
            try store.modelContext.save()
            XCTAssertEqual(defaults.object(forKey: "demo.reviewMap.seededDay.v1") as? Date, fixtureDate)

            XCTAssertTrue(try store.seedSupplementalSimulatorDemoDataIfNeeded(referenceDate: fixtureDate, isDemoMode: true))
            XCTAssertTrue(try store.seedSimulatorReviewMapDataIfNeeded(today: fixtureDate, defaults: defaults, isDemoMode: true))
            XCTAssertTrue(try store.seedSimulatorScheduleDataIfNeeded(today: fixtureDate, defaults: defaults, isDemoMode: true))

            XCTAssertEqual(Set(store.habits), originalHabits)
            XCTAssertEqual(Set(store.habitRecords), originalRecords)
            XCTAssertEqual(Set(store.shoppingStore.items), originalItems)
            XCTAssertEqual(Set(store.diaryEntries), originalDiaries)
            XCTAssertEqual(Set(store.tasks), originalTasks)
            XCTAssertEqual(Set(store.calendarEvents), originalEvents)
            XCTAssertEqual(try store.modelContext.fetchCount(FetchDescriptor<SDMemoPad>()), 1)
            XCTAssertEqual(try store.modelContext.fetchCount(FetchDescriptor<SDLetter>()), 1)
            XCTAssertEqual(try store.modelContext.fetchCount(FetchDescriptor<SDHealthSummary>()), 7)
            XCTAssertEqual(Set(store.diaryEntries.flatMap(\.locations).map(\.id)).count, 1_000)
        }
    }

    func testSeeding_preservesExistingRowsMemoAndHealthForTheSameDay() throws {
        try withStore { store, _, defaults in
            let task = Task(title: "My task", startDate: fixtureDate, endDate: fixtureDate, priority: .low)
            let event = CalendarEvent(title: "My event", detail: "My notes", startDate: fixtureDate,
                                      endDate: fixtureDate.addingTimeInterval(3_600), calendarName: "My category")
            let habit = Habit(title: "My custom habit", iconName: "heart", colorHex: "#123456", schedule: .daily,
                              createdAt: fixtureDate.addingTimeInterval(-86_400))
            let anniversary = Anniversary(title: "My anniversary", targetDate: fixtureDate, type: .since,
                                          repeatsYearly: false)
            var health = HealthSummary(date: fixtureDate.addingTimeInterval(1_200))
            health.steps = 123
            health.sleepHours = 3.25
            let memo = MemoPad(text: "My saved memo", lastUpdatedAt: fixtureDate.addingTimeInterval(-100))
            let letter = Letter(content: "My draft", createdAt: fixtureDate, deliveryDate: fixtureDate, status: .draft)
            let place = ShoppingPlace(name: "My shop", orderIndex: 0)
            let item = ShoppingItem(title: "My item", note: "My note", placeID: place.id, createdAt: fixtureDate)
            let diary = DiaryEntry(date: fixtureDate, text: "My diary", mood: .high, conditionScore: 4)
            let firstDemoHabit = try XCTUnwrap(SimulatorDemoFixtures.snapshot(referenceDate: fixtureDate).habits.first)
            let existingRecord = HabitRecord(habitID: firstDemoHabit.id, date: fixtureDate, isCompleted: false)
            store.modelContext.insert(SDTask(domain: task))
            store.modelContext.insert(SDCalendarEvent(domain: event))
            store.modelContext.insert(SDHabit(domain: habit))
            store.modelContext.insert(SDHabitRecord(domain: existingRecord))
            store.modelContext.insert(SDAnniversary(domain: anniversary))
            store.modelContext.insert(SDHealthSummary(domain: health))
            store.modelContext.insert(SDMemoPad(text: memo.text, lastUpdatedAt: memo.lastUpdatedAt))
            store.modelContext.insert(SDLetter(domain: letter))
            store.modelContext.insert(SDShoppingPlace(id: place.id, name: place.name, orderIndex: place.orderIndex))
            store.modelContext.insert(SDShoppingItem(domain: item))
            store.modelContext.insert(SDDiaryEntry(domain: diary))
            try store.modelContext.save()

            try store.seedSupplementalSimulatorDemoDataIfNeeded(referenceDate: fixtureDate, isDemoMode: true)
            try store.seedSimulatorReviewMapDataIfNeeded(today: fixtureDate, defaults: defaults, isDemoMode: true)
            try store.seedSimulatorScheduleDataIfNeeded(today: fixtureDate, defaults: defaults, isDemoMode: true)

            XCTAssertTrue(store.tasks.contains(task))
            XCTAssertTrue(store.calendarEvents.contains(event))
            XCTAssertTrue(store.habits.contains(habit))
            XCTAssertTrue(store.habitRecords.contains(existingRecord))
            XCTAssertEqual(store.habitRecords.filter { $0.habitID == firstDemoHabit.id &&
                Calendar.current.isDate($0.date, inSameDayAs: fixtureDate) }, [existingRecord])
            XCTAssertTrue(store.anniversaries.contains(anniversary))
            XCTAssertEqual(store.healthSummaries.filter { Calendar.current.isDate($0.date, inSameDayAs: fixtureDate) }, [health])
            XCTAssertEqual(store.healthSummaries.count, 7)
            XCTAssertEqual(store.memoPad, memo)
            XCTAssertTrue(store.letters.contains(letter))
            XCTAssertTrue(store.shoppingStore.items.contains(item))
            XCTAssertTrue(store.shoppingStore.places.contains(place))
            XCTAssertTrue(store.diaryEntries.contains(diary))
            XCTAssertEqual(store.diaryEntries.count, 7)
        }
    }

    private var fixtureDate: Date {
        Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_760_400_000))
    }

    private func withStore(filename: String = "simulator-demo.store",
                           operation: (AppDataStore, URL, UserDefaults) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "SimulatorDemoSeedingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent(filename)
        let store = AppDataStore(container: try makeContainer(url: url), startsBackgroundServices: false)
        try operation(store, url, defaults)
    }

    private func makeContainer(url: URL) throws -> ModelContainer {
        let schema = Schema([
            SDTask.self, SDDiaryEntry.self, SDHabit.self, SDHabitRecord.self, SDAnniversary.self,
            SDHealthSummary.self, SDCalendarEvent.self, SDMemoPad.self, SDAppState.self,
            SDLetter.self, SDSharedLetter.self, SDShoppingItem.self, SDShoppingPlace.self
        ])
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
#endif
