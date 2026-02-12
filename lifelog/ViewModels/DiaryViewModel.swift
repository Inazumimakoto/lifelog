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
import UIKit

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
        let normalized = Self.normalizedVisitTags(tags)
        guard entry.locations[index].visitTags != normalized else { return }
        entry.locations[index].visitTags = normalized
        persist()
    }
    
    func applyVisitTagRename(oldName: String, newName: String) {
        var didChange = false
        for index in entry.locations.indices {
            var tags = entry.locations[index].visitTags
            var locationChanged = false
            for tagIndex in tags.indices where Self.isSameTagName(tags[tagIndex], oldName) {
                tags[tagIndex] = newName
                locationChanged = true
            }
            if locationChanged {
                entry.locations[index].visitTags = Self.normalizedVisitTags(tags)
                didChange = true
            }
        }
        if didChange {
            persist()
        }
    }
    
    func applyVisitTagDeletion(name: String) {
        var didChange = false
        for index in entry.locations.indices {
            let before = entry.locations[index].visitTags
            let filtered = before.filter { Self.isSameTagName($0, name) == false }
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

    func updateLocationLinks(forPhoto path: String, selectedLocationIDs: [UUID]) {
        let targetIDs = Set(selectedLocationIDs)
        let identityByPath = makePhotoIdentityMap(paths: Set(entry.locations.flatMap(\.photoPaths)).union([path]))
        let selectedIdentity = identityByPath[path]
        var didChange = false
        for index in entry.locations.indices {
            let locationID = entry.locations[index].id
            let contains = entry.locations[index].photoPaths.contains(path)
            let hasEquivalent = selectedIdentity != nil && entry.locations[index].photoPaths.contains {
                identityByPath[$0] == selectedIdentity
            }
            if targetIDs.contains(locationID) {
                if contains == false && hasEquivalent == false {
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

    func linkedDiaryPhotoPaths() -> Set<String> {
        let directLinkedPaths = Set(entry.locations.flatMap(\.photoPaths))
        guard directLinkedPaths.isEmpty == false else { return [] }
        let targetPaths = Set(entry.photoPaths)
        let identityByPath = makePhotoIdentityMap(paths: targetPaths.union(directLinkedPaths))
        let linkedIdentitySet = Set(directLinkedPaths.compactMap { identityByPath[$0] })
        return Set(entry.photoPaths.filter { path in
            if directLinkedPaths.contains(path) {
                return true
            }
            guard let identity = identityByPath[path] else { return false }
            return linkedIdentitySet.contains(identity)
        })
    }

    func linkedLocationIDs(forPhoto path: String) -> Set<UUID> {
        let directMatches = Set(entry.locations.filter { $0.photoPaths.contains(path) }.map(\.id))
        let allLocationPaths = Set(entry.locations.flatMap(\.photoPaths))
        let identityByPath = makePhotoIdentityMap(paths: allLocationPaths.union([path]))
        guard let targetIdentity = identityByPath[path] else {
            return directMatches
        }
        var linkedIDs = directMatches
        for location in entry.locations where linkedIDs.contains(location.id) == false {
            if location.photoPaths.contains(where: { identityByPath[$0] == targetIdentity }) {
                linkedIDs.insert(location.id)
            }
        }
        return linkedIDs
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
        let locationPhotoAssetIdentifierIndex = makeLocationPhotoAssetIdentifierIndex()
        let locationPhotoDigestIndex = makeLocationPhotoDigestIndex()
        let locationPhotoVisualDigestIndex = makeLocationPhotoVisualDigestIndex()
        
        for item in usableItems {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    summary.failedLoadCount += 1
                    continue
                }
                if let existingPath = matchedLocationPhotoPath(for: item,
                                                               data: data,
                                                               assetIdentifierIndex: locationPhotoAssetIdentifierIndex,
                                                               digestIndex: locationPhotoDigestIndex,
                                                               visualDigestIndex: locationPhotoVisualDigestIndex) {
                    if entry.photoPaths.contains(existingPath) || summary.addedPaths.contains(existingPath) {
                        summary.skippedCount += 1
                    } else {
                        summary.addedPaths.append(existingPath)
                    }
                    continue
                }
                do {
                    let path = try await PhotoStorage.saveAsync(data: data,
                                                                sourceAssetIdentifier: item.itemIdentifier)
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
                    let path = try await PhotoStorage.saveAsync(data: data,
                                                                sourceAssetIdentifier: item.itemIdentifier)
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

    private func makeLocationPhotoAssetIdentifierIndex() -> [String: [String]] {
        PhotoStorage.assetIdentifierIndex(for: entry.locationPhotoPaths)
    }

    private func makePhotoIdentityMap(paths: Set<String>) -> [String: String] {
        guard paths.isEmpty == false else { return [:] }
        let pathList = Array(paths)
        let assetIdentifierByPath = PhotoStorage.assetIdentifierMap(for: pathList)
        var identityByPath: [String: String] = [:]
        for path in pathList {
            if let identifier = assetIdentifierByPath[path], identifier.isEmpty == false {
                identityByPath[path] = "asset:\(identifier)"
                continue
            }
            guard let data = PhotoStorage.loadData(at: path) else { continue }
            if let visualDigest = normalizedImageDigestHex(data: data), visualDigest.isEmpty == false {
                identityByPath[path] = "visual:\(visualDigest)"
                continue
            }
            identityByPath[path] = "digest:\(sha256DigestHex(data: data))"
        }
        return identityByPath
    }

    /// フォーマット差分（メタデータ/再エンコード）を吸収するための画像内容ベース索引。
    private func makeLocationPhotoVisualDigestIndex() -> [String: [String]] {
        var index: [String: [String]] = [:]
        for path in entry.locationPhotoPaths {
            guard let data = PhotoStorage.loadData(at: path),
                  let digest = normalizedImageDigestHex(data: data) else { continue }
            index[digest, default: []].append(path)
        }
        return index
    }

    private func matchedLocationPhotoPath(for item: PhotosPickerItem,
                                          data: Data,
                                          assetIdentifierIndex: [String: [String]],
                                          digestIndex: [String: [String]],
                                          visualDigestIndex: [String: [String]]) -> String? {
        if let itemIdentifier = item.itemIdentifier,
           let matched = assetIdentifierIndex[itemIdentifier]?.first {
            return matched
        }
        let digest = sha256DigestHex(data: data)
        if let matched = digestIndex[digest]?.first {
            return matched
        }
        guard let visualDigest = normalizedImageDigestHex(data: data) else { return nil }
        return visualDigestIndex[visualDigest]?.first
    }

    private func sha256DigestHex(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 画像を一定サイズへ正規化した後にハッシュ化し、エンコード差分に強い識別子を作る。
    private func normalizedImageDigestHex(data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let targetSize = CGSize(width: 256, height: 256)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let rendered = renderer.image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: targetSize))
            let drawRect = aspectFitRect(for: image.size, in: CGRect(origin: .zero, size: targetSize))
            image.draw(in: drawRect)
        }
        guard let normalizedData = rendered.pngData() else { return nil }
        return sha256DigestHex(data: normalizedData)
    }

    private func aspectFitRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        return CGRect(origin: origin, size: size)
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
    
    private static func normalizedVisitTags(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        var normalized: [String] = []
        for raw in tags {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            let key = normalizedTagKey(trimmed)
            guard seen.contains(key) == false else { continue }
            seen.insert(key)
            normalized.append(trimmed)
            if normalized.count >= AppDataStore.maxLocationVisitTagsPerVisit {
                break
            }
        }
        return normalized
    }
    
    private static func normalizedTagKey(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
    
    private static func isSameTagName(_ lhs: String, _ rhs: String) -> Bool {
        normalizedTagKey(lhs) == normalizedTagKey(rhs)
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
