import Foundation
import SwiftData

/// Imports verified records from a disposable copy. The active store remains the source of
/// truth for edits made since the reset. All changes belong to one save and one context.
@MainActor
final class RecoveredRecordImporter {
    private let source: ModelContext
    private let destination: ModelContext
    private var restored = 0

    private init(source: ModelContainer, destination: ModelContainer) {
        self.source = ModelContext(source)
        self.destination = ModelContext(destination)
        self.source.autosaveEnabled = false
        self.destination.autosaveEnabled = false
    }

    nonisolated deinit {}

    static func restore(from source: ModelContainer, into destination: ModelContainer) throws -> Int {
        let importer = Self(source: source, destination: destination)
        do {
            try importer.importRecords()
            if importer.restored > 0 { try importer.destination.save() }
            return importer.restored
        } catch {
            importer.destination.rollback()
            throw error
        }
    }

    private func importRecords() throws {
        try copy(id: \SDTask.id) { SDTask(domain: Task(sd: $0)) }
        try copy(id: \SDDiaryEntry.id, key: Self.diaryDay, mergeMatchingIDs: true,
                 merge: Self.mergeDiary, clone: Self.cloneDiary)
        try copy(id: \SDHabit.id) { old in
            let habit = SDHabit(domain: Habit(sd: old))
            habit.orderIndex = old.orderIndex
            habit.scheduleType = old.scheduleType
            habit.scheduleDays = old.scheduleDays
            return habit
        }
        try importHabitRecords()
        try copy(id: \SDAnniversary.id) { old in
            let anniversary = SDAnniversary(domain: Anniversary(sd: old))
            anniversary.orderIndex = old.orderIndex
            return anniversary
        }
        try copy(id: \SDHealthSummary.id, key: { Calendar.current.startOfDay(for: $0.date) },
                 merge: Self.mergeHealth) { old in
            let summary = SDHealthSummary(domain: HealthSummary(sd: old))
            summary.fitnessMoveModeRaw = old.fitnessMoveModeRaw
            return summary
        }
        try copy(id: \SDCalendarEvent.id) { old in
            let event = SDCalendarEvent(id: old.id, title: old.title,
                                        startDate: old.startDate, endDate: old.endDate,
                                        calendarName: old.calendarName, isAllDay: old.isAllDay,
                                        sourceCalendarIdentifier: old.sourceCalendarIdentifier,
                                        reminderMinutes: old.reminderMinutes, reminderDate: old.reminderDate,
                                        dateOnlyTimeZoneIdentifier: old.dateOnlyTimeZoneIdentifier,
                                        recurrenceRuleData: old.recurrenceRuleData, urlString: old.urlString)
            event.detail = old.detail
            return event
        }
        try copy(id: \SDCalendarEventException.id, key: {
            CalendarEventOccurrenceReference(seriesID: $0.seriesID, originalStartDate: $0.originalStartDate)
        }) { old in
            SDCalendarEventException(id: old.id, seriesID: old.seriesID, originalStartDate: old.originalStartDate,
                                     replacementData: old.replacementData)
        }
        try copy(id: \SDLetter.id, clone: Self.cloneLetter)
        try copy(id: \SDSharedLetter.id) { SDSharedLetter(domain: SharedLetter(sd: $0)) }
        try importShopping()
        try importMemo()
        try importAppState()
    }

    private struct HabitDay: Hashable {
        let habitID: UUID
        let day: Date

        init(_ record: SDHabitRecord) {
            habitID = record.habitID
            day = Calendar.current.startOfDay(for: record.date)
        }
    }

    private func importHabitRecords() throws {
        // HabitRecordLookup intentionally counts multiple legacy records on one day.
        // Preserve these together unless there is a post-reset record for that habit/day.
        let active = try destination.fetch(FetchDescriptor<SDHabitRecord>())
        let existingIDs = Set(active.map(\.id))
        let existingDays = Set(active.map(HabitDay.init))
        for old in try source.fetch(FetchDescriptor<SDHabitRecord>()) {
            guard !existingIDs.contains(old.id), !existingDays.contains(HabitDay(old)) else { continue }
            destination.insert(SDHabitRecord(domain: HabitRecord(sd: old)))
            restored += 1
        }
    }

    private func copy<Row: PersistentModel, ID: Hashable>(
        id: KeyPath<Row, ID>, include: (Row) -> Bool = { _ in true }, clone: (Row) -> Row
    ) throws {
        var identifiers = FetchDescriptor<Row>()
        identifiers.propertiesToFetch = [id]
        var known = Set(try destination.fetch(identifiers).map { $0[keyPath: id] })
        try source.enumerate(FetchDescriptor<Row>(), batchSize: 256) { old in
            guard include(old), known.insert(old[keyPath: id]).inserted else { return }
            destination.insert(clone(old))
            restored += 1
        }
    }

    /// Several domains have a logical identity in addition to the persisted UUID, e.g.
    /// a diary day or a series occurrence. Avoid creating a second invisible record.
    private func copy<Row: PersistentModel, ID: Hashable, Key: Hashable>(
        id: KeyPath<Row, ID>, key: (Row) -> Key, mergeMatchingIDs: Bool = false,
        merge: (Row, Row) throws -> Bool = { _, _ in false }, clone: (Row) -> Row
    ) throws {
        let current = try destination.fetch(FetchDescriptor<Row>())
        var byID = Dictionary(current.map { ($0[keyPath: id], $0) }, uniquingKeysWith: { first, _ in first })
        var byKey = Dictionary(current.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
        try source.enumerate(FetchDescriptor<Row>(), batchSize: 256) { old in
            let identity = old[keyPath: id]
            let logicalID = key(old)
            if let matchingID = byID[identity] {
                if mergeMatchingIDs, key(matchingID) == logicalID, try merge(matchingID, old) {
                    restored += 1
                }
            } else if let existing = byKey[logicalID] {
                if try merge(existing, old) { restored += 1 }
            } else {
                let copied = clone(old)
                destination.insert(copied)
                byID[identity] = copied
                byKey[logicalID] = copied
                restored += 1
            }
        }
    }

    private static func diaryDay(_ row: SDDiaryEntry) -> Date {
        let calendar = Calendar.current
        guard let zone = row.dateOnlyTimeZoneIdentifier, zone != calendar.timeZone.identifier else {
            return calendar.startOfDay(for: row.date)
        }
        return calendar.startOfDay(for: DateOnlyProjection.project(row.date, sourceTimeZoneIdentifier: zone, calendar: calendar))
    }

    private static func cloneDiary(_ old: SDDiaryEntry) -> SDDiaryEntry {
        let copy = SDDiaryEntry(id: old.id, date: old.date, text: old.text,
                                dateOnlyTimeZoneIdentifier: old.dateOnlyTimeZoneIdentifier,
                                mood: old.mood, conditionScore: old.conditionScore,
                                locationsData: old.locationsData, locationName: old.locationName,
                                latitude: old.latitude, longitude: old.longitude,
                                photoPaths: old.photoPaths, favoritePhotoPath: old.favoritePhotoPath)
        copy.locationPhotoPaths = old.locationPhotoPaths
        return copy
    }

    private static func mergeDiary(_ current: SDDiaryEntry, _ old: SDDiaryEntry) throws -> Bool {
        // A second restore usually sees identical rows. Avoid re-encoding locations,
        // rewriting array properties, or decoding a legacy payload that was copied intact.
        let sameVisits = current.locationsData == old.locationsData && current.locationName == old.locationName &&
            current.latitude == old.latitude && current.longitude == old.longitude
        if sameVisits, current.text == old.text, current.photoPaths == old.photoPaths,
           current.locationPhotoPaths == old.locationPhotoPaths, current.favoritePhotoPath == old.favoritePhotoPath,
           current.mood == old.mood, current.conditionScore == old.conditionScore {
            return false
        }
        var changed = appendText(old.text, to: &current.text)
        changed = appendMissing(old.photoPaths, to: &current.photoPaths) || changed
        var visitPaths = current.locationPhotoPaths ?? []
        if appendMissing(old.locationPhotoPaths ?? [], to: &visitPaths) {
            current.locationPhotoPaths = visitPaths
            changed = true
        }
        changed = fill(&current.favoritePhotoPath, from: old.favoritePhotoPath) || changed
        changed = fill(&current.mood, from: old.mood) || changed
        changed = fill(&current.conditionScore, from: old.conditionScore) || changed

        guard !sameVisits else { return changed }
        let oldVisits = try visits(old)
        if !oldVisits.isEmpty {
            var merged = try visits(current)
            let original = merged
            for visit in oldVisits {
                if let index = merged.firstIndex(where: { $0.id == visit.id }) {
                    appendMissing(visit.photoPaths, to: &merged[index].photoPaths)
                    appendMissing(visit.visitTags, to: &merged[index].visitTags)
                } else {
                    merged.append(visit)
                }
            }
            if merged != original {
                current.locationsData = try JSONEncoder().encode(merged)
                if let first = merged.first {
                    current.locationName = current.locationName ?? first.name
                    current.latitude = current.latitude ?? first.latitude
                    current.longitude = current.longitude ?? first.longitude
                }
                changed = true
            }
        }
        return changed
    }

    private static func visits(_ row: SDDiaryEntry) throws -> [DiaryLocation] {
        if let data = row.locationsData {
            let decoded = try JSONDecoder().decode([DiaryLocation].self, from: data)
            if !decoded.isEmpty { return decoded }
        }
        guard let name = row.locationName, let latitude = row.latitude, let longitude = row.longitude else { return [] }
        // Legacy rows had no visit ID. Reuse the diary UUID so that retries match the visit.
        return [DiaryLocation(id: row.id, name: name, address: nil, latitude: latitude,
                              longitude: longitude, mapItemURL: nil)]
    }

    private static func appendText(_ old: String, to current: inout String) -> Bool {
        guard !old.isEmpty, !("\n\n" + current + "\n\n").contains("\n\n" + old + "\n\n") else { return false }
        current = current.isEmpty ? old : current + "\n\n" + old
        return true
    }

    @discardableResult
    private static func appendMissing<Element: Hashable>(_ old: [Element], to current: inout [Element]) -> Bool {
        var seen = Set(current)
        let missing = old.filter { seen.insert($0).inserted }
        guard !missing.isEmpty else { return false }
        current += missing
        return true
    }

    @discardableResult
    private static func fill<Value>(_ current: inout Value?, from old: Value?) -> Bool {
        guard current == nil, let old else { return false }
        current = old
        return true
    }

    private static func mergeHealth(_ current: SDHealthSummary, _ old: SDHealthSummary) -> Bool {
        // Frequently a reset has already created a partial HealthKit/weather cache for today.
        var changed = false
        func restore<Value>(_ fields: [ReferenceWritableKeyPath<SDHealthSummary, Value?>]) {
            for field in fields where current[keyPath: field] == nil {
                if let value = old[keyPath: field] {
                    current[keyPath: field] = value
                    changed = true
                }
            }
        }
        restore([\.steps])
        restore([\.sleepHours, \.activeEnergy, \.moveMinutes, \.exerciseMinutes, \.standHours,
                 \.activeEnergyGoal, \.moveMinutesGoal, \.exerciseMinutesGoal, \.standHoursGoal,
                 \.highTemperature, \.lowTemperature])
        restore([\.fitnessMoveModeRaw, \.weatherCondition])
        restore([\.sleepStart, \.sleepEnd])
        if current.sleepStages.isEmpty, !old.sleepStages.isEmpty {
            current.sleepStages = old.sleepStages
            changed = true
        }
        return changed
    }

    private static func cloneLetter(_ old: SDLetter) -> SDLetter {
        SDLetter(id: old.id, content: old.content, photoPaths: old.photoPaths, createdAt: old.createdAt,
                 deliveryType: old.deliveryType, deliveryDate: old.deliveryDate, statusRaw: old.statusRaw,
                 openedAt: old.openedAt, dismissedFromHome: old.dismissedFromHome,
                 randomUseDateRange: old.randomUseDateRange, randomStartDate: old.randomStartDate,
                 randomEndDate: old.randomEndDate, randomUseTimeRange: old.randomUseTimeRange,
                 randomStartHour: old.randomStartHour, randomStartMinute: old.randomStartMinute,
                 randomEndHour: old.randomEndHour, randomEndMinute: old.randomEndMinute,
                 randomFixedDate: old.randomFixedDate, randomFixedHour: old.randomFixedHour,
                 randomFixedMinute: old.randomFixedMinute)
    }

    private func importShopping() throws {
        // A place of the same name can have been recreated since the reset. Items must
        // point at the active ID when we reuse such a place.
        let places = try destination.fetch(FetchDescriptor<SDShoppingPlace>())
        var activeIDs = Set(places.map(\.id))
        func nameKey(_ name: String) -> String { name.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil) }
        var byName = Dictionary(places.map { (nameKey($0.name), $0.id) }, uniquingKeysWith: { first, _ in first })
        var aliases: [UUID: UUID] = [:]
        for old in try source.fetch(FetchDescriptor<SDShoppingPlace>()) where !activeIDs.contains(old.id) {
            let key = nameKey(old.name)
            if let matching = byName[key] {
                aliases[old.id] = matching
            } else {
                destination.insert(SDShoppingPlace(id: old.id, name: old.name, orderIndex: old.orderIndex))
                activeIDs.insert(old.id)
                byName[key] = old.id
                restored += 1
            }
        }
        // ShoppingStore removes retired purchase history on load. Reimporting it
        // would incorrectly report the same removed rows as newly restored on every run.
        try copy(id: \SDShoppingItem.id, include: { $0.purchasedAt == nil }) { old in
            let item = SDShoppingItem(id: old.id, title: old.title, note: old.note,
                                      placeID: old.placeID.map { aliases[$0] ?? $0 },
                                      createdAt: old.createdAt, purchasedAt: old.purchasedAt)
            item.legacyQuantity = old.legacyQuantity
            return item
        }
    }

    private func importMemo() throws {
        let memos = try source.fetch(FetchDescriptor<SDMemoPad>())
        var current = try destination.fetch(FetchDescriptor<SDMemoPad>()).first
        for old in memos where !old.text.isEmpty {
            if let current {
                let wasEmpty = current.text.isEmpty
                if Self.appendText(old.text, to: &current.text) {
                    if wasEmpty { current.lastUpdatedAt = old.lastUpdatedAt }
                    restored += 1
                }
            } else {
                let memo = SDMemoPad(text: old.text, lastUpdatedAt: old.lastUpdatedAt)
                destination.insert(memo)
                current = memo
                restored += 1
            }
        }
    }

    private func importAppState() throws {
        let states = try source.fetch(FetchDescriptor<SDAppState>())
        var current = try destination.fetch(FetchDescriptor<SDAppState>()).first
        for old in states {
            guard let state = current else {
                let copy = SDAppState(lastCalendarSyncDate: old.lastCalendarSyncDate, calendarCategoryLinks: old.calendarCategoryLinks,
                                      unavailableCalendarCategoryLinks: old.unavailableCalendarCategoryLinks,
                                      diaryReminderEnabled: old.diaryReminderEnabled,
                                      diaryReminderHour: old.diaryReminderHour, diaryReminderMinute: old.diaryReminderMinute)
                destination.insert(copy)
                current = copy
                restored += 1
                continue
            }
            var changed = Self.fill(&state.lastCalendarSyncDate, from: old.lastCalendarSyncDate)
            var knownLinks = Set((state.calendarCategoryLinks + (state.unavailableCalendarCategoryLinks ?? [])).map(\.calendarIdentifier))
            let visible = old.calendarCategoryLinks.filter { knownLinks.insert($0.calendarIdentifier).inserted }
            let archived = (old.unavailableCalendarCategoryLinks ?? []).filter { knownLinks.insert($0.calendarIdentifier).inserted }
            if !visible.isEmpty {
                state.calendarCategoryLinks += visible
                changed = true
            }
            if !archived.isEmpty {
                state.unavailableCalendarCategoryLinks = (state.unavailableCalendarCategoryLinks ?? []) + archived
                changed = true
            }
            let usesDefaultReminder = !state.diaryReminderEnabled && state.diaryReminderHour == 21 && state.diaryReminderMinute == 0
            let oldHasReminder = old.diaryReminderEnabled || old.diaryReminderHour != 21 || old.diaryReminderMinute != 0
            if usesDefaultReminder && oldHasReminder {
                state.diaryReminderEnabled = old.diaryReminderEnabled
                state.diaryReminderHour = old.diaryReminderHour
                state.diaryReminderMinute = old.diaryReminderMinute
                changed = true
            }
            if changed { restored += 1 }
        }
    }
}
