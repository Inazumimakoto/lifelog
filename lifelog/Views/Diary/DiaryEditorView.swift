//
//  DiaryEditorView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI
import PhotosUI
import MapKit
import _Concurrency

struct DiaryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: DiaryViewModel
    @State private var selection: [PhotosPickerItem] = []
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var selectedPlaceName: String = ""
    @State private var showMapPicker = false

    init(store: AppDataStore, date: Date) {
        _viewModel = StateObject(wrappedValue: DiaryViewModel(store: store, date: date))
    }

    var body: some View {
        Form {
            entrySection
            moodSection
            conditionSection
            locationSection
            photosSection
        }
        .navigationTitle("日記")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完了") { dismiss() }
            }
        }
        .onAppear {
            selectedPlaceName = viewModel.entry.locationName ?? ""
            if let lat = viewModel.entry.latitude,
               let lon = viewModel.entry.longitude {
                selectedCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        }
        .onChange(of: selection) {
            _Concurrency.Task {
                for item in selection {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        viewModel.addPhoto(data: data)
                    }
                }
                selection = []
            }
        }
    }

    private var textBinding: Binding<String> {
        Binding<String>(
            get: { viewModel.entry.text },
            set: { viewModel.update(text: $0) }
        )
    }

    private var moodBinding: Binding<MoodLevel> {
        Binding<MoodLevel>(
            get: { viewModel.entry.mood ?? .neutral },
            set: { viewModel.update(mood: $0) }
        )
    }

    private var conditionBinding: Binding<Int> {
        Binding<Int>(
            get: { viewModel.entry.conditionScore ?? 3 },
            set: { viewModel.update(condition: $0) }
        )
    }

    private var entrySection: some View {
        Section("本文") {
            ZStack(alignment: .topLeading) {
                if viewModel.entry.text.isEmpty {
                    Text("ここに文章を入力")
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                TextEditor(text: textBinding)
                    .frame(minHeight: 200)
            }
            Text("感じたことを自由に書き留めましょう。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var moodSection: some View {
        Section("気分") {
            Picker("気分", selection: moodBinding) {
                ForEach(MoodLevel.allCases) { mood in
                    Text("\(mood.emoji) \(mood.rawValue)")
                        .tag(mood)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var conditionSection: some View {
        Section("体調") {
            Picker("体調", selection: conditionBinding) {
                ForEach(conditionLevels, id: \.value) { level in
                    Text(level.displayText)
                        .tag(level.value)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var locationSection: some View {
        Section("場所") {
            if let coordinate = selectedCoordinate {
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate,
                                                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))))
                    .frame(height: 120)
                    .cornerRadius(12)
            } else {
                Text("訪れた場所を保存しておきましょう。下のボタンからマップを開いて選択できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("場所を入力", text: $selectedPlaceName)
                .onChange(of: selectedPlaceName) {
                    viewModel.update(locationName: selectedPlaceName.isEmpty ? nil : selectedPlaceName,
                                     coordinate: selectedCoordinate)
                }
            Button {
                showMapPicker = true
            } label: {
                Label("マップから選ぶ", systemImage: "mappin.and.ellipse")
            }
        }
        .sheet(isPresented: $showMapPicker) {
            LocationSearchView { item in
                selectedPlaceName = item.name ?? ""
                selectedCoordinate = item.placemark.coordinate
                viewModel.update(locationName: selectedPlaceName,
                                 coordinate: selectedCoordinate)
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var photosSection: some View {
        Section("写真") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Array(viewModel.entry.photoPaths.enumerated()), id: \.offset) { index, path in
                        if let image = PhotoStorage.loadImage(at: path) {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        viewModel.deletePhoto(at: IndexSet(integer: index))
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white)
                                            .background(Circle().fill(Color.black.opacity(0.6)))
                                    }
                                    .offset(x: 8, y: -8)
                                }
                        }
                    }
                    PhotosPicker(selection: $selection, matching: .images) {
                        VStack {
                            Image(systemName: "plus")
                                .font(.title3)
                            Text("追加")
                        }
                        .frame(width: 80, height: 80)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            Text("写真は最大50枚まで追加できます（現在 \(viewModel.entry.photoPaths.count)/50 枚）。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var conditionLevels: [ConditionLevel] {
        [
            ConditionLevel(value: 1, emoji: "😫"),
            ConditionLevel(value: 2, emoji: "😟"),
            ConditionLevel(value: 3, emoji: "😐"),
            ConditionLevel(value: 4, emoji: "🙂"),
            ConditionLevel(value: 5, emoji: "😄")
        ]
    }
}

private struct ConditionLevel {
    let value: Int
    let emoji: String

    var displayText: String {
        "\(emoji) \(value)"
    }
}
