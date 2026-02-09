//
//  DiaryLocationPickerView.swift
//  lifelog
//
//  Created by Codex on 2026/02/02.
//

import SwiftUI
import MapKit
import CoreLocation
import Combine

struct DiaryLocationPickerView: View {
    @Binding private var isPresented: Bool
    @StateObject private var viewModel: DiaryLocationPickerViewModel
    @State private var showSavedLocationsOnMap: Bool = false
    @State private var pendingMapSelection: DiaryLocation?
    @State private var pendingCustomLocation: EditableLocationDraft?
    @State private var customLocationName: String = ""
    @State private var isSearchSectionExpanded: Bool = true
    @State private var isCenterSectionExpanded: Bool = true
    @State private var isNearbySectionExpanded: Bool = true
    @State private var isRecentSectionExpanded: Bool = true
    @FocusState private var isSearchFocused: Bool

    private let onSelect: (DiaryLocation) -> Void

    init(isPresented: Binding<Bool>,
         initialCoordinate: CLLocationCoordinate2D,
         pastEntries: [DiaryEntry] = [],
         onSelect: @escaping (DiaryLocation) -> Void) {
        _isPresented = isPresented
        _viewModel = StateObject(wrappedValue: DiaryLocationPickerViewModel(centerCoordinate: initialCoordinate,
                                                                            pastEntries: pastEntries))
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                DiaryLocationMapView(region: viewModel.mapRegion,
                                     mapCommandID: viewModel.mapCommandID,
                                     savedLocations: viewModel.visibleSavedLocations,
                                     showSavedLocations: showSavedLocationsOnMap,
                                     onRegionDidChange: { region in
                                         viewModel.updateRegion(region)
                                     },
                                     onSelectMapItem: { mapItem in
                                         requestMapSelectionConfirmation(DiaryLocation(mapItem: mapItem))
                                     },
                                     onSelectSavedLocation: { location in
                                         requestMapSelectionConfirmation(location.location)
                                     })
                .overlay(alignment: .topTrailing) {
                    if viewModel.canSearchThisArea {
                        Button("このエリアを検索") {
                            viewModel.searchPlaces()
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                        .padding(.trailing, 12)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if viewModel.savedLocations.isEmpty == false {
                        Button {
                            showSavedLocationsOnMap.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: showSavedLocationsOnMap ? "clock.arrow.circlepath" : "clock")
                                Text(showSavedLocationsOnMap ? "過去の登録地点 ON" : "過去の登録地点 OFF")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                        }
                        .padding(.top, 8)
                        .padding(.leading, 12)
                    }
                }
                .overlay {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottom) {
                    Button {
                        presentNameEditorForCenter()
                    } label: {
                        Label("中央を登録", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.bottom, 10)
                }
                .frame(height: 280)

                HStack {
                    Text("候補リスト")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                List {
                    if viewModel.shouldShowSearchResults {
                        Section {
                            if isSearchSectionExpanded {
                                if viewModel.isSearching {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                        Spacer()
                                    }
                                } else if viewModel.searchResults.isEmpty {
                                    Text("検索結果が見つかりませんでした")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(viewModel.searchResults) { place in
                                    PlaceResultRow(place: place,
                                                   onMove: {
                                                       viewModel.focus(on: place.coordinate)
                                                   },
                                                   onAdd: {
                                                       addAndDismiss(DiaryLocation(mapItem: place.mapItem))
                                                   })
                                }
                            }
                        } header: {
                            CollapsibleSectionHeader(title: "検索結果",
                                                     isExpanded: $isSearchSectionExpanded)
                        }
                    }

                    Section {
                        if isCenterSectionExpanded {
                            Button {
                                addAndDismiss(viewModel.centerLocation())
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(viewModel.centerLabel ?? "選択した場所")
                                        .font(.body)
                                    Text("この場所を追加")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Button("名前をつけて追加") {
                                presentNameEditorForCenter()
                            }
                            Text("Appleマップに表示されない場所は「名前をつけて追加」で登録できます。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        CollapsibleSectionHeader(title: "中心の場所",
                                                 isExpanded: $isCenterSectionExpanded)
                    }

                    Section {
                        if isNearbySectionExpanded {
                            if viewModel.isLoading {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                    Spacer()
                                }
                            }
                            ForEach(viewModel.nearbyPlaces) { place in
                                PlaceResultRow(place: place,
                                               onMove: {
                                                   viewModel.focus(on: place.coordinate)
                                               },
                                               onAdd: {
                                                   addAndDismiss(DiaryLocation(mapItem: place.mapItem))
                                               })
                            }
                        }
                    } header: {
                        CollapsibleSectionHeader(title: "周辺のスポット",
                                                 isExpanded: $isNearbySectionExpanded)
                    }

                    if viewModel.recentSavedLocations.isEmpty == false {
                        Section {
                            if isRecentSectionExpanded {
                                ForEach(viewModel.recentSavedLocations) { location in
                                    SavedLocationResultRow(location: location,
                                                           onMove: {
                                                               viewModel.focus(on: location.coordinate)
                                                           },
                                                           onAdd: {
                                                               addAndDismiss(location.location)
                                                           })
                                }
                            }
                        } header: {
                            CollapsibleSectionHeader(title: "最近登録した場所",
                                                     isExpanded: $isRecentSectionExpanded)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.never)
            }
            .navigationTitle("場所を選ぶ")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        isPresented = false
                    }
                }
            }
            .onAppear {
                viewModel.requestCurrentLocationIfNeeded()
            }
            .sheet(item: $pendingMapSelection) { location in
                MapSelectionConfirmSheet(location: location,
                                         onCancel: {
                                             pendingMapSelection = nil
                                         },
                                         onAdd: { selectedLocation in
                                             pendingMapSelection = nil
                                             addAndDismiss(selectedLocation)
                                         })
                .presentationDetents([.height(300), .medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $pendingCustomLocation) { draft in
                NavigationStack {
                    Form {
                        Section("場所名") {
                            TextField("場所名を入力", text: $customLocationName)
                        }
                        if let address = draft.address, address.isEmpty == false {
                            Section("住所") {
                                Text(address)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .navigationTitle("場所名を設定")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("キャンセル") {
                                pendingCustomLocation = nil
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("追加") {
                                let trimmed = customLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
                                let finalName = trimmed.isEmpty ? draft.initialName : trimmed
                                addAndDismiss(DiaryLocation(name: finalName,
                                                            address: draft.address,
                                                            latitude: draft.coordinate.latitude,
                                                            longitude: draft.coordinate.longitude,
                                                            mapItemURL: draft.mapItemURL,
                                                            photoPaths: []))
                                pendingCustomLocation = nil
                            }
                        }
                    }
                }
            }
        }
    }

    private func addAndDismiss(_ location: DiaryLocation) {
        onSelect(DiaryLocation(name: location.name,
                               address: location.address,
                               latitude: location.latitude,
                               longitude: location.longitude,
                               mapItemURL: location.mapItemURL,
                               photoPaths: []))
        isPresented = false
    }

    private func presentNameEditorForCenter() {
        let initialName = viewModel.centerLabel ?? "選択した場所"
        let address = viewModel.centerLabel
        pendingCustomLocation = EditableLocationDraft(coordinate: viewModel.centerCoordinate,
                                                      address: address,
                                                      mapItemURL: nil,
                                                      initialName: initialName)
        customLocationName = initialName
    }

    private func requestMapSelectionConfirmation(_ location: DiaryLocation) {
        pendingMapSelection = location
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("場所を検索", text: $viewModel.searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .focused($isSearchFocused)
                .onSubmit {
                    viewModel.searchPlaces()
                    isSearchFocused = false
                }
                .onChange(of: viewModel.searchText) { _, _ in
                    viewModel.searchTextDidChange()
                }
            if viewModel.searchText.isEmpty == false {
                Button {
                    viewModel.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Button("検索") {
                viewModel.searchPlaces()
                isSearchFocused = false
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

private struct EditableLocationDraft: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let address: String?
    let mapItemURL: String?
    let initialName: String
}

private struct MapSelectionConfirmSheet: View {
    let location: DiaryLocation
    let onCancel: () -> Void
    let onAdd: (DiaryLocation) -> Void

    private var addressText: String {
        let trimmed = location.address?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed! : "住所情報なし"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("この場所を追加しますか？")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text(location.name)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(addressText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("緯度 \(String(format: "%.5f", location.latitude)) / 経度 \(String(format: "%.5f", location.longitude))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button("キャンセル", action: onCancel)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Button("追加") {
                    onAdd(location)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
    }
}

@MainActor
private final class DiaryLocationPickerViewModel: NSObject, ObservableObject {
    @Published private(set) var nearbyPlaces: [NearbyPlace] = []
    @Published private(set) var savedLocations: [SavedDiaryLocation] = []
    @Published private(set) var centerLabel: String?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var centerCoordinate: CLLocationCoordinate2D
    @Published private(set) var mapRegion: MKCoordinateRegion
    @Published private(set) var mapCommandID: Int = 0
    @Published var searchText: String = ""
    @Published private(set) var searchResults: [NearbyPlace] = []
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var isSearchAreaDirty: Bool = false
    @Published private(set) var hasSearched: Bool = false

    private var searchTask: _Concurrency.Task<Void, Never>?
    private var queryTask: _Concurrency.Task<Void, Never>?
    private let geocoder = CLGeocoder()
    private let locationManager = CLLocationManager()
    private let mapSavedLocationLimit = 80
    private let recentSavedLocationLimit = 10
    private let refreshMinimumDistance: CLLocationDistance = 40
    private var lastLoadedCoordinate: CLLocationCoordinate2D?
    private var hasRequestedCurrentLocation = false
    private var hasAppliedCurrentLocation = false

    init(centerCoordinate: CLLocationCoordinate2D,
         pastEntries: [DiaryEntry]) {
        self.centerCoordinate = centerCoordinate
        self.savedLocations = Self.buildSavedLocations(from: pastEntries)
        let region = MKCoordinateRegion(center: centerCoordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.02,
                                                               longitudeDelta: 0.02))
        mapRegion = region
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        updateCenter(centerCoordinate)
    }

    func requestCurrentLocationIfNeeded() {
        guard hasRequestedCurrentLocation == false else { return }
        hasRequestedCurrentLocation = true
        if let currentCoordinate = locationManager.location?.coordinate {
            applyInitialCurrentLocation(currentCoordinate)
            return
        }
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            break
        @unknown default:
            break
        }
    }

    func updateCenter(_ coordinate: CLLocationCoordinate2D) {
        centerCoordinate = coordinate
        guard shouldRefreshMapMetadata(for: coordinate) else {
            return
        }
        searchTask?.cancel()
        searchTask = _Concurrency.Task { [weak self] in
            try? await _Concurrency.Task.sleep(nanoseconds: 350_000_000)
            await self?.loadCenterLabel(for: coordinate)
            await self?.loadNearbyPlaces(for: coordinate)
            await MainActor.run {
                self?.lastLoadedCoordinate = coordinate
            }
        }
    }

    func updateRegion(_ region: MKCoordinateRegion) {
        mapRegion = region
        updateCenter(region.center)
        if hasSearched && searchText.isEmpty == false {
            isSearchAreaDirty = true
        }
    }

    func centerLocation() -> DiaryLocation {
        let label = centerLabel ?? "選択した場所"
        return DiaryLocation(name: label,
                             address: centerLabel,
                             latitude: centerCoordinate.latitude,
                             longitude: centerCoordinate.longitude,
                             mapItemURL: nil,
                             photoPaths: [])
    }

    func focus(on coordinate: CLLocationCoordinate2D) {
        let region = MKCoordinateRegion(center: coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.01,
                                                               longitudeDelta: 0.01))
        mapRegion = region
        mapCommandID &+= 1
        updateCenter(region.center)
    }

    var shouldShowSearchResults: Bool {
        isSearching || hasSearched
    }

    func clearSearch() {
        searchText = ""
        searchResults = []
        queryTask?.cancel()
        queryTask = nil
        hasSearched = false
        isSearchAreaDirty = false
    }

    func searchTextDidChange() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearSearch()
        } else {
            hasSearched = false
            isSearchAreaDirty = false
            searchResults = []
        }
    }

    var canSearchThisArea: Bool {
        searchText.isEmpty == false && hasSearched && isSearchAreaDirty
    }

    var recentSavedLocations: [SavedDiaryLocation] {
        Array(savedLocations.prefix(recentSavedLocationLimit))
    }

    var visibleSavedLocations: [SavedDiaryLocation] {
        let visible = savedLocations
            .filter { mapRegion.contains($0.coordinate) }
            .sorted { lhs, rhs in
                distance(from: centerCoordinate, to: lhs.coordinate) < distance(from: centerCoordinate, to: rhs.coordinate)
            }
        return Array(visible.prefix(mapSavedLocationLimit))
    }

    func searchPlaces() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            clearSearch()
            return
        }
        queryTask?.cancel()
        isSearching = true
        isSearchAreaDirty = false
        let region = mapRegion
        queryTask = _Concurrency.Task { [weak self] in
            guard let self else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = region
            request.resultTypes = .pointOfInterest
            do {
                let response = try await performSearch(request)
                let items = response.mapItems
                await MainActor.run {
                    self.searchResults = self.deduplicatedPlaces(from: items.map { NearbyPlace(mapItem: $0) })
                    self.isSearching = false
                    self.hasSearched = true
                    self.isSearchAreaDirty = false
                }
            } catch {
                await MainActor.run {
                    self.searchResults = []
                    self.isSearching = false
                    self.hasSearched = true
                    self.isSearchAreaDirty = false
                }
            }
        }
    }

    private func loadNearbyPlaces(for coordinate: CLLocationCoordinate2D) async {
        isLoading = true
        let region = MKCoordinateRegion(center: coordinate,
                                        latitudinalMeters: 800,
                                        longitudinalMeters: 800)
        let request = MKLocalPointsOfInterestRequest(coordinateRegion: region)
        request.pointOfInterestFilter = .includingAll
        do {
            let response = try await performSearch(request)
            let items = response.mapItems
            nearbyPlaces = deduplicatedPlaces(from: items.map { NearbyPlace(mapItem: $0) })
        } catch {
            nearbyPlaces = []
        }
        isLoading = false
    }

    private func loadCenterLabel(for coordinate: CLLocationCoordinate2D) async {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            centerLabel = placemarks.first.flatMap { placemark in
                [placemark.administrativeArea,
                 placemark.locality,
                 placemark.thoroughfare,
                 placemark.subThoroughfare]
                    .compactMap { $0 }
                    .joined()
            }
        } catch {
            centerLabel = nil
        }
    }

    private func deduplicatedPlaces(from places: [NearbyPlace]) -> [NearbyPlace] {
        var seenKeys: Set<String> = []
        var deduplicated: [NearbyPlace] = []
        for place in places {
            let coordinate = place.coordinate
            let key = "\(place.name)|\(coordinate.latitude)|\(coordinate.longitude)"
            if seenKeys.contains(key) {
                continue
            }
            seenKeys.insert(key)
            deduplicated.append(place)
        }
        return deduplicated
    }

    private func distance(from source: CLLocationCoordinate2D,
                          to destination: CLLocationCoordinate2D) -> CLLocationDistance {
        let sourceLocation = CLLocation(latitude: source.latitude,
                                        longitude: source.longitude)
        let destinationLocation = CLLocation(latitude: destination.latitude,
                                             longitude: destination.longitude)
        return sourceLocation.distance(from: destinationLocation)
    }

    private func shouldRefreshMapMetadata(for coordinate: CLLocationCoordinate2D) -> Bool {
        guard let lastLoadedCoordinate else { return true }
        if nearbyPlaces.isEmpty || centerLabel == nil {
            return true
        }
        return distance(from: lastLoadedCoordinate, to: coordinate) >= refreshMinimumDistance
    }

    private func applyInitialCurrentLocation(_ coordinate: CLLocationCoordinate2D) {
        guard hasAppliedCurrentLocation == false else { return }
        hasAppliedCurrentLocation = true
        focus(on: coordinate)
    }

    private static func buildSavedLocations(from entries: [DiaryEntry]) -> [SavedDiaryLocation] {
        struct AggregatedLocation {
            var location: DiaryLocation
            var latestDate: Date
            var visitCount: Int
        }

        var byKey: [String: AggregatedLocation] = [:]
        for entry in entries {
            for location in entry.locations {
                let key = SavedDiaryLocation.key(for: location)
                if var existing = byKey[key] {
                    existing.visitCount += 1
                    if entry.date > existing.latestDate {
                        existing.latestDate = entry.date
                        existing.location = location
                    }
                    byKey[key] = existing
                } else {
                    byKey[key] = AggregatedLocation(location: location,
                                                    latestDate: entry.date,
                                                    visitCount: 1)
                }
            }
        }

        return byKey.map { key, value in
            SavedDiaryLocation(id: key,
                               location: value.location,
                               lastVisitedDate: value.latestDate,
                               visitCount: value.visitCount)
        }
        .sorted { lhs, rhs in
            lhs.lastVisitedDate > rhs.lastVisitedDate
        }
    }

    private func performSearch(_ request: MKLocalSearch.Request) async throws -> MKLocalSearch.Response {
        try await withCheckedThrowingContinuation { continuation in
            let search = MKLocalSearch(request: request)
            search.start { response, error in
                if let response {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "MapSearch", code: 1))
                }
            }
        }
    }

    private func performSearch(_ request: MKLocalPointsOfInterestRequest) async throws -> MKLocalSearch.Response {
        try await withCheckedThrowingContinuation { continuation in
            let search = MKLocalSearch(request: request)
            search.start { response, error in
                if let response {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "MapSearch", code: 2))
                }
            }
        }
    }
}

extension DiaryLocationPickerViewModel: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didChangeAuthorization status: CLAuthorizationStatus) {
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            return
        }
        manager.requestLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        _Concurrency.Task { [weak self] in
            await self?.applyInitialCurrentLocation(coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // Keep seeded region when current location is unavailable.
    }
}

private struct DiaryLocationMapView: UIViewRepresentable {
    let region: MKCoordinateRegion
    let mapCommandID: Int
    let savedLocations: [SavedDiaryLocation]
    let showSavedLocations: Bool
    let onRegionDidChange: (MKCoordinateRegion) -> Void
    let onSelectMapItem: (MKMapItem) -> Void
    let onSelectSavedLocation: (SavedDiaryLocation) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.selectableMapFeatures = .pointsOfInterest

        let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
        configuration.pointOfInterestFilter = .includingAll
        mapView.preferredConfiguration = configuration

        mapView.setRegion(region, animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onRegionDidChange = onRegionDidChange
        context.coordinator.onSelectMapItem = onSelectMapItem
        context.coordinator.onSelectSavedLocation = onSelectSavedLocation
        context.coordinator.syncSavedLocationAnnotations(on: mapView,
                                                         locations: showSavedLocations ? savedLocations : [])
        if context.coordinator.lastAppliedMapCommandID != mapCommandID {
            context.coordinator.lastAppliedMapCommandID = mapCommandID
            context.coordinator.pendingProgrammaticRegion = region
            mapView.setRegion(region, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onRegionDidChange: onRegionDidChange,
                    onSelectMapItem: onSelectMapItem,
                    onSelectSavedLocation: onSelectSavedLocation)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onRegionDidChange: (MKCoordinateRegion) -> Void
        var onSelectMapItem: (MKMapItem) -> Void
        var onSelectSavedLocation: (SavedDiaryLocation) -> Void
        var pendingProgrammaticRegion: MKCoordinateRegion?
        var lastAppliedMapCommandID: Int = -1
        private var savedLocationAnnotationsByID: [String: SavedLocationAnnotation] = [:]

        init(onRegionDidChange: @escaping (MKCoordinateRegion) -> Void,
             onSelectMapItem: @escaping (MKMapItem) -> Void,
             onSelectSavedLocation: @escaping (SavedDiaryLocation) -> Void) {
            self.onRegionDidChange = onRegionDidChange
            self.onSelectMapItem = onSelectMapItem
            self.onSelectSavedLocation = onSelectSavedLocation
        }

        func syncSavedLocationAnnotations(on mapView: MKMapView,
                                          locations: [SavedDiaryLocation]) {
            let nextIDs = Set(locations.map(\.id))
            let staleIDs = savedLocationAnnotationsByID.keys.filter { nextIDs.contains($0) == false }
            for id in staleIDs {
                if let annotation = savedLocationAnnotationsByID.removeValue(forKey: id) {
                    mapView.removeAnnotation(annotation)
                }
            }
            for location in locations {
                if let existing = savedLocationAnnotationsByID[location.id] {
                    existing.update(with: location)
                } else {
                    let annotation = SavedLocationAnnotation(location: location)
                    savedLocationAnnotationsByID[location.id] = annotation
                    mapView.addAnnotation(annotation)
                }
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if let pendingRegion = pendingProgrammaticRegion,
               mapView.region.isApproximatelyEqual(to: pendingRegion) {
                pendingProgrammaticRegion = nil
                return
            }
            onRegionDidChange(mapView.region)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let savedAnnotation = annotation as? SavedLocationAnnotation else {
                return nil
            }
            let reuseIdentifier = "SavedLocationAnnotationView"
            let view: SavedLocationAnnotationView
            if let dequeued = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) as? SavedLocationAnnotationView {
                view = dequeued
                view.annotation = savedAnnotation
            } else {
                view = SavedLocationAnnotationView(annotation: savedAnnotation,
                                                  reuseIdentifier: reuseIdentifier)
            }
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let savedAnnotation = annotation as? SavedLocationAnnotation {
                onSelectSavedLocation(savedAnnotation.location)
                mapView.deselectAnnotation(savedAnnotation, animated: false)
                return
            }
            guard let featureAnnotation = annotation as? MKMapFeatureAnnotation else {
                return
            }
            let request = MKMapItemRequest(mapFeatureAnnotation: featureAnnotation)
            _Concurrency.Task { [weak self] in
                guard let self else { return }
                do {
                    let mapItem = try await request.mapItem
                    await MainActor.run {
                        self.onSelectMapItem(mapItem)
                    }
                } catch {
                    // Ignore selection failures from non-resolvable features.
                }
            }
        }
    }

    private final class SavedLocationAnnotation: NSObject, MKAnnotation {
        var location: SavedDiaryLocation
        @objc dynamic var coordinate: CLLocationCoordinate2D
        var title: String? {
            location.location.name
        }
        var subtitle: String? {
            location.location.address
        }

        init(location: SavedDiaryLocation) {
            self.location = location
            self.coordinate = location.coordinate
            super.init()
        }

        func update(with location: SavedDiaryLocation) {
            self.location = location
            coordinate = location.coordinate
        }
    }

    private final class SavedLocationAnnotationView: MKAnnotationView {
        private let iconView = UIImageView()

        override var annotation: MKAnnotation? {
            didSet {
                updateContent()
            }
        }

        override var isSelected: Bool {
            didSet {
                updateSelectionState()
            }
        }

        override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
            super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
            configureAppearance()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func configureAppearance() {
            frame = CGRect(x: 0, y: 0, width: 24, height: 24)
            centerOffset = .zero
            canShowCallout = false
            collisionMode = .circle
            layer.cornerRadius = 12
            layer.borderWidth = 2
            layer.borderColor = UIColor.white.withAlphaComponent(0.95).cgColor
            layer.shadowColor = UIColor.black.withAlphaComponent(0.15).cgColor
            layer.shadowOffset = CGSize(width: 0, height: 1)
            layer.shadowRadius = 3
            layer.shadowOpacity = 1

            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.contentMode = .scaleAspectFit
            iconView.tintColor = .white
            addSubview(iconView)
            NSLayoutConstraint.activate([
                iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 12),
                iconView.heightAnchor.constraint(equalToConstant: 12)
            ])
            updateContent()
            updateSelectionState()
        }

        private func updateContent() {
            guard let savedAnnotation = annotation as? SavedLocationAnnotation else {
                return
            }
            let location = savedAnnotation.location
            iconView.image = UIImage(systemName: symbolName(for: location))
            backgroundColor = markerColor(for: location)
            accessibilityLabel = location.location.name
        }

        private func updateSelectionState() {
            if isSelected {
                transform = CGAffineTransform(scaleX: 1.16, y: 1.16)
                alpha = 1
            } else {
                transform = .identity
                alpha = 0.95
            }
        }

        private func markerColor(for location: SavedDiaryLocation) -> UIColor {
            switch location.visitCount {
            case 10...:
                return UIColor.systemOrange.withAlphaComponent(0.95)
            case 5...:
                return UIColor.systemTeal.withAlphaComponent(0.95)
            default:
                return UIColor.systemBlue.withAlphaComponent(0.92)
            }
        }

        private func symbolName(for location: SavedDiaryLocation) -> String {
            let source = "\(location.location.name) \(location.location.address ?? "")".lowercased()
            if source.contains("駅") || source.contains("station") {
                return "tram.fill"
            }
            if source.contains("カフェ") || source.contains("coffee") || source.contains("喫茶") {
                return "cup.and.saucer.fill"
            }
            if source.contains("公園") || source.contains("park") {
                return "leaf.fill"
            }
            if source.contains("海") || source.contains("beach") {
                return "water.waves"
            }
            if source.contains("学校") || source.contains("campus") {
                return "graduationcap.fill"
            }
            if source.contains("病院") || source.contains("hospital") {
                return "cross.case.fill"
            }
            if source.contains("ホテル") || source.contains("hotel") {
                return "bed.double.fill"
            }
            return "mappin.and.ellipse"
        }
    }
}

private extension MKCoordinateRegion {
    func isApproximatelyEqual(to other: MKCoordinateRegion,
                              centerTolerance: CLLocationDegrees = 0.00005,
                              spanTolerance: CLLocationDegrees = 0.0002) -> Bool {
        abs(center.latitude - other.center.latitude) <= centerTolerance &&
        abs(center.longitude - other.center.longitude) <= centerTolerance &&
        abs(span.latitudeDelta - other.span.latitudeDelta) <= spanTolerance &&
        abs(span.longitudeDelta - other.span.longitudeDelta) <= spanTolerance
    }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let halfLat = span.latitudeDelta / 2
        let halfLon = span.longitudeDelta / 2
        let minLat = center.latitude - halfLat
        let maxLat = center.latitude + halfLat
        let minLon = center.longitude - halfLon
        let maxLon = center.longitude + halfLon
        return coordinate.latitude >= minLat &&
        coordinate.latitude <= maxLat &&
        coordinate.longitude >= minLon &&
        coordinate.longitude <= maxLon
    }
}

private struct CollapsibleSectionHeader: View {
    let title: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SavedLocationResultRow: View {
    let location: SavedDiaryLocation
    let onMove: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(location.location.name)
                    .font(.body)
                if let address = location.location.address, address.isEmpty == false {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("訪問 \(location.visitCount)回")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("追加", action: onAdd)
                .buttonStyle(.bordered)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onMove)
    }
}

private struct PlaceResultRow: View {
    let place: NearbyPlace
    let onMove: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name)
                    .font(.body)
                if let address = place.address, address.isEmpty == false {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("追加", action: onAdd)
                .buttonStyle(.bordered)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onMove)
    }
}

private struct NearbyPlace: Identifiable, Hashable {
    let id = UUID()
    let mapItem: MKMapItem

    static func == (lhs: NearbyPlace, rhs: NearbyPlace) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var name: String {
        mapItem.name ?? "名称不明"
    }

    var coordinate: CLLocationCoordinate2D {
        mapItem.placemark.coordinate
    }

    var address: String? {
        let placemark = mapItem.placemark
        let parts = [placemark.administrativeArea,
                     placemark.locality,
                     placemark.thoroughfare,
                     placemark.subThoroughfare]
        let result = parts.compactMap { $0 }.joined()
        return result.isEmpty ? placemark.title : result
    }
}

private struct SavedDiaryLocation: Identifiable, Hashable {
    let id: String
    let location: DiaryLocation
    let lastVisitedDate: Date
    let visitCount: Int

    var coordinate: CLLocationCoordinate2D {
        location.coordinate
    }

    static func key(for location: DiaryLocation) -> String {
        if let mapItemURL = location.mapItemURL, mapItemURL.isEmpty == false {
            return "mapitem:\(mapItemURL)"
        }
        let lat = (location.latitude * 10_000).rounded() / 10_000
        let lon = (location.longitude * 10_000).rounded() / 10_000
        return "coord:\(lat),\(lon)"
    }
}

private extension DiaryLocation {
    init(mapItem: MKMapItem) {
        let placemark = mapItem.placemark
        let parts = [placemark.administrativeArea,
                     placemark.locality,
                     placemark.thoroughfare,
                     placemark.subThoroughfare]
        let address = parts.compactMap { $0 }.joined()
        self.init(name: mapItem.name ?? "名称不明",
                  address: address.isEmpty ? placemark.title : address,
                  latitude: placemark.coordinate.latitude,
                  longitude: placemark.coordinate.longitude,
                  mapItemURL: mapItem.url?.absoluteString,
                  photoPaths: [])
    }
}
