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
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: DiaryViewModel
    @ObservedObject private var tagManager = EmotionTagManager.shared
    @State private var selection: [PhotosPickerItem] = []
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var selectedPlaceName: String = ""
    @State private var draftText: String = ""
    @State private var showMapPicker = false
    @State private var selectedPhotoIndex: Int = 0
    @State private var isShowingPhotoViewer = false
    @State private var showTagManager = false
    @State private var isTagSectionExpanded = false
    @State private var diaryReminderEnabled: Bool = false
    @State private var diaryReminderTime: Date = Date()
    
    // AI採点機能
    @State private var showAIAppSelectionSheet = false
    @State private var selectedScoreMode: DiaryScoreMode = .strict
    @State private var selectedAIProvider: AIProvider = .chatgpt

    init(store: AppDataStore, date: Date) {
        _viewModel = StateObject(wrappedValue: DiaryViewModel(store: store, date: date))
    }

    var body: some View {
        Form {
            entrySection
            aiScoreSection
            moodSection
            emotionTagsSection
            conditionSection
            locationSection
            photosSection
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 12) {
                    Button {
                        navigateDay(offset: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    }
                    
                    Text(viewModel.entry.date.jaMonthDayWeekdayString)
                        .font(.headline)
                    
                    Button {
                        navigateDay(offset: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                    }
                    .disabled(Calendar.current.isDateInToday(viewModel.entry.date))
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("完了") {
                    viewModel.flushPendingTextSave()
                    HapticManager.success()
                    dismiss()
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 50, coordinateSpace: .local)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    // 水平方向が優勢な場合のみ
                    if abs(horizontal) > abs(vertical) {
                        if horizontal > 0 {
                            // 右スワイプ → 前日
                            navigateDay(offset: -1)
                        } else {
                            // 左スワイプ → 翌日
                            if !Calendar.current.isDateInToday(viewModel.entry.date) {
                                navigateDay(offset: 1)
                            }
                        }
                    }
                }
        )
        .onAppear {
            selectedPlaceName = viewModel.entry.locationName ?? ""
            draftText = viewModel.entry.text
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
        .onDisappear {
            viewModel.flushPendingTextSave()
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
        .onChange(of: draftText) { _, newValue in
            viewModel.update(text: newValue)
        }
        .onChange(of: viewModel.entry.date) { _, _ in
            draftText = viewModel.entry.text
        }
        .onChange(of: scenePhase, initial: false) { _, newPhase in
            if newPhase != .active {
                viewModel.flushPendingTextSave()
            }
        }
        .fullScreenCover(isPresented: $isShowingPhotoViewer) {
            DiaryPhotoViewerView(viewModel: viewModel, initialIndex: selectedPhotoIndex)
        }
        .sheet(isPresented: $showTagManager) {
            EmotionTagManagerView()
        }
        .sheet(isPresented: $showAIAppSelectionSheet) {
            AIAppSelectionSheet()
        }
        .sheet(isPresented: $showDevPCSheet, onDismiss: {
            DevPCLLMService.shared.cancel()  // キャンセル処理
            devPCPrompt = ""  // リセット
        }) {
            Group {
                if !devPCPrompt.isEmpty {
                    DevPCResponseView(prompt: devPCPrompt)
                } else {
                    Color.clear
                }
            }
        }
        .onChange(of: devPCPrompt) { _, newValue in
            if !newValue.isEmpty {
                showDevPCSheet = true
            }
        }
    }

    private var textBinding: Binding<String> {
        Binding<String>(
            get: { draftText },
            set: { draftText = $0 }
        )
    }
    
    private func navigateDay(offset: Int) {
        guard let newDate = Calendar.current.date(byAdding: .day, value: offset, to: viewModel.entry.date) else { return }
        // 未来の日付には移動しない
        if newDate > Date() { return }
        HapticManager.light()
        viewModel.loadEntry(for: newDate)
        draftText = viewModel.entry.text
        // 位置情報をリセット
        selectedPlaceName = viewModel.entry.locationName ?? ""
        if let lat = viewModel.entry.latitude,
           let lon = viewModel.entry.longitude {
            selectedCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else {
            selectedCoordinate = nil
        }
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
                if draftText.isEmpty {
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
    
    private var aiScoreSection: some View {
        Section {
            // モード選択
            Picker("モード", selection: $selectedScoreMode) {
                ForEach(DiaryScoreMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            
            // AI選択（Segmented）
            if DevPCLLMService.shared.isAvailable {
                Picker("AI", selection: $selectedAIProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            // 統一アクションボタン
            Button {
                executeAIAnalysis()
            } label: {
                HStack {
                    Spacer()
                    Image(systemName: selectedAIProvider.icon)
                    if selectedAIProvider == .devpc {
                        Text("直接分析")
                    } else {
                        Text("AIに採点してもらう")
                    }
                    Spacer()
                    if selectedAIProvider == .devpc {
                        Text("残\(DevPCLLMService.shared.remainingUsesThisWeek)回")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                DevPCLLMService.shared.canUseThisWeek ? Color.green.opacity(0.2) : Color.red.opacity(0.2),
                                in: Capsule()
                            )
                    }
                }
            }
            .disabled(draftText.isEmpty || (selectedAIProvider == .devpc && !DevPCLLMService.shared.canUseThisWeek))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedScoreMode.description)
                if selectedAIProvider == .devpc {
                    Text("データはどこにも保存されません")
                    Text("ソースコードはGitHubで公開中")
                    Text("週\(LLMConfig.weeklyLimit)回まで（毎週日曜リセット）")
                }
            }
            .font(.caption)
        }
    }
    
    private func executeAIAnalysis() {
        switch selectedAIProvider {
        case .chatgpt:
            copyForAIScoring()
        case .devpc:
            askDevPC()
        }
    }
    
    // 開発者PCシート
    @State private var showDevPCSheet = false
    @State private var devPCPrompt = ""
    
    private func askDevPC() {
        let prompt = DiaryScorePrompt.prompt(for: selectedScoreMode)
        devPCPrompt = DiaryScorePrompt.build(prompt: prompt, diaryText: draftText)
        HapticManager.light()
        // showDevPCSheet は onChange で設定される
    }
    
    private func copyForAIScoring() {
        // 選択したモードのプロンプト + 日記本文をクリップボードにコピー
        let prompt = DiaryScorePrompt.prompt(for: selectedScoreMode)
        let fullText = DiaryScorePrompt.build(prompt: prompt, diaryText: draftText)
        UIPasteboard.general.string = fullText
        HapticManager.success()
        showAIAppSelectionSheet = true
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
                            let isSelected = draftText.contains(tag.hashTag)
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
        var text = draftText
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
        draftText = text.trimmingCharacters(in: .whitespaces)
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
                DiaryLocationMapView(coordinate: coordinate)
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
                    DiaryPhotoThumbnailList(photoPaths: viewModel.entry.photoPaths,
                                            favoritePhotoPath: viewModel.entry.favoritePhotoPath,
                                            onSetFavorite: { index in
                                                viewModel.setFavoritePhoto(at: index)
                                                HapticManager.light()
                                            },
                                            onOpen: { index in
                                                selectedPhotoIndex = index
                                                isShowingPhotoViewer = true
                                            })
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

private struct DiaryLocationMapView: View, Equatable {
    let coordinate: CLLocationCoordinate2D

    static func ==(lhs: DiaryLocationMapView, rhs: DiaryLocationMapView) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: coordinate,
                                                        span: MKCoordinateSpan(latitudeDelta: 0.01,
                                                                               longitudeDelta: 0.01))))
    }
}

private struct DiaryPhotoThumbnailList: View, Equatable {
    let photoPaths: [String]
    let favoritePhotoPath: String?
    let onSetFavorite: (Int) -> Void
    let onOpen: (Int) -> Void

    static func ==(lhs: DiaryPhotoThumbnailList, rhs: DiaryPhotoThumbnailList) -> Bool {
        lhs.photoPaths == rhs.photoPaths && lhs.favoritePhotoPath == rhs.favoritePhotoPath
    }

    var body: some View {
        ForEach(Array(photoPaths.enumerated()), id: \.offset) { index, path in
            let isFavorite = favoritePhotoPath == path
            DiaryPhotoThumbnailItem(
                path: path,
                index: index,
                isFavorite: isFavorite,
                onSetFavorite: onSetFavorite,
                onOpen: onOpen
            )
        }
    }
}

// 個別のサムネイルアイテム（非同期読み込み）
private struct DiaryPhotoThumbnailItem: View {
    let path: String
    let index: Int
    let isFavorite: Bool
    let onSetFavorite: (Int) -> Void
    let onOpen: (Int) -> Void
    
    @State private var thumbnail: UIImage?
    
    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView()
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topLeading) {
            Button {
                onSetFavorite(index)
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
            onOpen(index)
        }
        .task {
            thumbnail = await PhotoStorage.loadThumbnail(at: path)
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
