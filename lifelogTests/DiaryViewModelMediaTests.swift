import XCTest
@testable import lifelify

@MainActor
final class DiaryViewModelMediaTests: XCTestCase {
    nonisolated deinit {}

    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    func testLegacyLocationMedia_appearsInDiaryOnceWithStableOrderAndPaths() {
        let location = makeLocation(paths: ["linked.mov", "diary.jpg", "legacy.jpg"])
        let original = DiaryEntry(date: date, text: "保存済みの日記", locations: [location],
                                  photoPaths: ["diary.jpg"],
                                  locationPhotoPaths: ["legacy.jpg", "legacy.jpg"],
                                  favoritePhotoPath: "diary.jpg")

        let normalized = AppDataStore.normalizeDiaryEntries([original])[0]

        XCTAssertEqual(normalized.photoPaths, ["diary.jpg", "legacy.jpg", "linked.mov"])
        XCTAssertEqual(normalized.locations, original.locations)
        XCTAssertEqual(normalized.text, original.text)
        XCTAssertEqual(normalized.favoritePhotoPath, original.favoritePhotoPath)
        XCTAssertEqual(AppDataStore.normalizeDiaryEntries([normalized])[0], normalized)
    }

    func testLegacyStoreLoad_includesPlaceOnlyMediaBeforeOpeningDiary() {
        let persistence = PersistenceController(inMemory: true)
        let location = makeLocation(paths: ["place-video.mp4"])
        let original = DiaryEntry(date: date, text: "", locations: [location],
                                  locationPhotoPaths: ["place-photo.jpg"])
        persistence.container.mainContext.insert(SDDiaryEntry(domain: original))
        let store = AppDataStore(container: persistence.container, startsBackgroundServices: false)

        XCTAssertEqual(store.entry(for: date)?.photoPaths, ["place-photo.jpg", "place-video.mp4"])
    }

    func testDiaryImport_moreThanTenAttachmentsAppearBeforeNextItemLoads() async {
        let store = makeStore()
        let viewModel = DiaryViewModel(store: store, date: date)
        let prefix = UUID().uuidString
        let items = (0..<17).map { index in
            DiaryPhotoImporter.Item(assetIdentifier: nil, loadData: {
                XCTAssertEqual(viewModel.entry.photoPaths.count, index,
                               "Each finished attachment must publish before the next load")
                return Data([UInt8(index)])
            })
        }

        let summary = await viewModel.importPhotoItems(items, save: { data, _ in
            "\(prefix)-\(data[0]).jpg"
        })

        XCTAssertEqual(summary.addedCount, 17)
        XCTAssertFalse(summary.hasIssues)
        XCTAssertEqual(viewModel.entry.photoPaths.count, 17)
        XCTAssertEqual(store.entry(for: date)?.photoPaths, viewModel.entry.photoPaths)
    }

    func testPlaceImport_publishesDiaryAndPlaceLinksForEachCompletedItem() async {
        let store = makeStore()
        let location = makeLocation()
        store.upsert(entry: DiaryEntry(date: date, text: "", locations: [location]))
        let viewModel = DiaryViewModel(store: store, date: date)
        let paths = [UUID().uuidString + ".jpg", UUID().uuidString + ".mov"]
        let items = paths.enumerated().map { index, _ in
            DiaryPhotoImporter.Item(assetIdentifier: nil, loadData: {
                XCTAssertEqual(viewModel.entry.photoPaths, Array(paths.prefix(index)))
                XCTAssertEqual(viewModel.entry.locations[0].photoPaths, Array(paths.prefix(index)))
                return Data([UInt8(index)])
            })
        }

        let summary = await viewModel.importPhotoItems(items, forLocation: location.id,
                                                     isLocationImport: true, save: { data, _ in
            paths[Int(data[0])]
        })

        XCTAssertEqual(summary.addedPaths, paths)
        XCTAssertEqual(viewModel.entry.photoPaths, paths)
        XCTAssertEqual(viewModel.entry.locationPhotoPaths, paths)
        XCTAssertEqual(viewModel.entry.locations[0].photoPaths, paths)
        XCTAssertEqual(store.entry(for: date)?.locations[0].photoPaths, paths)
    }

    func testImportWhileChangingDays_keepsMediaAndLinksOnOriginalDay() async {
        let store = makeStore()
        let location = makeLocation()
        store.upsert(entry: DiaryEntry(date: date, text: "", locations: [location]))
        let viewModel = DiaryViewModel(store: store, date: date)
        let originalID = viewModel.entry.id
        let nextDate = date.addingTimeInterval(86_400)
        let paths = [UUID().uuidString + ".jpg", UUID().uuidString + ".jpg"]
        let items = [
            DiaryPhotoImporter.Item(assetIdentifier: nil, loadData: { Data([0]) }),
            DiaryPhotoImporter.Item(assetIdentifier: nil, loadData: {
                viewModel.update(text: "入力途中の本文")
                viewModel.loadEntry(for: nextDate)
                return Data([1])
            })
        ]

        _ = await viewModel.importPhotoItems(items, forLocation: location.id,
                                            isLocationImport: true, save: { data, _ in
            paths[Int(data[0])]
        })

        XCTAssertNotEqual(viewModel.entry.id, originalID)
        XCTAssertTrue(viewModel.entry.photoPaths.isEmpty)
        XCTAssertEqual(store.entry(for: date)?.photoPaths, paths)
        XCTAssertEqual(store.entry(for: date)?.locations[0].photoPaths, paths)
        XCTAssertEqual(store.entry(for: date)?.text, "入力途中の本文")
    }

    func testDiaryDeletion_removesSameDayPlaceLinksAndPreservesOtherDayReference() {
        let store = makeStore()
        let path = UUID().uuidString + ".mov"
        let location = makeLocation(paths: [path])
        let original = DiaryEntry(date: date, text: "", locations: [location],
                                  photoPaths: [path], locationPhotoPaths: [path],
                                  favoritePhotoPath: path)
        let otherDate = date.addingTimeInterval(86_400)
        store.upsert(entry: original)
        store.upsert(entry: DiaryEntry(date: otherDate, text: "", photoPaths: [path]))
        let viewModel = DiaryViewModel(store: store, date: date)

        viewModel.deletePhoto(at: IndexSet(integer: 0))

        XCTAssertTrue(viewModel.entry.photoPaths.isEmpty)
        XCTAssertTrue(viewModel.entry.locationPhotoPaths.isEmpty)
        XCTAssertTrue(viewModel.entry.locations[0].photoPaths.isEmpty)
        XCTAssertNil(viewModel.entry.favoritePhotoPath)
        XCTAssertEqual(store.entry(for: otherDate)?.photoPaths, [path])
        XCTAssertFalse(PhotoSyncManifest.shared.isDeleted(path: path))
        XCTAssertTrue(AppDataStore.normalizeDiaryEntries([viewModel.entry])[0].photoPaths.isEmpty)
    }

    func testPlaceUnlink_keepsDiaryAttachmentAndExistingDiaryToPlaceFlow() async {
        let store = makeStore()
        let path = UUID().uuidString + ".mp4"
        let location = makeLocation(paths: [path])
        store.upsert(entry: DiaryEntry(date: date, text: "", locations: [location],
                                      photoPaths: [path], locationPhotoPaths: [path]))
        let viewModel = DiaryViewModel(store: store, date: date)

        viewModel.updatePhotoLinks(forLocation: location.id, selectedPaths: [])
        viewModel.deleteLocationPhoto(path: path)

        XCTAssertEqual(viewModel.entry.photoPaths, [path])
        XCTAssertTrue(viewModel.entry.locations[0].photoPaths.isEmpty)
        XCTAssertFalse(PhotoSyncManifest.shared.isDeleted(path: path))

        await viewModel.updateLocationLinks(forPhoto: path, selectedLocationIDs: [location.id])

        XCTAssertEqual(viewModel.entry.locations[0].photoPaths, [path])
        XCTAssertEqual(viewModel.entry.photoPaths, [path])
    }

    func testConcurrentImportMerge_keepsOtherEditorsAddedMediaAndPlaceLinks() {
        let location = makeLocation(paths: ["old.jpg"])
        let baseline = DiaryEntry(date: date, text: "", locations: [location],
                                  photoPaths: ["old.jpg"], locationPhotoPaths: ["old.jpg"])
        var draft = baseline
        draft.photoPaths.append("import.mov")
        draft.locationPhotoPaths.append("import.mov")
        draft.locations[0].photoPaths.append("import.mov")
        var current = baseline
        current.photoPaths.append("other.jpg")
        current.locationPhotoPaths.append("other.jpg")
        current.locations[0].photoPaths.append("other.jpg")

        let merged = DiaryDraftMerger.merge(draft: draft, baseline: baseline, current: current)

        XCTAssertEqual(merged.photoPaths, ["old.jpg", "other.jpg", "import.mov"])
        XCTAssertEqual(merged.locationPhotoPaths, merged.photoPaths)
        XCTAssertEqual(merged.locations[0].photoPaths, merged.photoPaths)
    }

    func testConcurrentImportMerge_appliesDeletionsWithoutRevivingConcurrentUnlinks() {
        let location = makeLocation(paths: ["remove.jpg", "unlinked.jpg"])
        let baseline = DiaryEntry(date: date, text: "", locations: [location],
                                  photoPaths: ["remove.jpg", "unlinked.jpg"])
        var draft = baseline
        draft.photoPaths = ["unlinked.jpg", "import.mov"]
        draft.locations[0].photoPaths = ["unlinked.jpg", "import.mov"]
        var current = baseline
        current.photoPaths.append("other.jpg")
        current.locations[0].photoPaths = ["remove.jpg", "other.jpg"]

        let merged = DiaryDraftMerger.merge(draft: draft, baseline: baseline, current: current)

        XCTAssertEqual(merged.photoPaths, ["unlinked.jpg", "other.jpg", "import.mov"])
        XCTAssertEqual(merged.locations[0].photoPaths, ["other.jpg", "import.mov"])
    }

    func testLocationLinkLookup_concurrentDiaryDeletionDoesNotRestoreAttachment() async {
        let store = makeStore()
        let path = UUID().uuidString + ".mov"
        let location = makeLocation()
        let original = DiaryEntry(date: date, text: "保存済み本文", locations: [location], photoPaths: [path])
        store.upsert(entry: original)
        let viewModel = DiaryViewModel(store: store, date: date)
        viewModel.update(text: "入力途中の本文")
        var resolved = false

        await viewModel.updateLocationLinks(forPhoto: path, selectedLocationIDs: [location.id],
                                           resolveLegacyIdentities: { paths in
            XCTAssertEqual(paths, [path])
            resolved = true
            var deleted = original
            deleted.photoPaths = []
            store.upsert(entry: deleted)
            return [path: "digest:removed-video"]
        })
        viewModel.flushPendingTextSave()

        XCTAssertTrue(resolved)
        XCTAssertTrue(viewModel.entry.photoPaths.isEmpty)
        XCTAssertTrue(viewModel.entry.locations[0].photoPaths.isEmpty)
        XCTAssertTrue(store.entry(for: date)?.photoPaths.isEmpty == true)
        XCTAssertTrue(store.entry(for: date)?.locations[0].photoPaths.isEmpty == true)
        XCTAssertEqual(viewModel.textDraft, "入力途中の本文")
    }

    func testDirectPlaceLink_badgesAndSelectionResolveWithoutLegacyEquivalence() async {
        let store = makeStore()
        let path = UUID().uuidString + ".mov"
        let location = makeLocation(paths: [path])
        store.upsert(entry: DiaryEntry(date: date, text: "", locations: [location], photoPaths: [path]))
        let viewModel = DiaryViewModel(store: store, date: date)

        let linkedPaths = await viewModel.linkedDiaryPhotoPaths()
        let linkedLocations = await viewModel.linkedLocationIDs(forPhoto: path)

        XCTAssertEqual(linkedPaths, [path])
        XCTAssertEqual(linkedLocations, [location.id])
    }

    private func makeStore() -> AppDataStore {
        AppDataStore(container: PersistenceController(inMemory: true).container,
                     startsBackgroundServices: false)
    }

    private func makeLocation(paths: [String] = []) -> DiaryLocation {
        DiaryLocation(name: "保存した場所", address: nil, latitude: 35, longitude: 139,
                      mapItemURL: nil, photoPaths: paths)
    }
}
