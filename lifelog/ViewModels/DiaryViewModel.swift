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
import CryptoKit

@MainActor
final class DiaryViewModel: ObservableObject {

    struct PhotoImportSummary: Equatable {
        var addedPaths: [String] = []
        var skippedCount: Int = 0
        var failedLoadCount: Int = 0
        var failedSaveCount: Int = 0
        
        var addedCount: Int { addedPaths.count }
        var hasIssues: Bool { skippedCount > 0 || failedLoadCount > 0 || failedSaveCount > 0 }
    }
    
    /// テキスト入力のデバウンス時間（秒）
    private static let textDebounceInterval: TimeInterval = 0.5
    /// UI操作系（気分/体調）のデバウンス時間（秒）
    private static let metadataDebounceInterval: TimeInterval = 0.25

    @Published private(set) var entry: DiaryEntry

    private(set) var store: AppDataStore
    private let monetization = MonetizationService.shared

    var diaryPhotoLimit: Int {
        monetization.diaryPhotoLimit
    }
    
    /// テキスト保存用のデバウンスタスク
    private var textPersistTask: _Concurrency.Task<Void, Never>?
    /// 気分/体調保存用のデバウンスタスク
    private var metadataPersistTask: _Concurrency.Task<Void, Never>?
    /// 画面入力の下書き本文
    private var pendingText: String = ""

    init(store: AppDataStore, date: Date) {
        self.store = store
        let existingEntry = store.entry(for: date)
        var normalized = existingEntry ?? DiaryEntry(date: date, text: "")
        let needsDefaultPersist = (existingEntry != nil && (existingEntry?.mood == nil || existingEntry?.conditionScore == nil))
        normalized.mood = normalized.mood ?? .neutral
        normalized.conditionScore = normalized.conditionScore ?? 3
        self.entry = normalized
        self.pendingText = normalized.text

        if needsDefaultPersist {
            store.upsert(entry: normalized)
        }

        cleanupMissingPhotos()
    }
    
    /// 別の日付のエントリを読み込む
    func loadEntry(for date: Date) {
        // 前のエントリの保存を確実に完了させる
        flushPendingTextSave()
        
        let existingEntry = store.entry(for: date)
        var normalized = existingEntry ?? DiaryEntry(date: date, text: "")
        normalized.mood = normalized.mood ?? .neutral
        normalized.conditionScore = normalized.conditionScore ?? 3
        self.entry = normalized
        self.pendingText = normalized.text
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

    func addLocation(_ location: DiaryLocation) {
        guard entry.locations.contains(where: { Self.isSameLocation($0, location) }) == false else { return }
        entry.locations.append(location)
        syncPrimaryLocation()
        persist()
    }

    func removeLocation(id: UUID) {
        entry.locations.removeAll { $0.id == id }
        syncPrimaryLocation()
        persist()
    }

    func updatePhotoLinks(forLocation locationID: UUID, selectedPaths: [String]) {
        guard let index = entry.locations.firstIndex(where: { $0.id == locationID }) else { return }
        let ordered = orderedPhotoPaths(from: Set(selectedPaths))
        entry.locations[index].photoPaths = ordered
        persist()
    }

    func updateLocationLinks(forPhoto path: String, selectedLocationIDs: [UUID]) {
        let targetIDs = Set(selectedLocationIDs)
        var didChange = false
        for index in entry.locations.indices {
            let locationID = entry.locations[index].id
            let contains = entry.locations[index].photoPaths.contains(path)
            if targetIDs.contains(locationID) {
                if contains == false {
                    entry.locations[index].photoPaths.append(path)
                    didChange = true
                }
            } else if contains {
                entry.locations[index].photoPaths.removeAll { $0 == path }
                didChange = true
            }
        }
        if didChange {
            for index in entry.locations.indices {
                entry.locations[index].photoPaths = orderedPhotoPaths(from: Set(entry.locations[index].photoPaths))
            }
        }
        if didChange {
            persist()
        }
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
        guard entry.photoPaths.count < diaryPhotoLimit else { return }
        guard let path = try? PhotoStorage.save(data: data) else { return }
        entry.photoPaths.append(path)
        persist()
    }

    func addLocationPhoto(data: Data) {
        guard let path = try? PhotoStorage.save(data: data) else { return }
        entry.locationPhotoPaths.append(path)
        persist()
    }

    func importPhotos(from items: [PhotosPickerItem]) async -> PhotoImportSummary {
        guard items.isEmpty == false else { return PhotoImportSummary() }

        let targetDate = entry.date
        let availableSlots = max(0, diaryPhotoLimit - entry.photoPaths.count)
        if availableSlots == 0 {
            return PhotoImportSummary(addedPaths: [],
                                      skippedCount: items.count,
                                      failedLoadCount: 0,
                                      failedSaveCount: 0)
        }
        
        let usableItems = Array(items.prefix(availableSlots))
        var summary = PhotoImportSummary()
        summary.skippedCount = max(0, items.count - usableItems.count)
        let locationPhotoDigestIndex = makeLocationPhotoDigestIndex()
        
        for item in usableItems {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    summary.failedLoadCount += 1
                    continue
                }
                if let existingPath = matchedLocationPhotoPath(for: data,
                                                               digestIndex: locationPhotoDigestIndex) {
                    if entry.photoPaths.contains(existingPath) || summary.addedPaths.contains(existingPath) {
                        summary.skippedCount += 1
                    } else {
                        summary.addedPaths.append(existingPath)
                    }
                    continue
                }
                do {
                    let path = try await PhotoStorage.saveAsync(data: data)
                    summary.addedPaths.append(path)
                } catch {
                    summary.failedSaveCount += 1
                }
            } catch {
                summary.failedLoadCount += 1
            }
        }
        
        if summary.addedPaths.isEmpty == false {
            if entry.date.isSameDay(as: targetDate) {
                entry.photoPaths.append(contentsOf: summary.addedPaths)
                persist()
            } else {
                var otherEntry = store.entry(for: targetDate) ?? DiaryEntry(date: targetDate, text: "")
                otherEntry.photoPaths.append(contentsOf: summary.addedPaths)
                store.upsert(entry: otherEntry)
            }
        }
        
        return summary
    }

    func importLocationPhotos(from items: [PhotosPickerItem]) async -> PhotoImportSummary {
        guard items.isEmpty == false else { return PhotoImportSummary() }

        let targetDate = entry.date
        var summary = PhotoImportSummary()

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    summary.failedLoadCount += 1
                    continue
                }
                do {
                    let path = try await PhotoStorage.saveAsync(data: data)
                    summary.addedPaths.append(path)
                } catch {
                    summary.failedSaveCount += 1
                }
            } catch {
                summary.failedLoadCount += 1
            }
        }

        if summary.addedPaths.isEmpty == false {
            if entry.date.isSameDay(as: targetDate) {
                entry.locationPhotoPaths.append(contentsOf: summary.addedPaths)
                persist()
            } else {
                var otherEntry = store.entry(for: targetDate) ?? DiaryEntry(date: targetDate, text: "")
                otherEntry.locationPhotoPaths.append(contentsOf: summary.addedPaths)
                store.upsert(entry: otherEntry)
            }
        }

        return summary
    }

    func deletePhoto(at offsets: IndexSet) {
        let sortedOffsets = offsets.sorted(by: >)
        for index in sortedOffsets {
            guard entry.photoPaths.indices.contains(index) else { continue }
            let path = entry.photoPaths[index]
            if entry.favoritePhotoPath == path {
                entry.favoritePhotoPath = nil
            }
            entry.photoPaths.remove(at: index)
            removePhotoAssetIfUnreferenced(path)
        }
        persist()
    }

    func deleteLocationPhoto(at offsets: IndexSet) {
        let sortedOffsets = offsets.sorted(by: >)
        for index in sortedOffsets {
            guard entry.locationPhotoPaths.indices.contains(index) else { continue }
            let path = entry.locationPhotoPaths[index]
            entry.locationPhotoPaths.remove(at: index)
            removePhotoAssetIfUnreferenced(path)
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
        let originalDiary = entry.photoPaths
        let originalLocation = entry.locationPhotoPaths
        let keptDiary = originalDiary.filter { PhotoStorage.fileExists(for: $0) }
        let keptLocation = originalLocation.filter { PhotoStorage.fileExists(for: $0) }
        let allKept = Set(keptDiary + keptLocation)
        let didChange = keptDiary.count != originalDiary.count
            || keptLocation.count != originalLocation.count
        guard didChange else { return }
        entry.photoPaths = keptDiary
        entry.locationPhotoPaths = keptLocation
        if let favorite = entry.favoritePhotoPath, keptDiary.contains(favorite) == false {
            entry.favoritePhotoPath = nil
        }
        pruneLocationPhotoLinks(availablePaths: allKept)
        persist()
    }

    private func orderedPhotoPaths(from selection: Set<String>) -> [String] {
        allPhotoPathsInOrder.filter { selection.contains($0) }
    }

    private func makeLocationPhotoDigestIndex() -> [String: [String]] {
        var index: [String: [String]] = [:]
        for path in entry.locationPhotoPaths {
            guard let data = PhotoStorage.loadData(at: path) else { continue }
            let digest = sha256DigestHex(data: data)
            index[digest, default: []].append(path)
        }
        return index
    }

    private func matchedLocationPhotoPath(for data: Data,
                                          digestIndex: [String: [String]]) -> String? {
        let digest = sha256DigestHex(data: data)
        return digestIndex[digest]?.first
    }

    private func sha256DigestHex(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private var allPhotoPathsInOrder: [String] {
        entry.photoPaths + entry.locationPhotoPaths
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

    private func removePhotoAssetIfUnreferenced(_ path: String) {
        guard entry.photoPaths.contains(path) == false,
              entry.locationPhotoPaths.contains(path) == false else { return }
        PhotoStorage.delete(at: path)
        removePhotoLinks(for: path)
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
                await self?.persist()
            } catch {
                // Task.sleep がキャンセルされた場合（正常動作）
            }
        }
    }
    
    /// 保留中のテキスト保存を即座に実行（画面を閉じる前に呼び出す）
    func flushPendingTextSave() {
        textPersistTask?.cancel()
        textPersistTask = nil
        // 現在のエントリを即座に保存
        persist()
    }

    private func persist() {
        syncPendingTextIfNeeded()
        entry.mood = entry.mood ?? .neutral
        entry.conditionScore = entry.conditionScore ?? 3
        store.upsert(entry: entry)
        
        // 日記の内容がある程度ある場合にポジティブアクションとして記録
        if !entry.text.isEmpty && entry.text.count > 10 {
            ReviewRequestManager.shared.registerPositiveAction()
        }
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
