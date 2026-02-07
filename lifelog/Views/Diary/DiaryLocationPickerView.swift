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
    @FocusState private var isSearchFocused: Bool

    private let onSelect: (DiaryLocation) -> Void

    init(isPresented: Binding<Bool>,
         initialCoordinate: CLLocationCoordinate2D,
         onSelect: @escaping (DiaryLocation) -> Void) {
        _isPresented = isPresented
        _viewModel = StateObject(wrappedValue: DiaryLocationPickerViewModel(centerCoordinate: initialCoordinate))
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                DiaryLocationMapView(region: viewModel.mapRegion,
                                     onRegionDidChange: { region in
                                         viewModel.updateRegion(region)
                                     },
                                     onSelectMapItem: { mapItem in
                                         onSelect(DiaryLocation(mapItem: mapItem))
                                         isPresented = false
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
                .frame(height: 280)

                List {
                    if viewModel.shouldShowSearchResults {
                        Section("検索結果") {
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
                                                   onSelect(DiaryLocation(mapItem: place.mapItem))
                                                   isPresented = false
                                               })
                            }
                        }
                    }
                    if let centerLabel = viewModel.centerLabel {
                        Section("中心の場所") {
                            Button {
                                onSelect(viewModel.centerLocation())
                                isPresented = false
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(centerLabel)
                                        .font(.body)
                                    Text("この場所を追加")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Section("周辺のスポット") {
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
                                               onSelect(DiaryLocation(mapItem: place.mapItem))
                                               isPresented = false
                                           })
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
        }
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

@MainActor
private final class DiaryLocationPickerViewModel: ObservableObject {
    @Published private(set) var nearbyPlaces: [NearbyPlace] = []
    @Published private(set) var centerLabel: String?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var centerCoordinate: CLLocationCoordinate2D
    @Published private(set) var mapRegion: MKCoordinateRegion
    @Published var searchText: String = ""
    @Published private(set) var searchResults: [NearbyPlace] = []
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var isSearchAreaDirty: Bool = false
    @Published private(set) var hasSearched: Bool = false

    private var searchTask: _Concurrency.Task<Void, Never>?
    private var queryTask: _Concurrency.Task<Void, Never>?
    private let geocoder = CLGeocoder()

    init(centerCoordinate: CLLocationCoordinate2D) {
        self.centerCoordinate = centerCoordinate
        let region = MKCoordinateRegion(center: centerCoordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.02,
                                                               longitudeDelta: 0.02))
        mapRegion = region
        updateCenter(centerCoordinate)
    }

    func updateCenter(_ coordinate: CLLocationCoordinate2D) {
        centerCoordinate = coordinate
        searchTask?.cancel()
        searchTask = _Concurrency.Task { [weak self] in
            try? await _Concurrency.Task.sleep(nanoseconds: 350_000_000)
            await self?.loadCenterLabel(for: coordinate)
            await self?.loadNearbyPlaces(for: coordinate)
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
        updateRegion(region)
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

private struct DiaryLocationMapView: UIViewRepresentable {
    let region: MKCoordinateRegion
    let onRegionDidChange: (MKCoordinateRegion) -> Void
    let onSelectMapItem: (MKMapItem) -> Void

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

        guard mapView.region.isApproximatelyEqual(to: region) == false else {
            return
        }
        context.coordinator.pendingProgrammaticRegion = region
        mapView.setRegion(region, animated: false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onRegionDidChange: onRegionDidChange,
                    onSelectMapItem: onSelectMapItem)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onRegionDidChange: (MKCoordinateRegion) -> Void
        var onSelectMapItem: (MKMapItem) -> Void
        var pendingProgrammaticRegion: MKCoordinateRegion?

        init(onRegionDidChange: @escaping (MKCoordinateRegion) -> Void,
             onSelectMapItem: @escaping (MKMapItem) -> Void) {
            self.onRegionDidChange = onRegionDidChange
            self.onSelectMapItem = onSelectMapItem
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if let pendingRegion = pendingProgrammaticRegion,
               mapView.region.isApproximatelyEqual(to: pendingRegion) {
                pendingProgrammaticRegion = nil
                return
            }
            onRegionDidChange(mapView.region)
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
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
