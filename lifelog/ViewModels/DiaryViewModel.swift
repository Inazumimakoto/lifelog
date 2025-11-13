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

    @Published private(set) var entry: DiaryEntry

    private let store: AppDataStore

    init(store: AppDataStore, date: Date) {
        self.store = store
        self.entry = store.entry(for: date) ?? DiaryEntry(date: date, text: "")
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
        guard entry.photoPaths.count < 50 else { return }
        guard let path = try? PhotoStorage.save(data: data) else { return }
        entry.photoPaths.append(path)
        persist()
    }

    func deletePhoto(at offsets: IndexSet) {
        let sortedOffsets = offsets.sorted(by: >)
        for index in sortedOffsets {
            guard entry.photoPaths.indices.contains(index) else { continue }
            PhotoStorage.delete(at: entry.photoPaths[index])
            entry.photoPaths.remove(at: index)
        }
        persist()
    }

    private func persist() {
        store.upsert(entry: entry)
    }
}
