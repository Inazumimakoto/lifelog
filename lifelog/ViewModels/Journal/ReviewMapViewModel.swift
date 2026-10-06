import Combine
import CryptoKit
import Foundation
import SwiftData

/// Owns map-only subscriptions and derived display state (docs/requirements.md §4.4.2).
/// Calendar, task and health publications never invalidate the persistent map cache.
@MainActor
final class ReviewMapViewModel: ObservableObject {
    private static var nextRequestRevision: UInt64 = 0

    struct DisplayState {
        let snapshot: ReviewMapSnapshot
        let renderedPlaces: [ReviewMapRenderedPlace]
    }

    @Published private(set) var displayState: DisplayState?
    @Published private(set) var tagDefinitions: [LocationVisitTagDefinition]

    private let cache: ReviewMapCacheService
    private var entries: [DiaryEntry]
    private var period: ReviewMapPeriod = .month
    private var anchorDate = Date()
    private var filters: [String] = []
    private var active = false
    private var generation: UInt64 = 0
    private var refreshTask: _Concurrency.Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()
    private var displayStatesByQuery: [ReviewMapQuery: DisplayState] = [:]
    private var displayQueryOrder: [ReviewMapQuery] = []

    init(store: AppDataStore) {
        entries = store.diaryEntries
        tagDefinitions = store.locationVisitTagDefinitions
        cache = ReviewMapCacheRegistry.service(for: store.modelContext)

        store.$diaryEntries.sink { [weak self] entries in
            guard let self else { return }
            self.entries = entries
            self.scheduleRefresh()
        }.store(in: &subscriptions)
        store.$locationVisitTagDefinitions.removeDuplicates().sink { [weak self] definitions in
            guard let self else { return }
            self.tagDefinitions = definitions
            self.scheduleRefresh()
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &subscriptions)
    }

    func activate(period: ReviewMapPeriod, anchorDate: Date) {
        active = true
        self.period = period
        self.anchorDate = anchorDate
        scheduleRefresh()
    }

    func setPeriod(_ period: ReviewMapPeriod, anchorDate: Date) {
        let previousQuery = query()
        self.period = period
        self.anchorDate = anchorDate
        guard query() != previousQuery else { return }
        scheduleRefresh()
    }

    func setFilters(_ filters: [String]) {
        guard self.filters != filters else { return }
        self.filters = filters
        scheduleRefresh()
    }

    func refreshEnvironment() {
        scheduleRefresh()
    }

    func flush() async {
        if let refreshTask { await refreshTask.value }
        await cache.flush()
    }

    private func query() -> ReviewMapQuery {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .month, for: anchorDate)?.start
        let end = start.flatMap { calendar.date(byAdding: .month, value: 1, to: $0) }
        return ReviewMapQuery(monthStart: period == .month ? start : nil,
                              monthEnd: period == .month ? end : nil,
                              selectedFilters: filters)
    }

    private func scheduleRefresh() {
        guard active else { return }
        generation &+= 1
        let requestedGeneration = generation
        refreshTask?.cancel()
        refreshTask = _Concurrency.Task { [weak self] in
            // Coalesce diary/tag publications from one edit, including rename/delete mutations.
            do { try await _Concurrency.Task.sleep(for: .milliseconds(40)) }
            catch { return }
            guard let self, !_Concurrency.Task.isCancelled else { return }
            Self.nextRequestRevision &+= 1
            let requestRevision = Self.nextRequestRevision
            let sources = self.entries.map(ReviewMapDiarySource.init(entry:))
            let tags = self.tagDefinitions.map(ReviewMapTagSource.init(definition:))
            let query = self.query()
            let environment = ReviewMapEnvironment(
                localeIdentifier: Locale.current.identifier,
                calendar: Calendar.current,
                visitCountFormat: String(localized: "%lld回")
            )
            let snapshot = await self.cache.snapshot(sources: sources, tags: tags,
                                                     query: query, environment: environment,
                                                     requestRevision: requestRevision)
            guard !_Concurrency.Task.isCancelled,
                  requestedGeneration == self.generation else { return }
            if self.displayState?.snapshot != snapshot {
                let previousPlaces = self.displayStatesByQuery[snapshot.query]?.renderedPlaces ??
                    self.displayState?.renderedPlaces ?? []
                let previousByID = Dictionary(uniqueKeysWithValues: previousPlaces.map { ($0.id, $0) })
                let rendered = snapshot.places.map { place in
                    if let previous = previousByID[place.id], previous.snapshot == place {
                        return previous
                    }
                    return ReviewMapRenderedPlace(snapshot: place)
                }
                let state = DisplayState(snapshot: snapshot, renderedPlaces: rendered)
                self.displayStatesByQuery[snapshot.query] = state
                self.displayQueryOrder.removeAll { $0 == snapshot.query }
                self.displayQueryOrder.append(snapshot.query)
                while self.displayQueryOrder.count > 8 {
                    self.displayStatesByQuery.removeValue(forKey: self.displayQueryOrder.removeFirst())
                }
                self.displayState = state
            }
            // Prepare the other period after publishing, so switching "month/all" can reuse
            // a saved snapshot as well. No UI or camera state depends on this background result.
            guard !_Concurrency.Task.isCancelled,
                  requestedGeneration == self.generation else { return }
            let month = Calendar.current.dateInterval(of: .month, for: self.anchorDate)
            let alternateQuery = ReviewMapQuery(
                monthStart: self.period == .all ? month?.start : nil,
                monthEnd: self.period == .all ? month?.end : nil,
                selectedFilters: self.filters
            )
            if alternateQuery != query {
                _ = await self.cache.snapshot(sources: sources, tags: tags,
                                              query: alternateQuery, environment: environment,
                                              requestRevision: requestRevision)
            }
        }
    }
}

/// Share one worker per physical store while keeping normal/demo stores in separate cache files.
@MainActor
private enum ReviewMapCacheRegistry {
    private static var services: [URL: ReviewMapCacheService] = [:]

    static func service(for context: ModelContext) -> ReviewMapCacheService {
        guard let configuration = context.container.configurations.first,
              !configuration.isStoredInMemoryOnly,
              let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return ReviewMapCacheService(fileURL: nil)
        }
        let identity = Data(configuration.url.standardizedFileURL.path.utf8)
        let digest = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
        let fileURL = directory.appendingPathComponent("ReviewMap", isDirectory: true)
            .appendingPathComponent(digest + ".json")
        if let existing = services[fileURL] { return existing }
        let service = ReviewMapCacheService(fileURL: fileURL)
        services[fileURL] = service
        return service
    }
}

@MainActor
private extension ReviewMapDiarySource {
    init(entry: DiaryEntry) {
        let locations: [DiaryLocation]
        if entry.locations.isEmpty,
           let name = entry.locationName, !name.isEmpty,
           let latitude = entry.latitude, let longitude = entry.longitude {
            // A deterministic legacy ID avoids treating the same record as new after every launch.
            locations = [DiaryLocation(id: entry.id, name: name, address: nil,
                                       latitude: latitude, longitude: longitude,
                                       mapItemURL: nil)]
        } else {
            locations = entry.locations
        }
        self.init(id: entry.id, date: entry.date, locations: locations.map { location in
            let isLegacyLocation = locations.count == 1 && location.mapItemURL == nil &&
                entry.locationName == location.name && entry.latitude == location.latitude &&
                entry.longitude == location.longitude
            return ReviewMapLocationSource(id: isLegacyLocation ? entry.id : location.id,
                                    name: location.name, address: location.address,
                                    latitude: location.latitude, longitude: location.longitude,
                                    mapItemURL: location.mapItemURL, photoPaths: location.photoPaths,
                                    visitTags: location.visitTags)
        })
    }
}

@MainActor
private extension ReviewMapTagSource {
    init(definition: LocationVisitTagDefinition) {
        self.init(id: definition.id, name: definition.name,
                  displayName: BuiltInDisplayName.locationVisitTag(definition.name),
                  sortOrder: definition.sortOrder, colorHex: definition.colorHex)
    }
}
