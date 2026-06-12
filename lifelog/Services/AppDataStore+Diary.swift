//
//  AppDataStore+Diary.swift
//  lifelog
//

import Foundation
import SwiftData
import SwiftUI

extension AppDataStore {

    // MARK: - Diary CRUD

    func entry(for date: Date) -> DiaryEntry? {
        diaryEntries.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func upsert(entry: DiaryEntry, syncSwiftData: Bool = true) {
        let normalized = normalizeDiaryEntry(entry)
        // syncSwiftData == false は編集中の打鍵ごとに呼ばれる軽量パス。
        // かつては UserDefaults へ下書きを書いていたが、読み戻す処理が
        // 存在しない死に書き込みだったため削除した(リマインダー解除のみ残す)。
        if syncSwiftData == false {
            let isToday = Calendar.current.isDateInToday(entry.date)
            if isToday && diaryReminderEnabled && normalized.text.isEmpty == false {
                NotificationService.shared.cancelDiaryReminder()
            }
            return
        }

        if let index = diaryEntries.firstIndex(where: { $0.id == normalized.id }) {
            diaryEntries[index] = normalized
        } else {
            diaryEntries.append(normalized)
        }

        let isToday = Calendar.current.isDateInToday(entry.date)
        let hasContent = !normalized.text.isEmpty

        if isToday && diaryReminderEnabled && hasContent {
            NotificationService.shared.cancelDiaryReminder()
        }
        guard syncSwiftData else { return }
        syncDiaryEntryToSwiftData(normalized)
        saveContext()
    }

    // MARK: - Location Visit Tags

    func createLocationVisitTag(named rawName: String) throws -> LocationVisitTagDefinition {
        let name = try validatedLocationVisitTagName(rawName)
        let definition = LocationVisitTagDefinition(name: name,
                                                    sortOrder: locationVisitTagDefinitions.count)
        locationVisitTagDefinitions.append(definition)
        persistLocationVisitTags()
        return definition
    }

    func renameLocationVisitTag(id: UUID, to rawName: String) throws {
        guard let index = locationVisitTagDefinitions.firstIndex(where: { $0.id == id }) else {
            throw LocationVisitTagError.tagNotFound
        }
        let newName = try validatedLocationVisitTagName(rawName, excluding: id)
        let oldName = locationVisitTagDefinitions[index].name
        guard isSameTagName(oldName, newName) == false else { return }
        locationVisitTagDefinitions[index].name = newName
        persistLocationVisitTags()

        let changedEntries = applyVisitTagMutation { tags in
            var didChange = false
            for i in tags.indices where isSameTagName(tags[i], oldName) {
                tags[i] = newName
                didChange = true
            }
            return didChange
        }
        syncDiaryEntriesToSwiftData(changedEntries)
    }

    @discardableResult
    func deleteLocationVisitTag(id: UUID) -> Int {
        guard let index = locationVisitTagDefinitions.firstIndex(where: { $0.id == id }) else {
            return 0
        }
        let deletedName = locationVisitTagDefinitions[index].name
        locationVisitTagDefinitions.remove(at: index)
        normalizeLocationVisitTagOrderIfNeeded()
        persistLocationVisitTags()

        var affectedVisitCount = 0
        let changedEntries = applyVisitTagMutation { tags in
            let before = tags.count
            tags.removeAll { isSameTagName($0, deletedName) }
            if tags.count != before {
                affectedVisitCount += 1
                return true
            }
            return false
        }
        syncDiaryEntriesToSwiftData(changedEntries)
        return affectedVisitCount
    }

    func moveLocationVisitTag(from source: IndexSet, to destination: Int) {
        locationVisitTagDefinitions.move(fromOffsets: source, toOffset: destination)
        normalizeLocationVisitTagOrderIfNeeded()
        persistLocationVisitTags()
    }

    @discardableResult
    func reAddDefaultLocationVisitTags() -> Int {
        var addedCount = 0
        for name in Self.defaultLocationVisitTagNames where containsLocationVisitTag(named: name) == false {
            let definition = LocationVisitTagDefinition(name: name,
                                                        sortOrder: locationVisitTagDefinitions.count)
            locationVisitTagDefinitions.append(definition)
            addedCount += 1
        }
        if addedCount > 0 {
            normalizeLocationVisitTagOrderIfNeeded()
            persistLocationVisitTags()
        }
        return addedCount
    }

    // MARK: - Diary Helpers

    static func normalizeDiaryEntries(_ entries: [DiaryEntry]) -> [DiaryEntry] {
        entries.map { entry in
            var normalized = entry
            normalized.mood = normalized.mood ?? .neutral
            normalized.conditionScore = normalized.conditionScore ?? 3
            for index in normalized.locations.indices {
                normalized.locations[index].visitTags = Self.normalizedVisitTags(normalized.locations[index].visitTags)
            }
            return normalized
        }
    }

    private func normalizeDiaryEntry(_ entry: DiaryEntry) -> DiaryEntry {
        var normalized = entry
        normalized.mood = normalized.mood ?? .neutral
        normalized.conditionScore = normalized.conditionScore ?? 3
        for index in normalized.locations.indices {
            normalized.locations[index].visitTags = Self.normalizedVisitTags(normalized.locations[index].visitTags)
        }
        return normalized
    }

    private static func normalizedTagKey(_ rawName: String) -> String {
        rawName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func normalizedVisitTags(_ tags: [String],
                                            limit: Int? = nil) -> [String] {
        let maxAllowedTags = limit ?? maxLocationVisitTagsPerVisit
        var seen: Set<String> = []
        var normalized: [String] = []
        for raw in tags {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            let key = normalizedTagKey(trimmed)
            guard seen.contains(key) == false else { continue }
            seen.insert(key)
            normalized.append(trimmed)
            if normalized.count >= maxAllowedTags {
                break
            }
        }
        return normalized
    }

    private func syncDiaryEntryToSwiftData(_ entry: DiaryEntry) {
        let entryID = entry.id
        let descriptor = FetchDescriptor<SDDiaryEntry>(predicate: #Predicate { $0.id == entryID })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.update(from: entry)
        } else {
            let newItem = SDDiaryEntry(domain: entry)
            modelContext.insert(newItem)
        }
    }

    private func syncDiaryEntriesToSwiftData(_ entries: [DiaryEntry]) {
        guard entries.isEmpty == false else { return }
        for entry in entries {
            syncDiaryEntryToSwiftData(entry)
        }
        saveContext()
    }

    private func applyVisitTagMutation(_ mutate: (inout [String]) -> Bool) -> [DiaryEntry] {
        var changedEntries: [DiaryEntry] = []
        for entryIndex in diaryEntries.indices {
            var entryChanged = false
            for locationIndex in diaryEntries[entryIndex].locations.indices {
                var tags = diaryEntries[entryIndex].locations[locationIndex].visitTags
                guard mutate(&tags) else { continue }
                diaryEntries[entryIndex].locations[locationIndex].visitTags = Self.normalizedVisitTags(tags)
                entryChanged = true
            }
            if entryChanged {
                diaryEntries[entryIndex] = normalizeDiaryEntry(diaryEntries[entryIndex])
                changedEntries.append(diaryEntries[entryIndex])
            }
        }
        if changedEntries.isEmpty == false {
        }
        return changedEntries
    }

    private func validatedLocationVisitTagName(_ rawName: String,
                                               excluding id: UUID? = nil) throws -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw LocationVisitTagError.emptyName
        }
        guard trimmed.count <= Self.maxLocationVisitTagNameLength else {
            throw LocationVisitTagError.nameTooLong(max: Self.maxLocationVisitTagNameLength)
        }
        guard containsLocationVisitTag(named: trimmed, excluding: id) == false else {
            throw LocationVisitTagError.duplicateName
        }
        return trimmed
    }

    private func containsLocationVisitTag(named name: String, excluding id: UUID? = nil) -> Bool {
        let target = Self.normalizedTagKey(name)
        return locationVisitTagDefinitions.contains {
            guard $0.id != id else { return false }
            return Self.normalizedTagKey($0.name) == target
        }
    }

    private func isSameTagName(_ lhs: String, _ rhs: String) -> Bool {
        Self.normalizedTagKey(lhs) == Self.normalizedTagKey(rhs)
    }

    func seedDefaultLocationVisitTagsIfNeeded() {
        let defaults = UserDefaults(suiteName: PersistenceController.appGroupIdentifier) ?? UserDefaults.standard
        let hasSeeded = defaults.bool(forKey: Self.locationVisitTagsSeededDefaultsKey)
        guard hasSeeded == false else { return }

        if locationVisitTagDefinitions.isEmpty {
            locationVisitTagDefinitions = Self.defaultLocationVisitTagNames.enumerated().map { index, name in
                LocationVisitTagDefinition(name: name, sortOrder: index)
            }
            persistLocationVisitTags()
        }
        defaults.set(true, forKey: Self.locationVisitTagsSeededDefaultsKey)
    }

    func normalizeLocationVisitTagOrderIfNeeded() {
        let sorted = locationVisitTagDefinitions.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.name < rhs.name
        }
        let normalized = sorted.enumerated().map { index, tag in
            var mutable = tag
            mutable.sortOrder = index
            return mutable
        }
        guard normalized != locationVisitTagDefinitions else { return }
        locationVisitTagDefinitions = normalized
        persistLocationVisitTags()
    }

    // MARK: - Diary Persisters

    func persistLocationVisitTags() {
        persist(locationVisitTagDefinitions, forKey: Self.locationVisitTagsDefaultsKey)
    }

}
