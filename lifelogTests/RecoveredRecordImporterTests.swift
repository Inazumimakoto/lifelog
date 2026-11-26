import SwiftData
import XCTest
@testable import lifelify

@MainActor
final class RecoveredRecordImporterTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = PersistenceController.localSchema
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testRecovery_allPersistedTypesSurviveAndSecondImportAddsNothing() throws {
        let archive = try makeContainer()
        let active = try makeContainer()
        let old = archive.mainContext
        let day = Date()
        let habit = SDHabit(title: "Habit", iconName: "book", colorHex: "#123456", schedule: .daily, orderIndex: 7)
        let anniversary = SDAnniversary(title: "Anniversary", targetDate: day, type: .since, repeatsYearly: true, orderIndex: 3)
        let event = SDCalendarEvent(title: "Event", startDate: day, endDate: day, calendarName: "Personal",
                                    recurrenceRuleData: Data([1, 2]))
        let visitData = Data([9, 7]) // Preserve even legacy payloads verbatim when copying a complete record.
        let diary = SDDiaryEntry(date: day, text: "Diary", locationsData: visitData, photoPaths: ["original.jpg"])
        let place = SDShoppingPlace(name: "Bakery")
        let item = SDShoppingItem(title: "Bread", note: "note", placeID: place.id, createdAt: day)
        item.legacyQuantity = "2"
        old.insert(SDTask(title: "Task"))
        old.insert(diary)
        old.insert(habit)
        old.insert(SDHabitRecord(habitID: habit.id, date: day, isCompleted: true))
        old.insert(anniversary)
        old.insert(SDHealthSummary(date: day, steps: 3000, fitnessMoveModeRaw: "legacy-mode"))
        old.insert(event)
        old.insert(SDCalendarEventException(seriesID: event.id, originalStartDate: day, replacementData: Data([4, 9])))
        old.insert(SDMemoPad(text: "Memo", lastUpdatedAt: day))
        old.insert(SDAppState(diaryReminderEnabled: true, diaryReminderHour: 8))
        old.insert(SDLetter(content: "Letter", deliveryType: "unknown", deliveryDate: day, randomStartMinute: 19))
        old.insert(SDSharedLetter(id: "s1", senderId: "u1", senderEmoji: "A", senderName: "Sender", content: "Shared",
                                  photoPaths: ["image.jpg"], deliveredAt: day, openedAt: day))
        old.insert(place)
        old.insert(item)
        try old.save()

        XCTAssertEqual(try RecoveredRecordImporter.restore(from: archive, into: active), 14)
        XCTAssertEqual(try RecoveredRecordImporter.restore(from: archive, into: active), 0)
        let result = ModelContext(active)
        XCTAssertEqual(try result.fetch(FetchDescriptor<SDTask>()).first?.title, "Task")
        let restoredDiary = try XCTUnwrap(result.fetch(FetchDescriptor<SDDiaryEntry>()).first)
        XCTAssertEqual(restoredDiary.id, diary.id)
        XCTAssertEqual(restoredDiary.photoPaths, ["original.jpg"])
        XCTAssertEqual(restoredDiary.locationsData, visitData)
        XCTAssertEqual(try result.fetch(FetchDescriptor<SDHabit>()).first?.orderIndex, 7)
        XCTAssertEqual(try result.fetch(FetchDescriptor<SDHabitRecord>()).first?.habitID, habit.id)
        XCTAssertEqual(try result.fetch(FetchDescriptor<SDAnniversary>()).first?.orderIndex, 3)
        XCTAssertEqual(try result.fetch(FetchDescriptor<SDHealthSummary>()).first?.fitnessMoveModeRaw, "legacy-mode")
        XCTAssertEqual(try result.fetch(FetchDescriptor<SDCalendarEvent>()).first?.recurrenceRuleData, Data([1, 2]))
        XCTAssertEqual(try result.fetch(FetchDescriptor<SDCalendarEventException>()).first?.replacementData, Data([4, 9]))
        XCTAssertEqual(try result.fetch(FetchDescriptor<SDMemoPad>()).first?.text, "Memo")
        XCTAssertEqual(try result.fetch(FetchDescriptor<SDAppState>()).first?.diaryReminderHour, 8)
        XCTAssertEqual(try result.fetch(FetchDescriptor<SDLetter>()).first?.deliveryType, "unknown")
        XCTAssertEqual(try result.fetch(FetchDescriptor<SDSharedLetter>()).first?.senderId, "u1")
        XCTAssertEqual(try result.fetch(FetchDescriptor<SDShoppingPlace>()).first?.id, place.id)
        XCTAssertEqual(try result.fetch(FetchDescriptor<SDShoppingItem>()).first?.legacyQuantity, "2")
    }

    func testCollisions_preserveNewRecordsMergeDiaryMemoAndMatchNaturalKeys() throws {
        let archive = try makeContainer()
        let active = try makeContainer()
        let old = archive.mainContext
        let new = active.mainContext
        let day = Date()
        let taskID = UUID()
        old.insert(SDTask(id: taskID, title: "Earlier"))
        new.insert(SDTask(id: taskID, title: "Edited after reset"))
        let currentDiary = SDDiaryEntry(date: day, text: "New", photoPaths: ["new.jpg"])
        old.insert(SDDiaryEntry(date: day, text: "Old", locationName: "Park", latitude: 10, longitude: 20,
                                photoPaths: ["old.jpg"]))
        new.insert(currentDiary)
        old.insert(SDMemoPad(text: "Old memo"))
        new.insert(SDMemoPad(text: "New memo"))
        let oldLink = CalendarCategoryLink(calendarIdentifier: "work", calendarTitle: "Work", categoryId: "Original")
        let currentLink = CalendarCategoryLink(calendarIdentifier: "work", calendarTitle: "Work", categoryId: nil)
        let personal = CalendarCategoryLink(calendarIdentifier: "personal", calendarTitle: "Personal")
        old.insert(SDAppState(calendarCategoryLinks: [oldLink, personal], diaryReminderEnabled: true, diaryReminderHour: 9))
        new.insert(SDAppState(calendarCategoryLinks: [currentLink], diaryReminderEnabled: true, diaryReminderHour: 7))
        let oldPlace = SDShoppingPlace(name: "Bakery")
        let currentPlace = SDShoppingPlace(name: "BAKERY")
        old.insert(oldPlace)
        new.insert(currentPlace)
        old.insert(SDShoppingItem(title: "Bread", placeID: oldPlace.id))
        old.insert(SDHealthSummary(date: day, steps: 20, sleepHours: 7))
        new.insert(SDHealthSummary(date: day, steps: 50))
        let habitID = UUID()
        old.insert(SDHabitRecord(habitID: habitID, date: day, isCompleted: true))
        new.insert(SDHabitRecord(habitID: habitID, date: day, isCompleted: false))
        let seriesID = UUID()
        old.insert(SDCalendarEventException(seriesID: seriesID, originalStartDate: day, replacementData: Data([1])))
        new.insert(SDCalendarEventException(seriesID: seriesID, originalStartDate: day))
        try old.save()
        try new.save()

        XCTAssertEqual(try RecoveredRecordImporter.restore(from: archive, into: active), 5)
        XCTAssertEqual(try RecoveredRecordImporter.restore(from: archive, into: active), 0)
        let result = ModelContext(active)
        let diaries = try result.fetch(FetchDescriptor<SDDiaryEntry>())
        XCTAssertEqual(diaries.count, 1)
        let recovered = try XCTUnwrap(diaries.first)
        XCTAssertEqual(recovered.id, currentDiary.id)
        XCTAssertEqual(recovered.text, "New\n\nOld")
        XCTAssertEqual(recovered.photoPaths, ["new.jpg", "old.jpg"])
        XCTAssertEqual(DiaryEntry(sd: recovered).locations.map(\.name), ["Park"])
        XCTAssertEqual(try result.fetch(FetchDescriptor<SDMemoPad>()).first?.text, "New memo\n\nOld memo")
        let state = try XCTUnwrap(result.fetch(FetchDescriptor<SDAppState>()).first)
        XCTAssertEqual(state.calendarCategoryLinks, [currentLink, personal])
        XCTAssertEqual(state.diaryReminderHour, 7)
        XCTAssertEqual(try result.fetch(FetchDescriptor<SDTask>()).first?.title, "Edited after reset")
        XCTAssertEqual(try result.fetchCount(FetchDescriptor<SDShoppingPlace>()), 1)
        XCTAssertEqual(try result.fetch(FetchDescriptor<SDShoppingItem>()).first?.placeID, currentPlace.id)
        let summary = try XCTUnwrap(result.fetch(FetchDescriptor<SDHealthSummary>()).first)
        XCTAssertEqual(summary.steps, 50)
        XCTAssertEqual(summary.sleepHours, 7)
        XCTAssertEqual(try result.fetchCount(FetchDescriptor<SDHabitRecord>()), 1)
        XCTAssertEqual(try result.fetch(FetchDescriptor<SDHabitRecord>()).first?.isCompleted, false)
        XCTAssertEqual(try result.fetchCount(FetchDescriptor<SDCalendarEventException>()), 1)
        XCTAssertNil(try result.fetch(FetchDescriptor<SDCalendarEventException>()).first?.replacementData)
    }

    func testSameDiaryIdentity_retainsNewTextAndFavoriteAndRecoversEarlierTextAndMediaOnce() throws {
        let archive = try makeContainer()
        let active = try makeContainer()
        let id = UUID()
        let day = Date()
        let visitID = UUID()
        let oldVisit = DiaryLocation(id: visitID, name: "Original", address: nil, latitude: 5,
                                     longitude: 10, mapItemURL: nil, photoPaths: ["old-visit.jpg"])
        let currentVisit = DiaryLocation(id: visitID, name: "New name", address: nil, latitude: 5,
                                         longitude: 10, mapItemURL: nil, photoPaths: ["new-visit.jpg"])
        let old = SDDiaryEntry(id: id, date: day, text: "Earlier text", locationsData: try JSONEncoder().encode([oldVisit]),
                               photoPaths: ["earlier.mov"], favoritePhotoPath: "earlier.mov")
        let current = SDDiaryEntry(id: id, date: day, text: "New text", locationsData: try JSONEncoder().encode([currentVisit]),
                                   photoPaths: ["now.jpg"], favoritePhotoPath: "now.jpg")
        archive.mainContext.insert(old)
        active.mainContext.insert(current)
        try archive.mainContext.save()
        try active.mainContext.save()

        XCTAssertEqual(try RecoveredRecordImporter.restore(from: archive, into: active), 1)
        XCTAssertEqual(try RecoveredRecordImporter.restore(from: archive, into: active), 0)
        let context = ModelContext(active)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SDDiaryEntry>()), 1)
        let restored = try XCTUnwrap(context.fetch(FetchDescriptor<SDDiaryEntry>()).first)
        XCTAssertEqual(restored.text, "New text\n\nEarlier text")
        XCTAssertEqual(restored.photoPaths, ["now.jpg", "earlier.mov"])
        XCTAssertEqual(restored.favoritePhotoPath, "now.jpg")
        let visit = try XCTUnwrap(DiaryEntry(sd: restored).locations.first)
        XCTAssertEqual(visit.name, "New name")
        XCTAssertEqual(visit.photoPaths, ["new-visit.jpg", "old-visit.jpg"])
    }

    func testInterruptedMerge_rollsBackEverythingAndLeavesSourceIntact() throws {
        let archive = try makeContainer()
        let active = try makeContainer()
        let day = Date()
        let unreadableLocations = Data([0xff])
        archive.mainContext.insert(SDTask(title: "Copied before diary validation"))
        archive.mainContext.insert(SDDiaryEntry(date: day, text: "Recovered", locationsData: unreadableLocations))
        active.mainContext.insert(SDDiaryEntry(date: day, text: "Keep this"))
        try archive.mainContext.save()
        try active.mainContext.save()

        XCTAssertThrowsError(try RecoveredRecordImporter.restore(from: archive, into: active))
        let result = ModelContext(active)
        XCTAssertEqual(try result.fetchCount(FetchDescriptor<SDTask>()), 0)
        XCTAssertEqual(try result.fetch(FetchDescriptor<SDDiaryEntry>()).first?.text, "Keep this")
        XCTAssertEqual(try ModelContext(archive).fetch(FetchDescriptor<SDDiaryEntry>()).first?.locationsData, unreadableLocations)
    }

    func testOriginalDuplicateHabitDay_preservesBothRecordsAndDoesNotDuplicateOnRetry() throws {
        let archive = try makeContainer()
        let active = try makeContainer()
        let habitID = UUID()
        let day = Date()
        archive.mainContext.insert(SDHabitRecord(habitID: habitID, date: day, isCompleted: true))
        archive.mainContext.insert(SDHabitRecord(habitID: habitID, date: day, isCompleted: false))
        try archive.mainContext.save()

        XCTAssertEqual(try RecoveredRecordImporter.restore(from: archive, into: active), 2)
        XCTAssertEqual(try RecoveredRecordImporter.restore(from: archive, into: active), 0)
        let records = try ModelContext(active).fetch(FetchDescriptor<SDHabitRecord>())
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.filter(\.isCompleted).count, 1)
    }
}
