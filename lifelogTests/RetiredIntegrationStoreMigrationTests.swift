import Foundation
import SwiftData
import XCTest
@testable import lifelify

/// Uses a temporary SQLite store, never the app's App Group store, Firebase,
/// CloudKit, Keychain, or an existing photo directory.
@MainActor
final class RetiredIntegrationStoreMigrationTests: XCTestCase {
    func testRemovingScalarIntegrationSidecars_preservesNativeRecordsAndOriginalPhotoFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("retired-integration-migration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("fixture.store")
        let photoURL = directory.appendingPathComponent("original-diary-photo.jpg")
        let visitPhotoURL = directory.appendingPathComponent("original-visit-photo.jpg")
        let photoBytes = Data("local original fixture".utf8)
        let visitPhotoBytes = Data("local visit original fixture".utf8)
        try photoBytes.write(to: photoURL)
        try visitPhotoBytes.write(to: visitPhotoURL)

        let date = Date(timeIntervalSince1970: 1_750_000_000)
        let visit = DiaryLocation(name: "残す訪問先", address: "元の住所", latitude: 35.6,
                                  longitude: 139.7, mapItemURL: "https://maps.apple.com/?q=fixture",
                                  photoPaths: [visitPhotoURL.path], visitTags: ["元のタグ"])
        let diary = DiaryEntry(date: date, text: "残す日記本文\n写真も保持する。",
                               dateOnlyTimeZoneIdentifier: "Asia/Tokyo", mood: nil,
                               conditionScore: nil, locations: [visit],
                               photoPaths: [photoURL.path], locationPhotoPaths: [visitPhotoURL.path],
                               favoritePhotoPath: visitPhotoURL.path)
        let place = ShoppingPlace(name: "残す購入先", orderIndex: 3)
        let item = ShoppingItem(title: "残す商品", note: "2個\n元のメモ", placeID: place.id, createdAt: date)
        let taskID = UUID()
        let habitID = UUID()
        let letterID = UUID()

        // Keep the fixture's native membership synchronized with the actual
        // production schema. Only the two scalar journals exist in the old schema.
        XCTAssertEqual(Set(Schema(nativeTypes).entities.map(\.name)),
                       Set(PersistenceController.localSchema.entities.map(\.name)))
        let oldSchema = Schema(nativeTypes + [
            RetiredIntegrationSchema.SDShoppingSyncState.self,
            RetiredIntegrationSchema.SDDiaryPhotoCloudState.self
        ])
        weak var releasedContainer: ModelContainer?
        try autoreleasepool {
            let container = try makeContainer(at: storeURL, schema: oldSchema)
            releasedContainer = container
            let context = ModelContext(container)
            context.autosaveEnabled = false
            context.insert(SDDiaryEntry(domain: diary))
            context.insert(SDShoppingPlace(id: place.id, name: place.name, orderIndex: place.orderIndex))
            context.insert(SDShoppingItem(domain: item))
            context.insert(SDTask(id: taskID, title: "残すタスク", detail: "元の詳細", startDate: date,
                                  priority: .high, reminderDate: date.addingTimeInterval(60)))
            context.insert(SDHabit(id: habitID, title: "残す習慣", iconName: "book", colorHex: "#123456",
                                   schedule: .daily, createdAt: date, orderIndex: 2))
            context.insert(SDHabitRecord(habitID: habitID, date: date, isCompleted: true))
            context.insert(SDAnniversary(title: "残す記念日", targetDate: date, type: .since,
                                         repeatsYearly: false, startLabel: "元のラベル", orderIndex: 4))
            context.insert(SDHealthSummary(date: date, steps: 1234, sleepHours: 7.25, activeEnergy: 320))
            context.insert(SDCalendarEvent(title: "残す予定", detail: "予定の詳細", startDate: date,
                                           endDate: date.addingTimeInterval(3600), calendarName: "元のカテゴリ",
                                           reminderMinutes: 15))
            context.insert(SDMemoPad(text: "残すメモ", lastUpdatedAt: date))
            context.insert(SDAppState(lastCalendarSyncDate: date, diaryReminderEnabled: true,
                                      diaryReminderHour: 20, diaryReminderMinute: 15))
            context.insert(SDLetter(id: letterID, content: "残す手紙本文", photoPaths: [photoURL.path],
                                    createdAt: date, deliveryDate: date.addingTimeInterval(86_400),
                                    statusRaw: "sealed", randomUseTimeRange: true, randomStartHour: 10,
                                    randomStartMinute: 20, randomEndHour: 18, randomEndMinute: 40))
            context.insert(SDSharedLetter(id: "local-shared-letter-fixture", senderId: "local-sender-fixture",
                                          senderEmoji: "🌷", senderName: "元の送信者", content: "残す受信手紙",
                                          photoPaths: [visitPhotoURL.path], deliveredAt: date, openedAt: date))
            context.insert(RetiredIntegrationSchema.SDShoppingSyncState(payload: Data("retired cursor".utf8)))
            context.insert(RetiredIntegrationSchema.SDDiaryPhotoCloudState(
                id: "diary-photos", payload: Data("retired upload journal".utf8)))
            try context.save()
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<RetiredIntegrationSchema.SDShoppingSyncState>()), 1)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<RetiredIntegrationSchema.SDDiaryPhotoCloudState>()), 1)
        }
        XCTAssertNil(releasedContainer, "Release the old container before reopening its SQLite file.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))

        // Verify the migration and a second ordinary launch, both with only the
        // current 13 native entities. No fallback/quarantine/reset path is used.
        for _ in 0..<2 {
            try autoreleasepool {
                let schema = PersistenceController.localSchema
                XCTAssertEqual(schema.entities.count, 13)
                let container = try makeContainer(at: storeURL, schema: schema)
                let context = ModelContext(container)
                context.autosaveEnabled = false
                XCTAssertEqual(DiaryEntry(sd: try only(SDDiaryEntry.self, in: context)), diary)
                let savedPlace = try only(SDShoppingPlace.self, in: context)
                XCTAssertEqual(savedPlace.id, place.id)
                XCTAssertEqual(savedPlace.name, place.name)
                XCTAssertEqual(savedPlace.orderIndex, place.orderIndex)
                let savedItem = try only(SDShoppingItem.self, in: context)
                XCTAssertEqual(savedItem.id, item.id)
                XCTAssertEqual(savedItem.title, item.title)
                XCTAssertEqual(savedItem.note, item.note)
                XCTAssertEqual(savedItem.placeID, place.id)
                XCTAssertEqual(savedItem.createdAt, date)
                let task = try only(SDTask.self, in: context)
                XCTAssertEqual(task.id, taskID)
                XCTAssertEqual(task.detail, "元の詳細")
                XCTAssertEqual(task.reminderDate, date.addingTimeInterval(60))
                XCTAssertEqual(try only(SDHabit.self, in: context).id, habitID)
                let completion = try only(SDHabitRecord.self, in: context)
                XCTAssertEqual(completion.habitID, habitID)
                XCTAssertTrue(completion.isCompleted)
                XCTAssertEqual(try only(SDAnniversary.self, in: context).startLabel, "元のラベル")
                let health = try only(SDHealthSummary.self, in: context)
                XCTAssertEqual(health.steps, 1234)
                XCTAssertEqual(health.sleepHours, 7.25)
                XCTAssertEqual(health.activeEnergy, 320)
                let event = try only(SDCalendarEvent.self, in: context)
                XCTAssertEqual(event.calendarName, "元のカテゴリ")
                XCTAssertEqual(event.detail, "予定の詳細")
                XCTAssertEqual(event.reminderMinutes, 15)
                XCTAssertEqual(try only(SDMemoPad.self, in: context).text, "残すメモ")
                let settings = try only(SDAppState.self, in: context)
                XCTAssertTrue(settings.diaryReminderEnabled)
                XCTAssertEqual(settings.diaryReminderHour, 20)
                XCTAssertEqual(settings.diaryReminderMinute, 15)
                let letter = try only(SDLetter.self, in: context)
                XCTAssertEqual(letter.id, letterID)
                XCTAssertEqual(letter.content, "残す手紙本文")
                XCTAssertEqual(letter.photoPaths, [photoURL.path])
                XCTAssertEqual(letter.statusRaw, "sealed")
                XCTAssertEqual(letter.deliveryDate, date.addingTimeInterval(86_400))
                XCTAssertTrue(letter.randomUseTimeRange)
                XCTAssertEqual(letter.randomStartMinute, 20)
                XCTAssertEqual(letter.randomEndMinute, 40)
                let sharedLetter = try only(SDSharedLetter.self, in: context)
                XCTAssertEqual(sharedLetter.id, "local-shared-letter-fixture")
                XCTAssertEqual(sharedLetter.senderName, "元の送信者")
                XCTAssertEqual(sharedLetter.content, "残す受信手紙")
                XCTAssertEqual(sharedLetter.photoPaths, [visitPhotoURL.path])
            }
        }
        XCTAssertEqual(try Data(contentsOf: photoURL), photoBytes)
        XCTAssertEqual(try Data(contentsOf: visitPhotoURL), visitPhotoBytes)
    }

    private var nativeTypes: [any PersistentModel.Type] {
        [SDTask.self, SDDiaryEntry.self, SDHabit.self, SDHabitRecord.self,
         SDAnniversary.self, SDHealthSummary.self, SDCalendarEvent.self,
         SDMemoPad.self, SDAppState.self, SDLetter.self, SDSharedLetter.self,
         SDShoppingItem.self, SDShoppingPlace.self]
    }

    private func makeContainer(at url: URL, schema: Schema) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func only<Model: PersistentModel>(_ type: Model.Type, in context: ModelContext) throws -> Model {
        let records = try context.fetch(FetchDescriptor<Model>())
        XCTAssertEqual(records.count, 1, "Expected exactly one preserved \(type) record.")
        return try XCTUnwrap(records.first)
    }
}

/// Exact scalar entity names, attributes, and initializers from the retired
/// integration. Kept exclusively in the test target, never the app schema.
private enum RetiredIntegrationSchema {
    @Model
    final class SDShoppingSyncState {
        @Attribute(.unique) var id: String
        var payload: Data
        init(id: String = "shopping", payload: Data) { self.id = id; self.payload = payload }
    }

    @Model
    final class SDDiaryPhotoCloudState {
        @Attribute(.unique) var id: String
        var payload: Data
        init(id: String, payload: Data) { self.id = id; self.payload = payload }
    }
}
