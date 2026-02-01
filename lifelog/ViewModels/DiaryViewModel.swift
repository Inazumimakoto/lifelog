//
//  DiaryViewModel.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import Foundation
import CoreLocation
import Combine

@MainActor
final class DiaryViewModel: ObservableObject {

    static let maxPhotos: Int = 10
    
    /// テキスト入力のデバウンス時間（秒）
    private static let textDebounceInterval: TimeInterval = 0.5
    /// UI操作系（気分/体調）のデバウンス時間（秒）
    private static let metadataDebounceInterval: TimeInterval = 0.25

    @Published private(set) var entry: DiaryEntry

    private(set) var store: AppDataStore
    
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
        persist()
    }

    func addPhoto(data: Data) {
        guard entry.photoPaths.count < Self.maxPhotos else { return }
        guard let path = try? PhotoStorage.save(data: data) else { return }
        entry.photoPaths.append(path)
        persist()
    }

    func deletePhoto(at offsets: IndexSet) {
        let sortedOffsets = offsets.sorted(by: >)
        for index in sortedOffsets {
            guard entry.photoPaths.indices.contains(index) else { continue }
            let path = entry.photoPaths[index]
            PhotoStorage.delete(at: path)
            if entry.favoritePhotoPath == path {
                entry.favoritePhotoPath = nil
            }
            entry.photoPaths.remove(at: index)
        }
        persist()
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
        let original = entry.photoPaths
        let kept = original.filter { PhotoStorage.fileExists(for: $0) }
        guard kept.count != original.count else { return }
        entry.photoPaths = kept
        persist()
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
