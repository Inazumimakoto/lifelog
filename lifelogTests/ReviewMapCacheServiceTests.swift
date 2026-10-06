import XCTest
#if canImport(lifelify)
@testable import lifelify
#else
@testable import ReviewMapCacheCore
#endif

@MainActor
final class ReviewMapCacheServiceTests: XCTestCase {
    func testUnchangedInput_reusesSnapshotWithoutRebuildOrWrite() async throws {
        let url = try temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = ReviewMapCacheService(fileURL: url)
        let sources = sampleSources()

        let first = await service.snapshot(sources: sources, tags: tags, query: .init(), environment: environment)
        await service.flush()
        let firstWrites = await service.persistentWriteCount
        let second = await service.snapshot(sources: sources, tags: tags, query: .init(), environment: environment)
        await service.flush()
        let rebuilt = await service.lastRebuiltPlaceIDs
        let rendered = await service.lastRenderedPlaceIDs
        let finalWrites = await service.persistentWriteCount

        XCTAssertEqual(second, first)
        XCTAssertTrue(rebuilt.isEmpty)
        XCTAssertTrue(rendered.isEmpty)
        XCTAssertEqual(firstWrites, 1)
        XCTAssertEqual(finalWrites, firstWrites)
    }

    func testActorRecreatedFromDisk_reusesPlacesAndDisplayInformation() async throws {
        let url = try temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = ReviewMapCacheService(fileURL: url)
        let expected = await original.snapshot(sources: sampleSources(), tags: tags, query: .init(), environment: environment)
        await original.flush()

        let reopened = ReviewMapCacheService(fileURL: url)
        let actual = await reopened.snapshot(sources: sampleSources(), tags: tags, query: .init(), environment: environment)
        await reopened.flush()
        let loaded = await reopened.loadedFromDisk
        let rebuilt = await reopened.lastRebuiltPlaceIDs
        let rendered = await reopened.lastRenderedPlaceIDs
        let writes = await reopened.persistentWriteCount

        XCTAssertEqual(actual, expected)
        XCTAssertTrue(loaded)
        XCTAssertTrue(rebuilt.isEmpty)
        XCTAssertTrue(rendered.isEmpty)
        XCTAssertEqual(writes, 0)
    }

    func testAllAndMonthQueries_reuseBothSnapshotsAfterRestart() async throws {
        let url = try temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let sources = [diary(1, day: 6, locations: [location(1, tags: ["Cafe"])]),
                       diary(2, month: 9, day: 30, locations: [location(1, tags: ["Work"])])]
        let month = ReviewMapQuery(monthStart: date(month: 10, day: 1), monthEnd: date(month: 11, day: 1))
        let original = ReviewMapCacheService(fileURL: url)
        let expectedAll = await original.snapshot(sources: sources, tags: tags, query: .init(), environment: environment)
        let expectedMonth = await original.snapshot(sources: sources, tags: tags, query: month, environment: environment)
        await original.flush()

        let reopened = ReviewMapCacheService(fileURL: url)
        let actualAll = await reopened.snapshot(sources: sources, tags: tags, query: .init(), environment: environment)
        let actualMonth = await reopened.snapshot(sources: sources, tags: tags, query: month, environment: environment)
        let rendered = await reopened.lastRenderedPlaceIDs
        let rebuilt = await reopened.lastRebuiltPlaceIDs

        XCTAssertEqual(actualAll, expectedAll)
        XCTAssertEqual(actualMonth, expectedMonth)
        XCTAssertEqual(actualAll.places.first?.count, 2)
        XCTAssertEqual(actualMonth.places.first?.count, 1)
        XCTAssertTrue(rendered.isEmpty)
        XCTAssertTrue(rebuilt.isEmpty)
    }

    func testOnePlacePhotoChanged_rebuildsOnlyThatPlaceAmongThousand() async throws {
        let service = ReviewMapCacheService()
        var sources = [diary(1, day: 6, locations: (0..<1_000).map { location($0, tags: ["Cafe"]) })]
        let original = await service.snapshot(sources: sources, tags: tags, query: .init(), environment: environment)
        let changedLocationID = sources[0].locations[413].id
        sources[0].locations[413].photoPaths = ["changed.jpg"]

        let updated = await service.snapshot(sources: sources, tags: tags, query: .init(), environment: environment)
        let changed = try XCTUnwrap(updated.places.first { $0.location.id == changedLocationID })
        let rebuilt = await service.lastRebuiltPlaceIDs
        let rendered = await service.lastRenderedPlaceIDs

        XCTAssertEqual(updated.places.count, 1_000)
        XCTAssertEqual(rebuilt, Set([changed.id]))
        XCTAssertEqual(rendered, Set([changed.id]))
        XCTAssertEqual(updated.places.filter { $0.id != changed.id },
                       original.places.filter { $0.id != changed.id })
        XCTAssertEqual(changed.visits.first?.photoPaths, ["changed.jpg"])
    }

    func testLocationMovedBetweenGroups_removesOldPlaceAndAddsNewPlace() async {
        let service = ReviewMapCacheService()
        var sources = [diary(1, day: 6, locations: [location(1, tags: ["Cafe"])])]
        let original = await service.snapshot(sources: sources, tags: tags, query: .init(), environment: environment)
        sources[0].locations[0].name = "Another cafe"
        sources[0].locations[0].latitude += 0.01

        let changed = await service.snapshot(sources: sources, tags: tags, query: .init(), environment: environment)
        XCTAssertEqual(changed.places.count, 1)
        XCTAssertNotEqual(changed.places.first?.id, original.places.first?.id)
        XCTAssertEqual(changed.places.first?.location.name, "Another cafe")

        sources[0].locations = []
        let deleted = await service.snapshot(sources: sources, tags: tags, query: .init(), environment: environment)
        XCTAssertTrue(deleted.places.isEmpty)
    }

    func testSameDayAcrossDiaryIDs_mergesTagsAndPhotosWithoutIncreasingCount() async throws {
        let service = ReviewMapCacheService()
        var morning = location(1, tags: ["Cafe"])
        morning.photoPaths = ["morning.jpg"]
        var evening = location(1, tags: ["Work", " cafe "])
        evening.photoPaths = ["morning.jpg", "evening.jpg"]
        let sources = [diary(1, day: 6, locations: [morning]), diary(2, day: 6, locations: [evening])]

        let snapshot = await service.snapshot(sources: sources, tags: tags, query: .init(), environment: environment)
        let place = try XCTUnwrap(snapshot.places.first)

        XCTAssertEqual(snapshot.places.count, 1)
        XCTAssertEqual(place.count, 1)
        XCTAssertEqual(Set(place.allTags.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }), Set(["cafe", "work"]))
        XCTAssertEqual(Set(place.visits[0].photoPaths), Set(["morning.jpg", "evening.jpg"]))
    }

    func testMonthAndORFilters_countOnlyMatchingVisitsAndColorSelectedTags() async throws {
        let service = ReviewMapCacheService()
        let sources = [diary(1, day: 6, locations: [location(1, tags: ["Cafe", "Work"])]),
                       diary(2, day: 5, locations: [location(1, tags: [])]),
                       diary(3, day: 4, locations: [location(1, tags: ["Work"])]),
                       diary(4, month: 9, day: 30, locations: [location(1, tags: ["Cafe"])])]
        let query = ReviewMapQuery(monthStart: date(month: 10, day: 1), monthEnd: date(month: 11, day: 1),
                                   selectedFilters: [" cafe ", "__untagged__"])

        let snapshot = await service.snapshot(sources: sources, tags: tags, query: query, environment: environment)
        let place = try XCTUnwrap(snapshot.places.first)

        XCTAssertEqual(place.count, 2)
        XCTAssertEqual(place.visits.map(\.date), [date(month: 10, day: 6), date(month: 10, day: 5)])
        XCTAssertEqual(place.compactColorHex, "D87568")
        XCTAssertEqual(place.expandedColorHexes, ["D87568"])
    }

    func testFilterNormalization_preservesUserLabelWhileMatchingCaseAndAccents() async {
        let service = ReviewMapCacheService()
        let query = ReviewMapQuery(selectedFilters: [" CAFÉ ", "cafe"])

        let snapshot = await service.snapshot(sources: sampleSources(), tags: tags,
                                               query: query, environment: environment)

        XCTAssertEqual(snapshot.query.selectedFilters, ["CAFÉ"])
        XCTAssertEqual(snapshot.places.map { $0.location.name }, ["Place 1"])
        XCTAssertEqual(snapshot.places.first?.compactColorHex, "D87568")
    }

    func testUnknownUserTag_keepsOriginalNameInSnapshotAndFilterChoices() async throws {
        let service = ReviewMapCacheService()
        let userTag = "自分の Café 🐈"
        let sources = [diary(1, day: 6, locations: [location(1, tags: [userTag])])]

        let snapshot = await service.snapshot(sources: sources, tags: tags,
                                               query: .init(selectedFilters: [userTag]), environment: environment)
        let place = try XCTUnwrap(snapshot.places.first)

        XCTAssertEqual(place.allTags, [userTag])
        XCTAssertTrue(snapshot.availableTagNames.contains(userTag))
        XCTAssertEqual(snapshot.query.selectedFilters, [userTag])
    }

    func testTagColorChanged_rendersOnlyPlacesUsingThatTag() async throws {
        let service = ReviewMapCacheService()
        var definitions = tags
        let sources = [diary(1, day: 6, locations: [location(1, tags: ["Cafe"]), location(2, tags: ["Work"])])]
        let original = await service.snapshot(sources: sources, tags: definitions, query: .init(), environment: environment)
        definitions[0].colorHex = "112233"

        let updated = await service.snapshot(sources: sources, tags: definitions, query: .init(), environment: environment)
        let cafe = try XCTUnwrap(updated.places.first { $0.location.name == "Place 1" })
        let work = try XCTUnwrap(updated.places.first { $0.location.name == "Place 2" })
        let rebuilt = await service.lastRebuiltPlaceIDs
        let rendered = await service.lastRenderedPlaceIDs

        XCTAssertTrue(rebuilt.isEmpty)
        XCTAssertEqual(rendered, Set([cafe.id]))
        XCTAssertEqual(cafe.compactColorHex, "112233")
        XCTAssertEqual(work, original.places.first { $0.id == work.id })
    }

    func testFrequentTagsAndReordering_keepNineColorsWithStableSegments() async throws {
        let service = ReviewMapCacheService()
        var definitions = (0..<12).map {
            ReviewMapTagSource(id: identifier(100 + $0), name: "Tag \($0)", displayName: "Tag \($0)",
                               sortOrder: $0, colorHex: String(format: "%06X", $0 + 1))
        }
        var sources: [ReviewMapDiarySource] = []
        var day = 1
        for index in 0..<12 {
            for _ in 0...index {
                sources.append(diary(day, day: 1, locations: [location(1, tags: ["Tag \(index)"])]))
                sources[sources.count - 1].date = date(month: 10, day: 6).addingTimeInterval(-Double(day) * 86_400)
                day += 1
            }
        }
        let original = await service.snapshot(sources: sources, tags: definitions, query: .init(), environment: environment)
        let expectedColors = Array(definitions.suffix(9)).map(\.colorHex)
        XCTAssertEqual(original.places.first?.expandedColorHexes, expectedColors)

        definitions[11].sortOrder = -1
        let updated = await service.snapshot(sources: sources, tags: Array(definitions.reversed()), query: .init(), environment: environment)
        let rebuilt = await service.lastRebuiltPlaceIDs
        XCTAssertEqual(updated.places.first?.expandedColorHexes, [definitions[11].colorHex] + Array(expectedColors.dropLast()))
        XCTAssertTrue(rebuilt.isEmpty)
    }

    func testSourceOrderChanged_keepsStablePlaceOrderWithoutRebuild() async {
        let service = ReviewMapCacheService()
        let sources = [diary(8, day: 6, locations: [location(8, tags: ["Cafe"])]),
                       diary(2, day: 6, locations: [location(2, tags: ["Cafe"])])]
        let original = await service.snapshot(sources: sources, tags: tags, query: .init(), environment: environment)

        let reordered = await service.snapshot(sources: Array(sources.reversed()), tags: Array(tags.reversed()),
                                                query: .init(), environment: environment)
        let rebuilt = await service.lastRebuiltPlaceIDs
        let rendered = await service.lastRenderedPlaceIDs
        XCTAssertEqual(reordered, original)
        XCTAssertTrue(rebuilt.isEmpty)
        XCTAssertTrue(rendered.isEmpty)
    }

    func testCorruptFile_rebuildsFromSourceWithoutLosingPlaces() async throws {
        let url = try temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data("not a cache".utf8).write(to: url)
        let service = ReviewMapCacheService(fileURL: url)

        let snapshot = await service.snapshot(sources: sampleSources(), tags: tags, query: .init(), environment: environment)
        await service.flush()
        let rebuilt = await service.lastRebuiltPlaceIDs
        let loaded = await service.loadedFromDisk

        XCTAssertEqual(snapshot.places.count, 2)
        XCTAssertEqual(rebuilt, Set(snapshot.places.map(\.id)))
        XCTAssertFalse(loaded)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(contentsOf: url)))
    }

    func testUnsupportedSchema_rebuildsFromSource() async throws {
        let url = try temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = ReviewMapCacheService(fileURL: url)
        let original = await service.snapshot(sources: sampleSources(), tags: tags, query: .init(), environment: environment)
        await service.flush()
        var stored = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        stored["schemaVersion"] = Int.max
        try JSONSerialization.data(withJSONObject: stored).write(to: url)

        let reopened = ReviewMapCacheService(fileURL: url)
        let recovered = await reopened.snapshot(sources: sampleSources(), tags: tags, query: .init(), environment: environment)
        let loaded = await reopened.loadedFromDisk
        let rebuilt = await reopened.lastRebuiltPlaceIDs

        XCTAssertEqual(recovered, original)
        XCTAssertFalse(loaded)
        XCTAssertEqual(rebuilt, Set(original.places.map(\.id)))
    }

    func testCalendarAndLocaleChanged_rebuildsDateAndVisitInformation() async throws {
        let url = try temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = ReviewMapCacheService(fileURL: url)
        _ = await service.snapshot(sources: sampleSources(), tags: tags, query: .init(), environment: environment)
        await service.flush()
        var changedCalendar = calendar
        changedCalendar.timeZone = TimeZone(secondsFromGMT: -8 * 3_600)!
        let changedEnvironment = ReviewMapEnvironment(localeIdentifier: "ja_JP", calendar: changedCalendar,
                                                       visitCountFormat: "%lld回")

        let reopened = ReviewMapCacheService(fileURL: url)
        let updated = await reopened.snapshot(sources: sampleSources(), tags: tags, query: .init(), environment: changedEnvironment)
        let loaded = await reopened.loadedFromDisk
        let rebuilt = await reopened.lastRebuiltPlaceIDs

        XCTAssertFalse(loaded)
        XCTAssertEqual(rebuilt, Set(updated.places.map(\.id)))
        XCTAssertEqual(updated.places.first?.visits.first?.date, changedCalendar.startOfDay(for: date(month: 10, day: 6)))
    }

    func testSeparateCacheURLs_keepStoresIsolated() async throws {
        let firstURL = try temporaryCacheURL()
        let secondURL = try temporaryCacheURL()
        defer {
            try? FileManager.default.removeItem(at: firstURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: secondURL.deletingLastPathComponent())
        }
        let first = ReviewMapCacheService(fileURL: firstURL)
        let second = ReviewMapCacheService(fileURL: secondURL)
        _ = await first.snapshot(sources: [diary(1, day: 6, locations: [location(1, tags: ["Cafe"])])],
                                 tags: tags, query: .init(), environment: environment)
        _ = await second.snapshot(sources: [diary(2, day: 6, locations: [location(2, tags: ["Work"])])],
                                  tags: tags, query: .init(), environment: environment)
        await first.flush()
        await second.flush()

        let firstData = try Data(contentsOf: firstURL)
        let secondData = try Data(contentsOf: secondURL)
        XCTAssertNotEqual(firstData, secondData)
        let reopened = ReviewMapCacheService(fileURL: firstURL)
        let snapshot = await reopened.snapshot(sources: [diary(1, day: 6, locations: [location(1, tags: ["Cafe"])])],
                                               tags: tags, query: .init(), environment: environment)
        XCTAssertEqual(snapshot.places.map { $0.location.name }, ["Place 1"])
    }

    func testCancelledThenLatestRequest_flushKeepsLatestSnapshot() async throws {
        let url = try temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = ReviewMapCacheService(fileURL: url)
        let oldSources = sampleSources()
        let definitions = tags
        let displayEnvironment = environment
        let oldRequest = _Concurrency.Task {
            await service.snapshot(sources: oldSources, tags: definitions, query: .init(), environment: displayEnvironment)
        }
        oldRequest.cancel()
        _ = await oldRequest.value
        let latestSources = [diary(3, day: 6, locations: [location(3, tags: ["Work"])])]
        let latest = await service.snapshot(sources: latestSources, tags: tags, query: .init(), environment: environment)
        await service.flush()

        let reopened = ReviewMapCacheService(fileURL: url)
        let persisted = await reopened.snapshot(sources: latestSources, tags: tags, query: .init(), environment: environment)
        XCTAssertEqual(persisted, latest)
        XCTAssertEqual(persisted.places.map { $0.location.name }, ["Place 3"])
        let rebuilt = await reopened.lastRebuiltPlaceIDs
        XCTAssertTrue(rebuilt.isEmpty)
    }

    func testRapidEditsBeforeFlush_persistOnlyTheLatestPlaceData() async throws {
        let url = try temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = ReviewMapCacheService(fileURL: url)
        var sources = sampleSources()
        _ = await service.snapshot(sources: sources, tags: tags, query: .init(), environment: environment)
        sources[0].locations[0].photoPaths = ["first-edit.jpg"]
        _ = await service.snapshot(sources: sources, tags: tags, query: .init(), environment: environment)
        sources[0].locations[0].photoPaths = ["latest-edit.jpg"]
        let latest = await service.snapshot(sources: sources, tags: tags, query: .init(), environment: environment)
        await service.flush()

        let reopened = ReviewMapCacheService(fileURL: url)
        let restored = await reopened.snapshot(sources: sources, tags: tags, query: .init(), environment: environment)
        let rebuilt = await reopened.lastRebuiltPlaceIDs

        XCTAssertEqual(restored, latest)
        XCTAssertEqual(restored.places.first { $0.location.name == "Place 1" }?.visits.first?.photoPaths,
                       ["latest-edit.jpg"])
        XCTAssertTrue(rebuilt.isEmpty)
    }

    func testOlderRevisionWithDifferentQuery_usesCurrentSourcesAndPersistsLatestState() async throws {
        let url = try temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = ReviewMapCacheService(fileURL: url)
        let latestSources = [diary(3, day: 6, locations: [location(3, tags: ["Work"])])]
        var latestTags = tags
        latestTags[1].colorHex = "ABCDEF"
        _ = await service.snapshot(sources: latestSources, tags: latestTags, query: .init(),
                                   environment: environment, requestRevision: 20)
        let work = ReviewMapQuery(selectedFilters: ["Work"])

        let staleRequest = await service.snapshot(sources: sampleSources(), tags: tags, query: work,
                                                  environment: environment, requestRevision: 19)
        let rebuilt = await service.lastRebuiltPlaceIDs
        await service.flush()

        XCTAssertEqual(staleRequest.places.map { $0.location.name }, ["Place 3"])
        XCTAssertEqual(staleRequest.places.first?.compactColorHex, "ABCDEF")
        XCTAssertTrue(rebuilt.isEmpty)
        let reopened = ReviewMapCacheService(fileURL: url)
        let persisted = await reopened.snapshot(sources: latestSources, tags: latestTags,
                                                query: work, environment: environment)
        let reopenedRebuilt = await reopened.lastRebuiltPlaceIDs
        XCTAssertEqual(persisted, staleRequest)
        XCTAssertTrue(reopenedRebuilt.isEmpty)
    }

    func testOlderRevision_cannotRestoreOldEnvironmentOrColors() async {
        let service = ReviewMapCacheService()
        let latestSources = [diary(1, day: 6, locations: [location(1, tags: ["Cafe"])]),
                             diary(2, day: 5, locations: [location(1, tags: ["Cafe"])])]
        var latestTags = tags
        latestTags[0].colorHex = "AA1122"
        var oldCalendar = calendar
        oldCalendar.timeZone = TimeZone(secondsFromGMT: 9 * 3_600)!
        let oldEnvironment = ReviewMapEnvironment(localeIdentifier: "ja_JP", calendar: oldCalendar,
                                                   visitCountFormat: "%lld回")
        _ = await service.snapshot(sources: sampleSources(), tags: tags, query: .init(),
                                   environment: oldEnvironment, requestRevision: 19)
        let latest = await service.snapshot(sources: latestSources, tags: latestTags, query: .init(),
                                            environment: environment, requestRevision: 20)

        let staleRequest = await service.snapshot(sources: sampleSources(), tags: tags, query: .init(),
                                                  environment: oldEnvironment, requestRevision: 19)
        let rebuilt = await service.lastRebuiltPlaceIDs

        XCTAssertEqual(staleRequest, latest)
        XCTAssertEqual(staleRequest.places.first?.count, 2)
        XCTAssertEqual(staleRequest.places.first?.compactColorHex, "AA1122")
        XCTAssertTrue(rebuilt.isEmpty)
    }

    func testEveryWarmedQuery_isPatchedAndPersistsAfterMoveDeletionAndTagChange() async throws {
        let url = try temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = ReviewMapCacheService(fileURL: url)
        var sources = [diary(1, day: 6, locations: [location(1, tags: ["Cafe"]), location(2, tags: ["Work"])]),
                       diary(2, month: 9, day: 30, locations: [location(1, tags: ["Cafe"])]),
                       diary(3, day: 5, locations: [location(3, tags: [])])]
        let queries = [ReviewMapQuery(),
                       ReviewMapQuery(monthStart: date(month: 10, day: 1), monthEnd: date(month: 11, day: 1)),
                       ReviewMapQuery(selectedFilters: ["Cafe"]),
                       ReviewMapQuery(selectedFilters: ["Work", "__untagged__"])]
        for query in queries {
            _ = await service.snapshot(sources: sources, tags: tags, query: query, environment: environment)
        }
        // Keep the older visit to Place 1, move its newer visit, and delete Place 2.
        sources[0].locations[0].name = "Moved cafe"
        sources[0].locations[0].latitude += 0.02
        sources[0].locations.removeLast()
        var changedTags = tags
        changedTags[0].colorHex = "778899"
        changedTags[0].displayName = "Coffee time"
        _ = await service.snapshot(sources: sources, tags: changedTags, query: .init(), environment: environment)
        await service.flush()

        let reopened = ReviewMapCacheService(fileURL: url)
        let cold = ReviewMapCacheService()
        for query in queries {
            let persisted = await reopened.snapshot(sources: sources, tags: changedTags, query: query, environment: environment)
            let expected = await cold.snapshot(sources: sources, tags: changedTags, query: query, environment: environment)
            let rebuilt = await reopened.lastRebuiltPlaceIDs
            let rendered = await reopened.lastRenderedPlaceIDs
            XCTAssertEqual(persisted, expected)
            XCTAssertTrue(rebuilt.isEmpty)
            XCTAssertTrue(rendered.isEmpty)
        }
    }

    private var tags: [ReviewMapTagSource] {
        [ReviewMapTagSource(id: identifier(101), name: "Cafe", displayName: "Cafe", sortOrder: 0, colorHex: "D87568"),
         ReviewMapTagSource(id: identifier(102), name: "Work", displayName: "Work", sortOrder: 1, colorHex: "688EA8")]
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var environment: ReviewMapEnvironment {
        ReviewMapEnvironment(localeIdentifier: "en_US", calendar: calendar, visitCountFormat: "%lld visits")
    }

    private func sampleSources() -> [ReviewMapDiarySource] {
        [diary(1, day: 6, locations: [location(1, tags: ["Cafe"]), location(2, tags: ["Work"])])]
    }

    private func diary(_ index: Int, month: Int = 10, day: Int,
                       locations: [ReviewMapLocationSource]) -> ReviewMapDiarySource {
        ReviewMapDiarySource(id: identifier(index), date: date(month: month, day: day), locations: locations)
    }

    private func location(_ index: Int, tags: [String]) -> ReviewMapLocationSource {
        ReviewMapLocationSource(id: identifier(10_000 + index), name: "Place \(index)",
                                latitude: 35 + Double(index) * 0.0002, longitude: 139,
                                visitTags: tags)
    }

    private func date(month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    private func identifier(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "AB000000-0000-4000-8000-%012d", index))!
    }

    private func temporaryCacheURL() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ReviewMapCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("review-map.json")
    }
}
