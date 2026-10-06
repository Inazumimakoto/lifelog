import Foundation

/// Derived review-map data only (docs/requirements.md §4.4.2).
/// Disk reads, difference detection, aggregation and formatting stay on this worker actor.
actor ReviewMapCacheService {
    private(set) var lastRebuiltPlaceIDs: Set<String> = []
    private(set) var lastRenderedPlaceIDs: Set<String> = []
    private(set) var persistentWriteCount = 0
    private(set) var loadedFromDisk = false

    var cachedQueryCount: Int { queries.count }

    private let fileURL: URL?
    private var environment: ReviewMapEnvironment?
    private var sourcesByID: [UUID: ReviewMapDiarySource] = [:]
    private var sourceDays: [UUID: Date] = [:]
    private var contributionsBySource: [UUID: [String: [ReviewMapLocationSource]]] = [:]
    private var placeSourceIDs: [String: Set<UUID>] = [:]
    private var aggregates: [String: Aggregate] = [:]
    private var tagPlaceIDs: [String: Set<String>] = [:]
    private var tagsByID: [UUID: ReviewMapTagSource] = [:]
    private var tagLookup = TagLookup(tags: [])
    private var queries: [ReviewMapQuery: CachedQuery] = [:]
    private var accessCounter: UInt64 = 0
    private var monthDayFormatter: DateFormatter?
    private var needsPersistence = false
    private var writeGeneration: UInt64 = 0
    private var pendingWriteTask: _Concurrency.Task<Void, Never>?
    private var highestRequestRevision: UInt64?

    private static let schemaVersion = 1
    private static let queryLimit = 8

    /// Initialization is deliberately free of disk I/O, including when called on MainActor.
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
    }

    func snapshot(sources: [ReviewMapDiarySource],
                  tags: [ReviewMapTagSource],
                  query: ReviewMapQuery,
                  environment requestedEnvironment: ReviewMapEnvironment,
                  requestRevision: UInt64? = nil) async -> ReviewMapSnapshot {
        lastRebuiltPlaceIDs = []
        lastRenderedPlaceIDs = []
        if let requestRevision {
            if let highestRequestRevision, requestRevision < highestRequestRevision {
                // Older prewarm work may request another query, but cannot roll back source state.
                return finishQuery(query)
            }
            highestRequestRevision = requestRevision
        }
        prepare(environment: requestedEnvironment)

        var incomingSources: [UUID: ReviewMapDiarySource] = [:]
        for source in sources { incomingSources[source.id] = source }
        var incomingTags: [UUID: ReviewMapTagSource] = [:]
        for var tag in tags {
            tag.colorHex = ReviewMapCacheIdentity.normalizedColorHex(tag.colorHex)
            incomingTags[tag.id] = tag
        }
        let changedSourceIDs = Set(sourcesByID.keys).union(incomingSources.keys).filter {
            sourcesByID[$0] != incomingSources[$0]
        }
        let changedTagIDs = Set(tagsByID.keys).union(incomingTags.keys).filter {
            tagsByID[$0] != incomingTags[$0]
        }

        // An unchanged persisted query returns without aggregation, formatting or a disk rewrite.
        if changedSourceIDs.isEmpty, changedTagIDs.isEmpty, var cached = queries[query] {
            accessCounter &+= 1
            cached.lastAccess = accessCounter
            queries[query] = cached
            return cached.snapshot
        }

        var changedTagKeys: Set<String> = []
        for id in changedTagIDs {
            if let tag = tagsByID[id] { changedTagKeys.insert(ReviewMapCacheIdentity.normalizedName(tag.name)) }
            if let tag = incomingTags[id] { changedTagKeys.insert(ReviewMapCacheIdentity.normalizedName(tag.name)) }
        }
        var affectedTagPlaces: Set<String> = []
        for key in changedTagKeys { affectedTagPlaces.formUnion(tagPlaceIDs[key] ?? []) }

        let changedPlaces = applySourceChanges(changedSourceIDs, incoming: incomingSources,
                                              calendar: requestedEnvironment.calendar)
        for id in changedPlaces.sorted() { rebuildPlace(id) }
        lastRebuiltPlaceIDs = changedPlaces

        if !changedTagIDs.isEmpty {
            tagsByID = incomingTags
            tagLookup = TagLookup(tags: Array(incomingTags.values))
            for key in changedTagKeys { affectedTagPlaces.formUnion(tagPlaceIDs[key] ?? []) }
        }
        let affectedPlaces = changedPlaces.union(affectedTagPlaces)
        if !changedSourceIDs.isEmpty || !changedTagIDs.isEmpty {
            // Patch every retained query so its disk snapshot is immediately usable after restart.
            for cachedQuery in Array(queries.keys) {
                guard let cached = queries[cachedQuery] else { continue }
                queries[cachedQuery] = patch(cached, changedPlaceIDs: affectedPlaces)
            }
            needsPersistence = true
        }

        return finishQuery(query)
    }

    private func finishQuery(_ query: ReviewMapQuery) -> ReviewMapSnapshot {
        accessCounter &+= 1
        if var cached = queries[query] {
            cached.lastAccess = accessCounter
            queries[query] = cached
        } else {
            queries[query] = buildQuery(query, lastAccess: accessCounter)
            evictOldQueries()
            needsPersistence = true
        }
        schedulePersistence()
        return queries[query]?.snapshot ?? ReviewMapSnapshot(
            query: query, places: [], availableTagNames: [], region: nil
        )
    }

    /// Call at a durability boundary, such as scene backgrounding; writes only changed cache data.
    func flush() async {
        writeGeneration &+= 1
        pendingWriteTask?.cancel()
        pendingWriteTask = nil
        persistIfNeeded()
    }

    private func prepare(environment requested: ReviewMapEnvironment) {
        if environment == requested { return }
        let isFirstRequest = environment == nil
        resetDerivedState()
        environment = requested
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: requested.localeIdentifier)
        formatter.calendar = requested.calendar
        formatter.timeZone = requested.calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("Md")
        monthDayFormatter = formatter
        guard isFirstRequest, let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == Self.schemaVersion,
              envelope.environment == requested,
              Set(envelope.sources.map(\.id)).count == envelope.sources.count,
              Set(envelope.tags.map(\.id)).count == envelope.tags.count,
              Set(envelope.aggregates.map(\.id)).count == envelope.aggregates.count,
              envelope.queries.count <= Self.queryLimit else { return }

        for source in envelope.sources {
            sourcesByID[source.id] = source
            sourceDays[source.id] = requested.calendar.startOfDay(for: source.date)
            let contributions = sourceContributions(source)
            contributionsBySource[source.id] = contributions
            for id in contributions.keys { placeSourceIDs[id, default: []].insert(source.id) }
        }
        guard Set(placeSourceIDs.keys) == Set(envelope.aggregates.map(\.id)) else {
            resetDerivedState()
            environment = requested
            monthDayFormatter = formatter
            return
        }
        for aggregate in envelope.aggregates {
            aggregates[aggregate.id] = aggregate
            indexTags(for: aggregate)
        }
        for tag in envelope.tags { tagsByID[tag.id] = tag }
        tagLookup = TagLookup(tags: envelope.tags)
        for cached in envelope.queries {
            guard Set(cached.snapshot.places.map(\.id)).count == cached.snapshot.places.count else {
                resetDerivedState()
                environment = requested
                monthDayFormatter = formatter
                return
            }
            queries[cached.snapshot.query] = cached
            accessCounter = max(accessCounter, cached.lastAccess)
        }
        loadedFromDisk = true
    }

    private func resetDerivedState() {
        writeGeneration &+= 1
        pendingWriteTask?.cancel()
        pendingWriteTask = nil
        sourcesByID = [:]
        sourceDays = [:]
        contributionsBySource = [:]
        placeSourceIDs = [:]
        aggregates = [:]
        tagPlaceIDs = [:]
        tagsByID = [:]
        tagLookup = TagLookup(tags: [])
        queries = [:]
        accessCounter = 0
        needsPersistence = false
        loadedFromDisk = false
    }

    private func sourceContributions(_ source: ReviewMapDiarySource) -> [String: [ReviewMapLocationSource]] {
        var result: [String: [ReviewMapLocationSource]] = [:]
        for location in source.locations {
            result[ReviewMapCacheIdentity.placeID(for: location), default: []].append(location)
        }
        for id in Array(result.keys) {
            result[id]?.sort { $0.id.uuidString < $1.id.uuidString }
        }
        return result
    }

    /// Compare each place's contributions inside a changed diary, not every place in that diary.
    private func applySourceChanges(_ changedIDs: Set<UUID>,
                                    incoming: [UUID: ReviewMapDiarySource],
                                    calendar: Calendar) -> Set<String> {
        var changedPlaces: Set<String> = []
        for sourceID in changedIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            let old = contributionsBySource[sourceID] ?? [:]
            let new = incoming[sourceID].map(sourceContributions) ?? [:]
            let oldDay = sourceDays[sourceID]
            let newDay = incoming[sourceID].map { calendar.startOfDay(for: $0.date) }
            for id in Set(old.keys).union(new.keys) {
                if old[id] != new[id] || oldDay != newDay { changedPlaces.insert(id) }
            }
            for id in old.keys {
                placeSourceIDs[id]?.remove(sourceID)
                if placeSourceIDs[id]?.isEmpty == true { placeSourceIDs.removeValue(forKey: id) }
            }
            for id in new.keys { placeSourceIDs[id, default: []].insert(sourceID) }
            if let source = incoming[sourceID] {
                sourcesByID[sourceID] = source
                sourceDays[sourceID] = newDay
                contributionsBySource[sourceID] = new
            } else {
                sourcesByID.removeValue(forKey: sourceID)
                sourceDays.removeValue(forKey: sourceID)
                contributionsBySource.removeValue(forKey: sourceID)
            }
        }
        return changedPlaces
    }

    private func rebuildPlace(_ id: String) {
        if let old = aggregates.removeValue(forKey: id) {
            for name in old.allTags {
                let key = ReviewMapCacheIdentity.normalizedName(name)
                tagPlaceIDs[key]?.remove(id)
                if tagPlaceIDs[key]?.isEmpty == true { tagPlaceIDs.removeValue(forKey: key) }
            }
        }
        let sourceIDs = (placeSourceIDs[id] ?? []).sorted {
            let left = sourceDays[$0] ?? .distantPast
            let right = sourceDays[$1] ?? .distantPast
            if left != right { return left > right }
            return $0.uuidString < $1.uuidString
        }
        var location: ReviewMapLocationSource?
        var days: [Date: MutableVisit] = [:]
        for sourceID in sourceIDs {
            guard let date = sourceDays[sourceID],
                  let contributions = contributionsBySource[sourceID]?[id] else { continue }
            if location == nil { location = contributions.first }
            var visit = days[date] ?? MutableVisit()
            for contribution in contributions {
                for path in contribution.photoPaths where visit.photoSet.insert(path).inserted {
                    visit.photoPaths.append(path)
                }
                for rawName in contribution.visitTags {
                    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let key = ReviewMapCacheIdentity.normalizedName(name)
                    guard !key.isEmpty, visit.tagKeys.insert(key).inserted else { continue }
                    visit.tags.append(name)
                }
            }
            days[date] = visit
        }
        guard let location else { return }
        let visits = days.keys.sorted(by: >).map { date in
            let visit = days[date]!
            return ReviewMapVisitSnapshot(date: date, photoPaths: visit.photoPaths, tags: visit.tags)
        }
        let aggregate = Aggregate(id: id, location: location, visits: visits, allTags: tagNames(in: visits))
        aggregates[id] = aggregate
        indexTags(for: aggregate)
    }

    private func indexTags(for aggregate: Aggregate) {
        for name in aggregate.allTags {
            tagPlaceIDs[ReviewMapCacheIdentity.normalizedName(name), default: []].insert(aggregate.id)
        }
    }

    private func periodVisits(_ aggregate: Aggregate, query: ReviewMapQuery) -> [ReviewMapVisitSnapshot] {
        guard query.monthStart != nil || query.monthEnd != nil else { return aggregate.visits }
        return aggregate.visits.filter { visit in
            (query.monthStart.map { visit.date >= $0 } ?? true) &&
                (query.monthEnd.map { visit.date < $0 } ?? true)
        }
    }

    private func matchingVisits(_ visits: [ReviewMapVisitSnapshot], filterKeys: Set<String>) -> [ReviewMapVisitSnapshot] {
        guard !filterKeys.isEmpty else { return visits }
        return visits.filter { visit in
            (filterKeys.contains(ReviewMapCacheIdentity.untaggedFilterToken) && visit.tags.isEmpty) ||
                visit.tags.contains { filterKeys.contains(ReviewMapCacheIdentity.normalizedName($0)) }
        }
    }

    private func buildQuery(_ query: ReviewMapQuery, lastAccess: UInt64) -> CachedQuery {
        let filterKeys = Set(query.filterKeys)
        var places: [ReviewMapPlaceSnapshot] = []
        var periodPlaces: [String: PeriodMetadata] = [:]
        for aggregate in aggregates.values {
            let visits = periodVisits(aggregate, query: query)
            guard let latestDate = visits.first?.date else { continue }
            periodPlaces[aggregate.id] = PeriodMetadata(latestDate: latestDate, tags: tagNames(in: visits))
            let matched = matchingVisits(visits, filterKeys: filterKeys)
            if !matched.isEmpty { places.append(render(aggregate, visits: matched, filterKeys: filterKeys)) }
        }
        places.sort(by: placePrecedes)
        return CachedQuery(snapshot: makeSnapshot(query: query, places: places, periodPlaces: periodPlaces),
                           periodPlaces: periodPlaces, lastAccess: lastAccess)
    }

    private func patch(_ cached: CachedQuery, changedPlaceIDs: Set<String>) -> CachedQuery {
        let query = cached.snapshot.query
        let filterKeys = Set(query.filterKeys)
        var places: [String: ReviewMapPlaceSnapshot] = [:]
        for place in cached.snapshot.places { places[place.id] = place }
        var periodPlaces = cached.periodPlaces
        for id in changedPlaceIDs.sorted() {
            guard let aggregate = aggregates[id] else {
                if places.removeValue(forKey: id) != nil { lastRenderedPlaceIDs.insert(id) }
                periodPlaces.removeValue(forKey: id)
                continue
            }
            let visits = periodVisits(aggregate, query: query)
            if let latestDate = visits.first?.date {
                periodPlaces[id] = PeriodMetadata(latestDate: latestDate, tags: tagNames(in: visits))
            } else {
                periodPlaces.removeValue(forKey: id)
            }
            let matched = matchingVisits(visits, filterKeys: filterKeys)
            if !matched.isEmpty {
                places[id] = render(aggregate, visits: matched, filterKeys: filterKeys)
            } else if places.removeValue(forKey: id) != nil {
                lastRenderedPlaceIDs.insert(id)
            }
        }
        let ordered = places.values.sorted(by: placePrecedes)
        return CachedQuery(snapshot: makeSnapshot(query: query, places: ordered, periodPlaces: periodPlaces),
                           periodPlaces: periodPlaces, lastAccess: cached.lastAccess)
    }

    private func render(_ aggregate: Aggregate, visits: [ReviewMapVisitSnapshot],
                        filterKeys: Set<String>) -> ReviewMapPlaceSnapshot {
        lastRenderedPlaceIDs.insert(aggregate.id)
        let count = visits.count
        let allTags = tagNames(in: visits)
        let summary = dateSummary(visits.map(\.date))
        let countText = environment.map {
            String(format: $0.visitCountFormat, locale: Locale(identifier: $0.localeIdentifier), Int64(count))
        } ?? String(count)
        var frequency: [String: Int] = [:]
        for visit in visits {
            var seen: Set<String> = []
            for name in visit.tags {
                let key = ReviewMapCacheIdentity.normalizedName(name)
                guard filterKeys.isEmpty || filterKeys.contains(key), seen.insert(key).inserted else { continue }
                frequency[key, default: 0] += 1
            }
        }
        let ranked = frequency.keys.sorted {
            let left = frequency[$0, default: 0]
            let right = frequency[$1, default: 0]
            if left != right { return left > right }
            return tagLookup.precedes($0, $1)
        }
        let expandedNames = ranked.prefix(9).sorted(by: tagLookup.precedes)
        let displayTags = allTags.map { tagLookup.displayName(for: $0) }
        let expandedColors = expandedNames.map { tagLookup.colorHex(forKey: $0) }
        return ReviewMapPlaceSnapshot(
            id: aggregate.id, location: aggregate.location, visits: visits,
            count: count, latestDate: visits.first?.date ?? .distantPast,
            dateSummary: summary, dateLabelText: count > 1 ? summary + " · " + countText : summary,
            allTags: allTags, listTagText: displayTags.prefix(3).joined(separator: " / "),
            accessibilityText: summary + " · " + countText + " · " + displayTags.joined(separator: ", "),
            compactColorHex: ranked.first.map { tagLookup.colorHex(forKey: $0) } ?? ReviewMapCacheIdentity.untaggedColorHex,
            expandedColorHexes: expandedColors.isEmpty ? [ReviewMapCacheIdentity.untaggedColorHex] : expandedColors
        )
    }

    private func tagNames(in visits: [ReviewMapVisitSnapshot]) -> [String] {
        var seen: Set<String> = []
        var names: [String] = []
        for visit in visits {
            for name in visit.tags where seen.insert(ReviewMapCacheIdentity.normalizedName(name)).inserted {
                names.append(name)
            }
        }
        return names
    }

    private func dateSummary(_ dates: [Date]) -> String {
        guard let first = dates.first, let formatter = monthDayFormatter,
              let calendar = environment?.calendar else { return "" }
        if dates.count == 1 { return formatter.string(from: first) }
        let sameMonth = dates.allSatisfy { calendar.isDate($0, equalTo: first, toGranularity: .month) }
        if sameMonth {
            let days = dates.dropFirst().prefix(2).map { String(calendar.component(.day, from: $0)) }
            let shown = ([formatter.string(from: first)] + days).joined(separator: ",")
            return dates.count > 3 ? shown + "+\(dates.count - 3)" : shown
        }
        let shown = dates.prefix(2).map { formatter.string(from: $0) }.joined(separator: ",")
        return dates.count > 2 ? shown + "+\(dates.count - 2)" : shown
    }

    private func makeSnapshot(query: ReviewMapQuery, places: [ReviewMapPlaceSnapshot],
                              periodPlaces: [String: PeriodMetadata]) -> ReviewMapSnapshot {
        var available = tagLookup.orderedNames
        var seen = Set(available.map(ReviewMapCacheIdentity.normalizedName))
        let orderedPeriodIDs = periodPlaces.keys.sorted {
            let left = periodPlaces[$0]?.latestDate ?? .distantPast
            let right = periodPlaces[$1]?.latestDate ?? .distantPast
            if left != right { return left > right }
            return $0 < $1
        }
        for id in orderedPeriodIDs {
            for name in periodPlaces[id]?.tags ?? [] where seen.insert(ReviewMapCacheIdentity.normalizedName(name)).inserted {
                available.append(name)
            }
        }
        return ReviewMapSnapshot(query: query, places: places, availableTagNames: available,
                                 region: region(for: places), unfilteredPlaceCount: periodPlaces.count)
    }

    private func region(for places: [ReviewMapPlaceSnapshot]) -> ReviewMapRegion? {
        guard let first = places.first else { return nil }
        var minLatitude = first.location.latitude
        var maxLatitude = minLatitude
        var minLongitude = first.location.longitude
        var maxLongitude = minLongitude
        for place in places.dropFirst() {
            minLatitude = min(minLatitude, place.location.latitude)
            maxLatitude = max(maxLatitude, place.location.latitude)
            minLongitude = min(minLongitude, place.location.longitude)
            maxLongitude = max(maxLongitude, place.location.longitude)
        }
        return ReviewMapRegion(centerLatitude: (minLatitude + maxLatitude) / 2,
                               centerLongitude: (minLongitude + maxLongitude) / 2,
                               latitudeDelta: max(0.05, (maxLatitude - minLatitude) * 1.4),
                               longitudeDelta: max(0.05, (maxLongitude - minLongitude) * 1.4))
    }

    private func placePrecedes(_ left: ReviewMapPlaceSnapshot, _ right: ReviewMapPlaceSnapshot) -> Bool {
        if left.latestDate != right.latestDate { return left.latestDate > right.latestDate }
        return left.id < right.id
    }

    private func evictOldQueries() {
        while queries.count > Self.queryLimit {
            guard let oldest = queries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key else { return }
            queries.removeValue(forKey: oldest)
        }
    }

    private func schedulePersistence() {
        guard fileURL != nil, needsPersistence else { return }
        writeGeneration &+= 1
        let generation = writeGeneration
        pendingWriteTask?.cancel()
        pendingWriteTask = _Concurrency.Task { [weak self] in
            do { try await _Concurrency.Task.sleep(for: .milliseconds(350)) }
            catch { return }
            guard !_Concurrency.Task.isCancelled else { return }
            await self?.performScheduledWrite(generation: generation)
        }
    }

    private func performScheduledWrite(generation: UInt64) {
        guard generation == writeGeneration else { return }
        pendingWriteTask = nil
        persistIfNeeded()
    }

    private func persistIfNeeded() {
        guard needsPersistence, let fileURL, let environment else { return }
        let envelope = Envelope(
            schemaVersion: Self.schemaVersion, environment: environment,
            sources: sourcesByID.values.sorted { $0.id.uuidString < $1.id.uuidString },
            tags: tagsByID.values.sorted { $0.id.uuidString < $1.id.uuidString },
            aggregates: aggregates.values.sorted { $0.id < $1.id },
            queries: queries.values.sorted { $0.lastAccess < $1.lastAccess }
        )
        do {
            let data = try JSONEncoder().encode(envelope)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            needsPersistence = false
            persistentWriteCount += 1
        } catch {
            // A disposable cache failure never changes or blocks the diary's source store.
            needsPersistence = true
        }
    }

    private nonisolated struct MutableVisit {
        var photoPaths: [String] = []
        var photoSet: Set<String> = []
        var tags: [String] = []
        var tagKeys: Set<String> = []
    }

    private nonisolated struct Aggregate: Codable, Sendable {
        let id: String
        let location: ReviewMapLocationSource
        let visits: [ReviewMapVisitSnapshot]
        let allTags: [String]
    }

    private nonisolated struct PeriodMetadata: Codable, Sendable {
        let latestDate: Date
        let tags: [String]
    }

    private nonisolated struct CachedQuery: Codable, Sendable {
        let snapshot: ReviewMapSnapshot
        let periodPlaces: [String: PeriodMetadata]
        var lastAccess: UInt64
    }

    private nonisolated struct Envelope: Codable, Sendable {
        let schemaVersion: Int
        let environment: ReviewMapEnvironment
        let sources: [ReviewMapDiarySource]
        let tags: [ReviewMapTagSource]
        let aggregates: [Aggregate]
        let queries: [CachedQuery]
    }

    private nonisolated struct TagLookup {
        var byKey: [String: ReviewMapTagSource] = [:]
        var order: [String: Int] = [:]
        var orderedNames: [String] = []

        init(tags: [ReviewMapTagSource]) {
            let sorted = tags.sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.id.uuidString < $1.id.uuidString
            }
            for tag in sorted {
                let key = ReviewMapCacheIdentity.normalizedName(tag.name)
                guard byKey[key] == nil else { continue }
                var canonical = tag
                canonical.colorHex = ReviewMapCacheIdentity.normalizedColorHex(tag.colorHex)
                byKey[key] = canonical
                order[key] = orderedNames.count
                orderedNames.append(tag.name)
            }
        }

        func precedes(_ left: String, _ right: String) -> Bool {
            let leftOrder = order[left, default: .max]
            let rightOrder = order[right, default: .max]
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            return left < right
        }

        func colorHex(forKey key: String) -> String {
            byKey[key]?.colorHex ?? ReviewMapCacheIdentity.untaggedColorHex
        }

        func displayName(for name: String) -> String {
            byKey[ReviewMapCacheIdentity.normalizedName(name)]?.displayName ?? name
        }
    }
}
