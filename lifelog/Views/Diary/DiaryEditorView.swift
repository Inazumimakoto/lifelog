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
    @ObservedObject private var tagManager = EmotionTagManager.shared
    @State private var selection: [PhotosPickerItem] = []
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var selectedPlaceName: String = ""
    @State private var showMapPicker = false
    @State private var selectedPhotoIndex: Int = 0
    @State private var isShowingPhotoViewer = false
    @State private var showTagManager = false
    @State private var isTagSectionExpanded = false
    @State private var diaryReminderEnabled: Bool = false
    @State private var diaryReminderTime: Date = Date()

    init(store: AppDataStore, date: Date) {
        _viewModel = StateObject(wrappedValue: DiaryViewModel(store: store, date: date))
    }

    var body: some View {
        Form {
            entrySection
            moodSection
            emotionTagsSection
            conditionSection
            locationSection
            photosSection
        }
        .navigationTitle("日記")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完了") {
                    HapticManager.success()
                    dismiss()
                }
            }
        }
        .onAppear {
            selectedPlaceName = viewModel.entry.locationName ?? ""
            if let lat = viewModel.entry.latitude,
               let lon = viewModel.entry.longitude {
                selectedCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            // 日記リマインダー設定を読み込み
            diaryReminderEnabled = viewModel.store.diaryReminderEnabled
            let calendar = Calendar.current
            diaryReminderTime = calendar.date(bySettingHour: viewModel.store.diaryReminderHour,
                                               minute: viewModel.store.diaryReminderMinute,
                                               second: 0,
                                               of: Date()) ?? Date()
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
        .fullScreenCover(isPresented: $isShowingPhotoViewer) {
            DiaryPhotoViewerView(viewModel: viewModel, initialIndex: selectedPhotoIndex)
        }
        .sheet(isPresented: $showTagManager) {
            EmotionTagManagerView()
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
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                }
                TextEditor(text: textBinding)
                    .font(.body)
                    .frame(minHeight: 220, alignment: .topLeading)
                    .scrollContentBackground(.hidden)
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
    
    private var emotionTagsSection: some View {
        let moodValue = (viewModel.entry.mood ?? .neutral).rawValue
        let availableTags = tagManager.tags(for: moodValue)
        
        return Section {
            DisclosureGroup(isExpanded: $isTagSectionExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    // タグボタン一覧
                    FlowLayout(spacing: 8) {
                        ForEach(availableTags) { tag in
                            let isSelected = viewModel.entry.text.contains(tag.hashTag)
                            Button {
                                toggleTag(tag)
                            } label: {
                                Text(tag.displayText)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground),
                                               in: Capsule())
                                    .foregroundStyle(isSelected ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // タグ管理ボタン
                    Button {
                        showTagManager = true
                    } label: {
                        HStack {
                            Image(systemName: "tag")
                            Text("タグを管理")
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                    }
                }
            } label: {
                Text("感情タグ")
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        } footer: {
            if isTagSectionExpanded {
                Text("タップでタグを本文の末尾に追加/削除します")
            }
        }
    }
    
    private func toggleTag(_ tag: EmotionTag) {
        HapticManager.soft()
        var text = viewModel.entry.text
        if text.contains(tag.hashTag) {
            // タグを削除
            text = text.replacingOccurrences(of: " \(tag.hashTag)", with: "")
            text = text.replacingOccurrences(of: tag.hashTag, with: "")
        } else {
            // タグを追加
            if !text.isEmpty && !text.hasSuffix(" ") && !text.hasSuffix("\n") {
                text += " "
            }
            text += tag.hashTag
        }
        viewModel.update(text: text.trimmingCharacters(in: .whitespaces))
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
                            let isFavorite = viewModel.entry.favoritePhotoPath == path
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .topLeading) {
                                    Button {
                                        viewModel.setFavoritePhoto(at: index)
                                        HapticManager.light()
                                    } label: {
                                        Image(systemName: isFavorite ? "star.fill" : "star")
                                            .font(.caption)
                                            .foregroundStyle(isFavorite ? Color.yellow : Color.white)
                                            .padding(6)
                                            .background(.black.opacity(0.5), in: Circle())
                                            .symbolEffect(.bounce, value: isFavorite)
                                    }
                                    .offset(x: -8, y: -8)
                                    .buttonStyle(.plain)
                                }
                                .onTapGesture {
                                    selectedPhotoIndex = index
                                    isShowingPhotoViewer = true
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
            Text("写真は最大\(DiaryViewModel.maxPhotos)枚まで追加できます。⭐️で「今日の一枚」をえらびましょう。現在 \(viewModel.entry.photoPaths.count)/\(DiaryViewModel.maxPhotos) 枚。")
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

    private var diaryReminderSection: some View {
        Section("日記リマインダー") {
            Toggle("毎日通知", isOn: $diaryReminderEnabled)
                .onChange(of: diaryReminderEnabled) { _, newValue in
                    let calendar = Calendar.current
                    let hour = calendar.component(.hour, from: diaryReminderTime)
                    let minute = calendar.component(.minute, from: diaryReminderTime)
                    viewModel.store.updateDiaryReminder(enabled: newValue, hour: hour, minute: minute)
                }
            if diaryReminderEnabled {
                DatePicker("通知時刻", selection: $diaryReminderTime, displayedComponents: .hourAndMinute)
                    .onChange(of: diaryReminderTime) { _, newValue in
                        let calendar = Calendar.current
                        let hour = calendar.component(.hour, from: newValue)
                        let minute = calendar.component(.minute, from: newValue)
                        viewModel.store.updateDiaryReminder(enabled: diaryReminderEnabled, hour: hour, minute: minute)
                    }
            }
            Text("オンにすると毎日指定時刻に日記のリマインダーが届きます。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ConditionLevel {
    let value: Int
    let emoji: String

    var displayText: String {
        "\(emoji) \(value)"
    }
}
