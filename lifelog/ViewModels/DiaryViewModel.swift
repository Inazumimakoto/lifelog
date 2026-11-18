//
//  DiaryViewModel.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import CoreLocation
import Combine
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DiaryViewModel: ObservableObject {

    typealias PhotoImportSummary = DiaryPhotoImporter.Summary
    
    /// テキスト入力のデバウンス時間（秒）
    private static let textDebounceInterval: TimeInterval = 0.5
    /// UI操作系（気分/体調）のデバウンス時間（秒）
    private static let metadataDebounceInterval: TimeInterval = 0.25

    @Published private(set) var entry: DiaryEntry

    private(set) var store: AppDataStore
    var textDraft: String {
        pendingText
    }
    
    /// テキスト保存用のデバウンスタスク
    private var textPersistTask: _Concurrency.Task<Void, Never>?
    /// 気分/体調保存用のデバウンスタスク
    private var metadataPersistTask: _Concurrency.Task<Void, Never>?
    /// 画面入力の下書き本文
    private var pendingText: String = ""
    private var savedEntry: DiaryEntry
    private var storeObservation: AnyCancellable?
    nonisolated deinit {}

    init(store: AppDataStore, date: Date) {
        self.store = store
        let existingEntry = store.entry(for: date)
        let normalized = existingEntry ?? DiaryEntry(date: date, text: "")
        self.entry = normalized; self.savedEntry = normalized; self.pendingText = normalized.text
        storeObservation = store.$diaryEntries.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.receiveStoreChanges() }

        cleanupMissingPhotos()
    }
    
    /// 別の日付のエントリを読み込む
    func loadEntry(for date: Date) {
        // 前のエントリの保存を確実に完了させる
        flushPendingTextSave()
        
        let existingEntry = store.entry(for: date)
        let normalized = existingEntry ?? DiaryEntry(date: date, text: "")
        self.entry = normalized; self.savedEntry = normalized; self.pendingText = normalized.text
        cleanupMissingPhotos()
    }

    func update(text: String) {
        guard pendingText != text else { return }
        pendingText = text
        // テキスト入力はデバウンスで遅延保存
        debouncedPersistText()
    }

    func update(mood: MoodLevel?) {
        entry.mood = mood
        debouncedPersistMetadata()
    }

    func update(condition: Int?) {
        entry.conditionScore = condition
        debouncedPersistMetadata()
    }

    func update(locationName: String?, coordinate: CLLocationCoordinate2D?) {
        entry.locationName = locationName
        entry.latitude = coordinate?.latitude
        entry.longitude = coordinate?.longitude
        if let locationName, let coordinate {
            if entry.locations.isEmpty {
                entry.locations = [
                    DiaryLocation(name: locationName,
                                  address: nil,
                                  latitude: coordinate.latitude,
                                  longitude: coordinate.longitude,
                                  mapItemURL: nil,
                                  photoPaths: [])
                ]
            } else {
                entry.locations[0].name = locationName
                entry.locations[0].latitude = coordinate.latitude
                entry.locations[0].longitude = coordinate.longitude
            }
        } else if entry.locations.isEmpty == false {
            entry.locations = []
        }
        persist()
    }

    @discardableResult
    func addLocation(_ location: DiaryLocation) -> UUID? {
        guard entry.locations.contains(where: { Self.isSameLocation($0, location) }) == false else { return nil }
        entry.locations.append(location)
        syncPrimaryLocation()
        persist()
        return location.id
    }

    func removeLocation(id: UUID) {
        entry.locations.removeAll { $0.id == id }
        syncPrimaryLocation()
        persist()
    }
    
    func visitTags(for locationID: UUID) -> [String] {
        guard let location = entry.locations.first(where: { $0.id == locationID }) else { return [] }
        return location.visitTags
    }
    
    func updateVisitTags(for locationID: UUID, tags: [String]) {
        guard let index = entry.locations.firstIndex(where: { $0.id == locationID }) else { return }
        let normalized = DiaryVisitTagNormalizer.normalize(tags, limit: AppDataStore.maxLocationVisitTagsPerVisit)
        guard entry.locations[index].visitTags != normalized else { return }
        entry.locations[index].visitTags = normalized
        persist()
    }
    
    func applyVisitTagRename(oldName: String, newName: String) {
        var didChange = false
        let oldKey = DiaryVisitTagNormalizer.key(for: oldName)
        for index in entry.locations.indices {
            var tags = entry.locations[index].visitTags
            var locationChanged = false
            for tagIndex in tags.indices where DiaryVisitTagNormalizer.key(for: tags[tagIndex]) == oldKey {
                tags[tagIndex] = newName
                locationChanged = true
            }
            if locationChanged {
                entry.locations[index].visitTags = DiaryVisitTagNormalizer.normalize(tags, limit: AppDataStore.maxLocationVisitTagsPerVisit)
                didChange = true
            }
        }
        if didChange {
            persist()
        }
    }
    
    func applyVisitTagDeletion(name: String) {
        var didChange = false
        let deletedKey = DiaryVisitTagNormalizer.key(for: name)
        for index in entry.locations.indices {
            let before = entry.locations[index].visitTags
            let filtered = before.filter { DiaryVisitTagNormalizer.key(for: $0) != deletedKey }
            guard filtered.count != before.count else { continue }
            entry.locations[index].visitTags = filtered
            didChange = true
        }
        if didChange {
            persist()
        }
    }

    func updatePhotoLinks(forLocation locationID: UUID, selectedPaths: [String]) {
        guard let index = entry.locations.firstIndex(where: { $0.id == locationID }) else { return }
        let ordered = orderedPhotoPaths(from: Set(selectedPaths))
        entry.locations[index].photoPaths = ordered
        persist()
    }

    /// 既存リンクを維持したまま、指定写真だけを場所へ追加リンクする。
    /// インポート直後の追記用途（上書きによる意図しない解除を避ける）。
    func addPhotoLinks(forLocation locationID: UUID, paths: [String]) {
        guard let index = entry.locations.firstIndex(where: { $0.id == locationID }) else { return }
        guard paths.isEmpty == false else { return }
        let merged = Set(entry.locations[index].photoPaths).union(paths)
        let ordered = orderedPhotoPaths(from: merged)
        guard ordered != entry.locations[index].photoPaths else { return }
        entry.locations[index].photoPaths = ordered
        persist()
    }

    func updateLocationLinks(
        forPhoto path: String,
        selectedLocationIDs: [UUID],
        resolveLegacyIdentities: @MainActor ([String]) async -> [String: String] = {
            await PhotoStorage.identityMap(for: $0)
        }
    ) async {
        guard entry.photoPaths.contains(path) else { return }
        let targetID = entry.id
        let isVideo = PhotoStorage.isVideo(at: path)
        let paths = Array(Set(entry.locations.flatMap(\.photoPaths)).union([path]))
            .filter { PhotoStorage.isVideo(at: $0) == isVideo }
        let identifiers = PhotoStorage.assetIdentifierMap(for: paths)
        let identityByPath: [String: String]
        if identifiers[path] != nil {
            // Known Photos identities never need to read a movie's bytes.
            identityByPath = identifiers.mapValues { "asset:" + $0 }
        } else {
            identityByPath = await resolveLegacyIdentities(paths.filter { identifiers[$0] == nil })
        }
        guard !_Concurrency.Task.isCancelled else { return }
        var target: DiaryEntry
        if entry.id == targetID {
            // Include concurrent store removals even while this editor has a
            // pending text/media draft and therefore defers store publication.
            let current = store.diaryEntries.first { $0.id == targetID } ?? savedEntry
            target = DiaryDraftMerger.merge(draft: entry, baseline: savedEntry, current: current)
        } else if let stored = store.diaryEntries.first(where: { $0.id == targetID }) {
            target = stored
        } else {
            return
        }
        guard target.photoPaths.contains(path) else {
            if entry.id == targetID { entry = target }
            return
        }
        let targetIDs = Set(selectedLocationIDs)
        let selectedIdentity = identityByPath[path]
        var didChange = false
        for index in target.locations.indices {
            let locationID = target.locations[index].id
            let contains = target.locations[index].photoPaths.contains(path)
            let hasEquivalent = selectedIdentity != nil && target.locations[index].photoPaths.contains {
                identityByPath[$0] == selectedIdentity
            }
            if targetIDs.contains(locationID) {
                if !contains && !hasEquivalent {
                    target.locations[index].photoPaths.append(path)
                    didChange = true
                }
            } else if contains || hasEquivalent {
                target.locations[index].photoPaths.removeAll {
                    $0 == path || (selectedIdentity != nil && identityByPath[$0] == selectedIdentity)
                }
                didChange = true
            }
        }
        guard didChange else { return }
        let orderedPaths = DiaryMediaCollection.allPaths(in: target)
        for index in target.locations.indices {
            let selected = Set(target.locations[index].photoPaths)
            target.locations[index].photoPaths = orderedPaths.filter { selected.contains($0) }
        }
        if entry.id == targetID {
            entry = target
            persist()
        } else {
            store.upsert(entry: target)
        }
    }

    func linkedDiaryPhotoPaths() async -> Set<String> {
        let photoPaths = entry.photoPaths
        let directLinkedPaths = Set(entry.locations.flatMap(\.photoPaths))
        guard !directLinkedPaths.isEmpty else { return [] }
        let identifiers = PhotoStorage.assetIdentifierMap(for: Array(Set(photoPaths).union(directLinkedPaths)))
        let linkedAssetIDs = Set(directLinkedPaths.compactMap { identifiers[$0] })
        var linkedPaths = Set(photoPaths.filter {
            directLinkedPaths.contains($0) || identifiers[$0].map { linkedAssetIDs.contains($0) } == true
        })
        let legacyLinked = directLinkedPaths.filter { identifiers[$0] == nil }
        let legacyKinds = Set(legacyLinked.map { PhotoStorage.isVideo(at: $0) })
        let legacyUnlinked = photoPaths.filter {
            !linkedPaths.contains($0) && identifiers[$0] == nil
                && legacyKinds.contains(PhotoStorage.isVideo(at: $0))
        }
        guard !legacyLinked.isEmpty, !legacyUnlinked.isEmpty else { return linkedPaths }
        let candidateKinds = Set(legacyUnlinked.map { PhotoStorage.isVideo(at: $0) })
        let comparableLinked = legacyLinked.filter { candidateKinds.contains(PhotoStorage.isVideo(at: $0)) }
        let identityByPath = await PhotoStorage.identityMap(for: legacyUnlinked + Array(comparableLinked))
        let linkedIdentities = Set(comparableLinked.compactMap { identityByPath[$0] })
        for path in legacyUnlinked {
            if let identity = identityByPath[path], linkedIdentities.contains(identity) {
                linkedPaths.insert(path)
            }
        }
        return linkedPaths
    }

    func linkedLocationIDs(forPhoto path: String) async -> Set<UUID> {
        let locations = entry.locations
        let directMatches = Set(locations.filter { $0.photoPaths.contains(path) }.map(\.id))
        let isVideo = PhotoStorage.isVideo(at: path)
        let locationPaths = Set(locations.flatMap(\.photoPaths))
            .filter { PhotoStorage.isVideo(at: $0) == isVideo }
        let identifiers = PhotoStorage.assetIdentifierMap(for: Array(locationPaths.union([path])))
        if let assetIdentifier = identifiers[path] {
            return directMatches.union(locations.filter { location in
                location.photoPaths.contains { identifiers[$0] == assetIdentifier }
            }.map(\.id))
        }
        let legacyCandidates = locationPaths.filter { $0 != path && identifiers[$0] == nil }
        guard !legacyCandidates.isEmpty else { return directMatches }
        let identityByPath = await PhotoStorage.identityMap(for: Array(legacyCandidates) + [path])
        guard let targetIdentity = identityByPath[path] else { return directMatches }
        return directMatches.union(locations.filter { location in
            location.photoPaths.contains { identityByPath[$0] == targetIdentity }
        }.map(\.id))
    }

    func recentLocationCoordinate() -> CLLocationCoordinate2D? {
        let sorted = store.diaryEntries.sorted { $0.date > $1.date }
        for entry in sorted {
            if let location = entry.locations.first {
                return location.coordinate
            }
            if let lat = entry.latitude, let lon = entry.longitude {
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        }
        return nil
    }

    func addPhoto(data: Data) {
        guard let path = try? PhotoStorage.save(data: data) else { return }
        entry.photoPaths.append(path)
        persist()
    }

    func addLocationPhoto(data: Data) {
        guard let path = try? PhotoStorage.save(data: data) else { return }
        entry.locationPhotoPaths.append(path)
        entry.photoPaths.append(path)
        persist()
    }

    func importPhotos(from items: [PhotosPickerItem]) async -> PhotoImportSummary {
        await importPhotoItems(photoImportItems(from: items))
    }

    func importLocationPhotos(from items: [PhotosPickerItem],
                              forLocation locationID: UUID? = nil) async -> PhotoImportSummary {
        await importPhotoItems(photoImportItems(from: items), forLocation: locationID, isLocationImport: true)
    }

    /// Publish each finished attachment immediately. Persist the visible day's
    /// batch once, instead of rebuilding the journal and saving SwiftData for
    /// every selection. Changing days/closing the editor also flushes the draft.
    /// See docs/requirements.md §4.4.
    func importPhotoItems(
        _ items: [DiaryPhotoImporter.Item],
        forLocation locationID: UUID? = nil,
        isLocationImport: Bool = false,
        save: @MainActor (Data, String?) async throws -> String = {
            try await PhotoStorage.saveAsync(data: $0, sourceAssetIdentifier: $1)
        }
    ) async -> PhotoImportSummary {
        guard !items.isEmpty else { return PhotoImportSummary() }
        let targetID = entry.id
        let targetDate = entry.date
        var identityIndexes: [Bool: (paths: [String], index: PhotoIdentityIndex)] = [:]

        func targetEntry() -> DiaryEntry? {
            entry.id == targetID ? entry : store.diaryEntries.first { $0.id == targetID }
        }

        func matchingIndex(for identifier: String?, isVideo: Bool) async -> PhotoIdentityIndex {
            var paths = targetEntry().map { DiaryMediaCollection.allPaths(in: $0) } ?? []
            paths.removeAll { PhotoStorage.isVideo(at: $0) != isVideo }
            if let identifier, !identifier.isEmpty {
                // Stable Photos identities already ruled out every known
                // different asset. Only legacy attachments without that identity
                // need byte/visual matching; never hash a newly imported movie
                // again just to append the next picker selection.
                let identifiers = PhotoStorage.assetIdentifierMap(for: paths)
                paths.removeAll { identifiers[$0] != nil }
            }
            if let cached = identityIndexes[isVideo], cached.paths == paths { return cached.index }
            let index = await PhotoStorage.identityIndex(for: paths)
            identityIndexes[isVideo] = (paths, index)
            return index
        }

        let summary = await DiaryPhotoImporter.importPhotos(
            from: items,
            alreadyContains: { path in
                guard let target = targetEntry() else { return false }
                if isLocationImport {
                    if let locationID {
                        return target.locations.first { $0.id == locationID }?.photoPaths.contains(path) == true
                    }
                    return target.locationPhotoPaths.contains(path)
                }
                return target.photoPaths.contains(path)
            },
            matchingAssetPath: { identifier in
                let paths = targetEntry().map { DiaryMediaCollection.allPaths(in: $0) } ?? []
                return PhotoStorage.assetIdentifierIndex(for: paths)[identifier]?.first
            },
            matchingPath: { identifier, data in
                await PhotoStorage.matchingPhotoPath(assetIdentifier: identifier, data: data,
                                                    in: matchingIndex(for: identifier, isVideo: false))
            },
            matchingVideoPath: { identifier, url in
                await PhotoStorage.matchingVideoPath(assetIdentifier: identifier, fileURL: url,
                                                    in: matchingIndex(for: identifier, isVideo: true))
            },
            save: save,
            onAdded: { path in
                self.appendImportedPhoto(path, entryID: targetID, date: targetDate,
                                         locationID: locationID, isLocationImport: isLocationImport)
            }
        )
        if entry.id == targetID { persist() }
        return summary
    }

    private func photoImportItems(from items: [PhotosPickerItem]) -> [DiaryPhotoImporter.Item] {
        items.map { item in
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                return DiaryPhotoImporter.Item.video(assetIdentifier: item.itemIdentifier, load: {
                    try await item.loadTransferable(type: ImportedDiaryVideo.self)
                })
            }
            return DiaryPhotoImporter.Item(assetIdentifier: item.itemIdentifier) {
                try await item.loadTransferable(type: Data.self)
            }
        }
    }

    private func appendImportedPhoto(_ path: String, entryID: UUID, date: Date,
                                     locationID: UUID?, isLocationImport: Bool) {
        func append(to target: inout DiaryEntry) {
            if !target.photoPaths.contains(path) { target.photoPaths.append(path) }
            if isLocationImport && !target.locationPhotoPaths.contains(path) {
                target.locationPhotoPaths.append(path)
            }
            if let locationID, let index = target.locations.firstIndex(where: { $0.id == locationID }),
               !target.locations[index].photoPaths.contains(path) {
                target.locations[index].photoPaths.append(path)
            }
        }
        if entry.id == entryID {
            append(to: &entry)
        } else {
            var target = store.diaryEntries.first { $0.id == entryID }
                ?? DiaryEntry(id: entryID, date: date, text: "")
            append(to: &target)
            store.upsert(entry: target)
        }
    }

    func deletePhoto(at offsets: IndexSet) {
        let sortedOffsets = offsets.sorted(by: >)
        for index in sortedOffsets {
            guard entry.photoPaths.indices.contains(index) else { continue }
            let previous = entry
            let path = entry.photoPaths[index]
            if entry.favoritePhotoPath == path {
                entry.favoritePhotoPath = nil
            }
            entry.photoPaths.remove(at: index)
            entry.locationPhotoPaths.removeAll { $0 == path }
            removePhotoLinks(for: path)
            if !removePhotoAssetIfUnreferenced(path) { entry = previous }
        }
        persist()
    }

    func deleteLocationPhoto(at offsets: IndexSet) {
        let sortedOffsets = offsets.sorted(by: >)
        for index in sortedOffsets {
            guard entry.locationPhotoPaths.indices.contains(index) else { continue }
            let previous = entry
            let path = entry.locationPhotoPaths[index]
            entry.locationPhotoPaths.remove(at: index)
            if !removePhotoAssetIfUnreferenced(path) { entry = previous }
        }
        persist()
    }

    func deleteLocationPhoto(path: String) {
        guard let index = entry.locationPhotoPaths.firstIndex(of: path) else { return }
        deleteLocationPhoto(at: IndexSet(integer: index))
    }

    func setFavoritePhoto(at index: Int) {
        guard entry.photoPaths.indices.contains(index) else { return }
        let path = entry.photoPaths[index]
        if entry.favoritePhotoPath == path {
            entry.favoritePhotoPath = nil
        } else {
            entry.favoritePhotoPath = path
        }
        persist()
    }

    func cleanupMissingPhotos() {
        let previous = entry
        // Missing originals may be offloaded or awaiting restoration. Only an
        // explicit durable deletion removes a shared attachment from the diary.
        let keptPaths = Set(DiaryMediaCollection.allPaths(in: entry).filter {
            !PhotoSyncManifest.shared.isDeleted(path: $0)
        })
        entry.photoPaths.removeAll { !keptPaths.contains($0) }
        entry.locationPhotoPaths.removeAll { !keptPaths.contains($0) }
        pruneLocationPhotoLinks(availablePaths: keptPaths)
        entry = DiaryMediaCollection.normalized(entry)
        if let favorite = entry.favoritePhotoPath, !entry.photoPaths.contains(favorite) {
            entry.favoritePhotoPath = nil
        }
        if previous != entry { persist() }
    }

    private func orderedPhotoPaths(from selection: Set<String>) -> [String] {
        allPhotoPathsInOrder.filter { selection.contains($0) }
    }

    private var allPhotoPathsInOrder: [String] {
        DiaryMediaCollection.allPaths(in: entry)
    }

    private func removePhotoLinks(for path: String) {
        for index in entry.locations.indices {
            let original = entry.locations[index].photoPaths
            let filtered = original.filter { $0 != path }
            if filtered.count != original.count {
                entry.locations[index].photoPaths = filtered
            }
        }
    }

    @discardableResult
    private func removePhotoAssetIfUnreferenced(_ path: String) -> Bool {
        guard !entry.photoPaths.contains(path), !entry.locationPhotoPaths.contains(path) else { return true }
        let referencedElsewhere = store.diaryEntries.contains { other in
            other.id != entry.id && (other.photoPaths.contains(path) || other.locationPhotoPaths.contains(path)
                || other.locations.contains { $0.photoPaths.contains(path) })
        }
        if !referencedElsewhere, !PhotoStorage.delete(at: path) { return false }
        removePhotoLinks(for: path)
        return true
    }

    private func pruneLocationPhotoLinks(availablePaths: Set<String>) {
        for index in entry.locations.indices {
            let original = entry.locations[index].photoPaths
            let filtered = original.filter { availablePaths.contains($0) }
            if filtered.count != original.count {
                entry.locations[index].photoPaths = filtered
            }
        }
    }

    private func syncPrimaryLocation() {
        if let first = entry.locations.first {
            entry.locationName = first.name
            entry.latitude = first.latitude
            entry.longitude = first.longitude
        } else {
            entry.locationName = nil
            entry.latitude = nil
            entry.longitude = nil
        }
    }

    private static func isSameLocation(_ lhs: DiaryLocation, _ rhs: DiaryLocation) -> Bool {
        locationIdentity(for: lhs) == locationIdentity(for: rhs)
    }

    private static func locationIdentity(for location: DiaryLocation) -> String {
        if let mapItemURL = location.mapItemURL, mapItemURL.isEmpty == false {
            return "mapitem:\(mapItemURL)"
        }
        let lat = (location.latitude * 10_000).rounded() / 10_000
        let lon = (location.longitude * 10_000).rounded() / 10_000
        return "coord:\(lat),\(lon)"
    }
    
    // MARK: - Debounce Methods
    
    /// テキスト保存をデバウンスで遅延実行
    private func debouncedPersistText() {
        // 既存のタスクをキャンセル
        textPersistTask?.cancel()
        
        // 新しいタスクを開始
        textPersistTask = _Concurrency.Task { [weak self] in
            do {
                // 指定時間待機
                try await _Concurrency.Task.sleep(nanoseconds: UInt64(Self.textDebounceInterval * 1_000_000_000))
                
                // キャンセルされていなければ保存
                guard !_Concurrency.Task.isCancelled else { return }
                await self?.persistTextDraft()
            } catch {
                // Task.sleep がキャンセルされた場合（正常動作）
            }
        }
    }
    
    /// 保留中のテキスト保存を即座に実行（画面を閉じる前に呼び出す）
    func flushPendingTextSave() {
        textPersistTask?.cancel()
        textPersistTask = nil
        metadataPersistTask?.cancel(); metadataPersistTask = nil
        persist()
    }

    private func persist() {
        var draft = entry; draft.text = pendingText
        guard draft != savedEntry else {
            receiveStoreChanges(); return
        }
        let current = store.diaryEntries.first { $0.id == draft.id } ?? savedEntry
        let merged = DiaryDraftMerger.merge(draft: draft, baseline: savedEntry, current: current)
        store.upsert(entry: merged)
        entry = store.diaryEntries.first { $0.id == merged.id } ?? merged
        pendingText = entry.text; savedEntry = entry
        if !entry.text.isEmpty && entry.text.count > 10 { ReviewRequestManager.shared.registerPositiveAction() }
    }
    private func receiveStoreChanges() {
        // Read current state, never an older queued publisher value.
        guard var latest = store.diaryEntries.first(where: { $0.id == entry.id }) else { return }
        var draft = entry; draft.text = pendingText
        guard draft == savedEntry else { return }
        latest.dateOnlyTimeZoneIdentifier = latest.dateOnlyTimeZoneIdentifier ?? savedEntry.dateOnlyTimeZoneIdentifier
        entry = latest; savedEntry = latest; pendingText = latest.text
    }

    /// 本文の自動保存は SwiftData 同期と published entry 更新をスキップして入力中の IME を保つ。
    /// 画面終了時の flush やメタデータ更新時に通常保存で同期される。
    private func persistTextDraft() {
        var draft = entry
        draft.text = pendingText
        store.upsert(entry: draft, syncSwiftData: false)
    }

    private func syncPendingTextIfNeeded() {
        if entry.text != pendingText {
            entry.text = pendingText
        }
    }

    private func debouncedPersistMetadata() {
        metadataPersistTask?.cancel()
        metadataPersistTask = _Concurrency.Task { [weak self] in
            do {
                try await _Concurrency.Task.sleep(nanoseconds: UInt64(Self.metadataDebounceInterval * 1_000_000_000))
                guard !_Concurrency.Task.isCancelled else { return }
                await self?.persist()
            } catch {
                // Task.sleep がキャンセルされた場合（正常動作）
            }
        }
    }
}
