import Foundation

/// Merge only fields the human changed. Other edits come from the current
/// store, even when its publisher has not delivered yet.
nonisolated enum DiaryDraftMerger {
    @MainActor static func merge(draft: DiaryEntry, baseline: DiaryEntry, current: DiaryEntry) -> DiaryEntry {
        guard Set(baseline.locations.map(\.id)).count == baseline.locations.count, Set(draft.locations.map(\.id)).count == draft.locations.count, Set(current.locations.map(\.id)).count == current.locations.count else { return draft }
        var result = current
        if draft.text != baseline.text { result.text = draft.text }
        if draft.mood != baseline.mood { result.mood = draft.mood }
        if draft.conditionScore != baseline.conditionScore { result.conditionScore = draft.conditionScore }
        if draft.photoPaths != baseline.photoPaths { result.photoPaths = draft.photoPaths }
        if draft.locationPhotoPaths != baseline.locationPhotoPaths { result.locationPhotoPaths = draft.locationPhotoPaths }
        if draft.favoritePhotoPath != baseline.favoritePhotoPath { result.favoritePhotoPath = draft.favoritePhotoPath }
        let old = Dictionary(uniqueKeysWithValues: baseline.locations.map { ($0.id, $0) })
        let desired = Dictionary(uniqueKeysWithValues: draft.locations.map { ($0.id, $0) })
        var locations = current.locations.filter { old[$0.id] == nil || desired[$0.id] != nil }
        for location in draft.locations {
            guard let previous = old[location.id] else { if !locations.contains(where: { $0.id == location.id }) { locations.append(location) }; continue }
            guard let index = locations.firstIndex(where: { $0.id == location.id }) else {
                // A concurrently removed location is restored only when the draft edited it.
                if location != previous { locations.append(location) }; continue
            }
            if location.name != previous.name { locations[index].name = location.name }
            if location.address != previous.address { locations[index].address = location.address }
            if location.latitude != previous.latitude { locations[index].latitude = location.latitude }
            if location.longitude != previous.longitude { locations[index].longitude = location.longitude }
            if location.mapItemURL != previous.mapItemURL { locations[index].mapItemURL = location.mapItemURL }
            if location.photoPaths != previous.photoPaths { locations[index].photoPaths = location.photoPaths }
            if location.visitTags != previous.visitTags { locations[index].visitTags = location.visitTags }
        }
        if draft.locations.map(\.id) != baseline.locations.map(\.id) {
            let order = Dictionary(uniqueKeysWithValues: draft.locations.enumerated().map { ($0.element.id, $0.offset) })
            locations = locations.enumerated().sorted { lhs, rhs in (order[lhs.element.id] ?? draft.locations.count + lhs.offset) < (order[rhs.element.id] ?? draft.locations.count + rhs.offset) }.map(\.element)
        }
        result.locations = locations; result.locationName = locations.first?.name; result.latitude = locations.first?.latitude; result.longitude = locations.first?.longitude
        return result
    }
    @MainActor static func placesEqual(_ lhs: DiaryLocation, _ rhs: DiaryLocation) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.address == rhs.address && lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude && lhs.mapItemURL == rhs.mapItemURL && lhs.visitTags == rhs.visitTags
    }
}
