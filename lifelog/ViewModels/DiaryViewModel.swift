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

    @Published private(set) var entry: DiaryEntry

    private let store: AppDataStore

    init(store: AppDataStore, date: Date) {
        self.store = store
        let existingEntry = store.entry(for: date)
        var normalized = existingEntry ?? DiaryEntry(date: date, text: "")
        let needsDefaultPersist = (existingEntry != nil && (existingEntry?.mood == nil || existingEntry?.conditionScore == nil))
        normalized.mood = normalized.mood ?? .neutral
        normalized.conditionScore = normalized.conditionScore ?? 3
        self.entry = normalized

        if needsDefaultPersist {
            store.upsert(entry: normalized)
        }

        cleanupMissingPhotos()
    }

    func update(text: String) {
        entry.text = text
        persist()
    }

    func update(mood: MoodLevel?) {
        entry.mood = mood
        persist()
    }

    func update(condition: Int?) {
        entry.conditionScore = condition
        persist()
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

    private func persist() {
        entry.mood = entry.mood ?? .neutral
        entry.conditionScore = entry.conditionScore ?? 3
        store.upsert(entry: entry)
    }
}
