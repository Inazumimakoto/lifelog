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
    @State private var selectedPlace: NearbyPlace?

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
                Map(position: $viewModel.cameraPosition,
                    interactionModes: .all,
                    selection: $selectedPlace) {
                    ForEach(viewModel.nearbyPlaces) { place in
                        Marker(place.mapItem.name ?? "名称不明",
                               coordinate: place.mapItem.placemark.coordinate)
                            .tag(place)
                    }
                }
                .overlay {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title)
                        .foregroundStyle(.red)
                        .shadow(radius: 2)
                        .allowsHitTesting(false)
                }
                .onChange(of: selectedPlace) { _, newValue in
                    guard let place = newValue else { return }
                    onSelect(DiaryLocation(mapItem: place.mapItem))
                    isPresented = false
                    selectedPlace = nil
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    viewModel.updateCenter(context.region.center)
                }
                .frame(height: 280)

                List {
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
                            Button {
                                onSelect(DiaryLocation(mapItem: place.mapItem))
                                isPresented = false
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(place.mapItem.name ?? "名称不明")
                                        .font(.body)
                                    if let address = place.address, address.isEmpty == false {
                                        Text(address)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
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
}

@MainActor
private final class DiaryLocationPickerViewModel: ObservableObject {
    @Published var cameraPosition: MapCameraPosition
    @Published private(set) var nearbyPlaces: [NearbyPlace] = []
    @Published private(set) var centerLabel: String?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var centerCoordinate: CLLocationCoordinate2D

    private var searchTask: _Concurrency.Task<Void, Never>?
    private let geocoder = CLGeocoder()

    init(centerCoordinate: CLLocationCoordinate2D) {
        self.centerCoordinate = centerCoordinate
        cameraPosition = .region(MKCoordinateRegion(center: centerCoordinate,
                                                    span: MKCoordinateSpan(latitudeDelta: 0.02,
                                                                           longitudeDelta: 0.02)))
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

    func centerLocation() -> DiaryLocation {
        let label = centerLabel ?? "選択した場所"
        return DiaryLocation(name: label,
                             address: centerLabel,
                             latitude: centerCoordinate.latitude,
                             longitude: centerCoordinate.longitude,
                             mapItemURL: nil)
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
            nearbyPlaces = items.map { NearbyPlace(mapItem: $0) }
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

private struct NearbyPlace: Identifiable, Hashable {
    let id = UUID()
    let mapItem: MKMapItem

    static func == (lhs: NearbyPlace, rhs: NearbyPlace) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
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
                  mapItemURL: mapItem.url?.absoluteString)
    }
}
