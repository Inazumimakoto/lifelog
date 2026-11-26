import SwiftData
import UIKit
import XCTest
@testable import lifelify

@MainActor
final class WallpaperCalendarExportTests: XCTestCase {
    func testUnchangedCalendar_reusesImageUntilLocalMidnight() throws {
        let suite = "WallpaperExportTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        let files = WallpaperCalendarPhotoBackgroundTests.IsolatedFileManager(rootURL: directory)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? files.removeItem(at: directory)
        }

        let persistence = PersistenceController(inMemory: true)
        let provider = WallpaperCalendarDataProvider(displayDefaults: defaults,
                                                     modelContext: { persistence.container.mainContext },
                                                     externalDefaults: { defaults })
        let settings = WallpaperCalendarSettingsStore(defaults: defaults, fileManager: files)
        let renderer = WallpaperCalendarRenderer(settingsStore: settings, dataProvider: provider, fileManager: files)
        func render(at date: Date) throws -> URL {
            try renderer.render(now: date, screenSize: CGSize(width: 390, height: 844), scale: 1)
        }

        // Both days fall in the same display week for either supported week start.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = WallpaperCalendarDataProvider.calendar.timeZone
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 9)))
        let lateEvening = try XCTUnwrap(calendar.date(bySettingHour: 23, minute: 59, second: 59, of: morning))
        let midnight = lateEvening.addingTimeInterval(1)

        let firstURL = try render(at: morning)
        let firstImage = try Data(contentsOf: firstURL)
        let timestamp = Date(timeIntervalSince1970: 946_684_800)
        try files.setAttributes([.modificationDate: timestamp], ofItemAtPath: firstURL.path)

        let cachedURL = try render(at: lateEvening)
        let attributes = try files.attributesOfItem(atPath: cachedURL.path)
        XCTAssertEqual(attributes[.modificationDate] as? Date, timestamp)

        let nextImage = try Data(contentsOf: render(at: midnight))
        XCTAssertNotEqual(nextImage, firstImage, "The highlight should move after midnight with no edits to the calendar.")
        let snapshot = renderer.makePreviewSnapshot(settings: settings.load(), now: midnight)
        let highlightedDates = snapshot.weeks.flatMap(\.days).map(\.date).filter(snapshot.isToday)
        XCTAssertEqual(highlightedDates, [midnight])
    }

    func testPhotoWallpaperWithSavedEvents_writesJPEGUsingShortcutRenderPath() throws {
        let suite = "WallpaperExportTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        let files = WallpaperCalendarPhotoBackgroundTests.IsolatedFileManager(rootURL: directory)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? files.removeItem(at: directory)
        }

        let persistence = PersistenceController(inMemory: true)
        let provider = WallpaperCalendarDataProvider(displayDefaults: defaults,
                                                    modelContext: { persistence.container.mainContext }, externalDefaults: { defaults })
        let settings = WallpaperCalendarSettingsStore(defaults: defaults, fileManager: files)
        let renderer = WallpaperCalendarRenderer(settingsStore: settings, dataProvider: provider, fileManager: files)
        let size = CGSize(width: 390, height: 844)
        let photo = UIGraphicsImageRenderer(size: size).image { renderer in
            let backdrop = CAGradientLayer()
            backdrop.frame = CGRect(origin: .zero, size: size)
            backdrop.colors = [UIColor(white: 0.14, alpha: 1).cgColor, UIColor(white: 0.92, alpha: 1).cgColor]
            backdrop.startPoint = CGPoint(x: 0, y: 0.5)
            backdrop.endPoint = CGPoint(x: 1, y: 0.5)
            backdrop.render(in: renderer.cgContext)
        }
        _ = try settings.saveBackgroundImageData(XCTUnwrap(photo.jpegData(compressionQuality: 0.94)))

        let calendar = WallpaperCalendarDataProvider.calendar
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 10)))
        let noEvents = try Data(contentsOf: renderer.render(now: now, screenSize: size, scale: 3))
        let meeting = SDCalendarEvent(title: "打合せ", startDate: now,
                                      endDate: now.addingTimeInterval(3600), calendarName: "Work")
        let trip = SDCalendarEvent(title: "東京出張 B8", startDate: now,
                                   endDate: try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: now)), calendarName: "Travel")
        let context = persistence.container.mainContext
        context.insert(meeting)
        context.insert(trip)
        try context.save()

        let snapshot = renderer.makePreviewSnapshot(settings: settings.load(), now: now)
        XCTAssertTrue(snapshot.weeks.flatMap(\.multiDayLayout.segments).contains { $0.eventID == trip.id })
        XCTAssertTrue(snapshot.weeks.flatMap(\.days).flatMap(\.rowContents).contains {
            if case .item(let item) = $0 { return item.sourceID == meeting.id }
            return false
        })

        // perform() reads this exact file and returns its bytes as an IntentFile.
        let url = try renderer.render(force: false, now: now, screenSize: size, scale: 3)
        let jpeg = try Data(contentsOf: url)
        XCTAssertNotEqual(jpeg, noEvents)
        XCTAssertEqual(jpeg.prefix(2), Data([0xFF, 0xD8]))
        let image = try XCTUnwrap(UIImage(data: jpeg)?.cgImage)
        XCTAssertEqual(image.width, 1170)
        XCTAssertEqual(image.height, 2532)
        let attachment = XCTAttachment(contentsOfFile: url)
        attachment.name = "Photo wallpaper with Japanese events.jpg"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
