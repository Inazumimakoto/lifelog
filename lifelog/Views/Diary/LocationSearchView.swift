//
//  LocationSearchView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI
import MapKit
import Combine

struct LocationSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = LocationSearchService()

    var onSelect: (MKMapItem) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(service.results, id: \.self) { completion in
                    Button {
                        service.resolve(completion: completion) { item in
                            guard let item else { return }
                            onSelect(item)
                            dismiss()
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(completion.title)
                                .font(.headline)
                            if completion.subtitle.isEmpty == false {
                                Text(completion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $service.query, prompt: "地名や施設を検索")
            .navigationTitle("場所を検索")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

private final class LocationSearchService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query: String = "" {
        didSet {
            completer.queryFragment = query
        }
    }
    @Published var results: [MKLocalSearchCompletion] = []

    private let completer: MKLocalSearchCompleter

    override init() {
        let completer = MKLocalSearchCompleter()
        completer.resultTypes = .pointOfInterest
        self.completer = completer
        super.init()
        completer.delegate = self
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }

    func resolve(completion: MKLocalSearchCompletion, completionHandler: @escaping (MKMapItem?) -> Void) {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            completionHandler(response?.mapItems.first)
        }
    }
}
