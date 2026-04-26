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
    @ObservedObject private var monetization = MonetizationService.shared
    @ObservedObject private var tagManager = EmotionTagManager.shared
    @State private var selection: [PhotosPickerItem] = []
    @State private var draftText: String = ""
    @State private var showLocationPicker = false
    @State private var pendingLocationSelection: DiaryLocation?
    @State private var locationTagEditorContext: LocationTagEditorContext?
    @State private var selectedPhoto: PhotoSelection?
    @State private var showTagManager = false
    @State private var isTagSectionExpanded = false
    @State private var diaryReminderEnabled: Bool = false
    @State private var diaryReminderTime: Date = Date()
    @State private var isImportingPhotos = false
    @State private var photoLinkContext: PhotoLinkContext?
    @State private var showPaywall = false
    @State private var linkedPhotoPathsCache: Set<String> = []
    
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
            draftText = viewModel.entry.text
            refreshLinkedPhotoPaths()
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
        .onChange(of: selection) { _, newSelection in
            guard newSelection.isEmpty == false else { return }
            let items = newSelection
            selection = []
            isImportingPhotos = true
            _Concurrency.Task {
                let summary = await viewModel.importPhotos(from: items)
                await MainActor.run {
                    isImportingPhotos = false
                    showPhotoImportToast(summary)
                }
            }
        }
        .onChange(of: draftText) { _, newValue in
            viewModel.update(text: newValue)
        }
        .onChange(of: viewModel.entry.photoPaths) { _, _ in
            refreshLinkedPhotoPaths()
        }
        .onChange(of: viewModel.entry.locations) { _, _ in
            refreshLinkedPhotoPaths()
        }
        .onChange(of: viewModel.entry.date) { _, _ in
            draftText = viewModel.entry.text
        }
        .onChange(of: scenePhase, initial: false) { _, newPhase in
            if newPhase != .active {
                viewModel.flushPendingTextSave()
            }
        }
        .fullScreenCover(item: $selectedPhoto) { selection in
            DiaryPhotoViewerView(viewModel: viewModel,
                                 initialIndex: selection.index,
                                 onIndexChanged: { newIndex in
                                     selectedPhoto?.index = newIndex
                                 })
        }
        .sheet(isPresented: $showTagManager) {
            EmotionTagManagerView()
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView()
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
        .sheet(isPresented: $showLocationPicker, onDismiss: {
            if let pendingLocationSelection {
                if let locationID = viewModel.addLocation(pendingLocationSelection) {
                    locationTagEditorContext = LocationTagEditorContext(locationID: locationID,
                                                                        isPromptForNewLocation: true)
                }
                self.pendingLocationSelection = nil
            }
        }) {
            DiaryLocationPickerView(isPresented: $showLocationPicker,
                                    initialCoordinate: locationSeedCoordinate,
                                    pastEntries: viewModel.store.diaryEntries) { location in
                pendingLocationSelection = location
            }
            .presentationDetents([.large])
        }
        .sheet(item: $photoLinkContext) { context in
            PhotoLocationLinkSheet(context: context, viewModel: viewModel, onImportSummary: { summary in
                showPhotoImportToast(summary)
            })
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $locationTagEditorContext) { context in
            if let location = viewModel.entry.locations.first(where: { $0.id == context.locationID }) {
                LocationVisitTagPickerSheet(locationName: location.name,
                                           selectedTags: location.visitTags,
                                           store: viewModel.store,
                                           isPromptForNewLocation: context.isPromptForNewLocation,
                                           onSave: { tags in
                                               viewModel.updateVisitTags(for: context.locationID, tags: tags)
                                           },
                                           onGlobalRename: { oldName, newName in
                                               viewModel.applyVisitTagRename(oldName: oldName, newName: newName)
                                           },
                                           onGlobalDelete: { deletedName in
                                               viewModel.applyVisitTagDeletion(name: deletedName)
                                           })
                    .presentationDetents([.medium, .large])
            } else {
                Color.clear
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
                Text("ここに文章を入力")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                    .opacity(draftText.isEmpty ? 1 : 0)
                    .allowsHitTesting(false)
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

    @ViewBuilder
    private var locationSection: some View {
        Section("場所") {
            if monetization.canUseDiaryLocation {
                // docs/requirements.md §4.4 日記: 位置情報ログ
                if viewModel.entry.locations.isEmpty {
                    Text("訪れた場所を残しておきましょう。地図を動かしてお店やスポットを選べます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    DiaryLocationsMapView(locations: viewModel.entry.locations)
                        .equatable()
                        .frame(height: 120)
                        .cornerRadius(12)
                    VStack(spacing: 8) {
                        ForEach(viewModel.entry.locations) { location in
                            DiaryLocationRow(location: location,
                                             onLink: {
                                                 photoLinkContext = .location(location.id)
                                             },
                                             onEditTags: {
                                                 locationTagEditorContext = LocationTagEditorContext(locationID: location.id,
                                                                                                     isPromptForNewLocation: false)
                                             },
                                             onRemove: {
                                                 viewModel.removeLocation(id: location.id)
                                             })
                            .equatable()
                        }
                    }
                }
                Button {
                    showLocationPicker = true
                } label: {
                    Label("場所を追加", systemImage: "mappin.and.ellipse")
                }
            } else {
                PremiumLockCard(title: "場所保存",
                                message: monetization.diaryLocationMessage(),
                                actionTitle: "プランを見る") {
                    showPaywall = true
                }
            }
        }
    }

    private var locationSeedCoordinate: CLLocationCoordinate2D {
        if let location = viewModel.entry.locations.last {
            return location.coordinate
        }
        if let lat = viewModel.entry.latitude, let lon = viewModel.entry.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return viewModel.recentLocationCoordinate()
            ?? CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125)
    }

    private var photosSection: some View {
        let maxPhotos = viewModel.diaryPhotoLimit
        let remainingSlots = max(0, maxPhotos - viewModel.entry.photoPaths.count)
        return Section("写真") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    DiaryPhotoThumbnailList(photoPaths: viewModel.entry.photoPaths,
                                            favoritePhotoPath: viewModel.entry.favoritePhotoPath,
                                            linkedPhotoPaths: linkedPhotoPathsCache,
                                            showFavorite: true,
                                            showDelete: false,
                                            onSetFavorite: { index in
                                                viewModel.setFavoritePhoto(at: index)
                                                HapticManager.light()
                                            },
                                            onOpen: { index in
                                                selectedPhoto = PhotoSelection(index: index)
                                            },
                                            onLink: { path in
                                                photoLinkContext = .photo(path)
                                            },
                                            onDelete: nil)
                    PhotosPicker(selection: $selection,
                                 maxSelectionCount: max(1, remainingSlots),
                                 matching: .images) {
                        VStack {
                            if isImportingPhotos {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            } else {
                                Image(systemName: "plus")
                                    .font(.title3)
                                Text("追加")
                            }
                        }
                        .frame(width: 80, height: 80)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isImportingPhotos || remainingSlots == 0)
                }
            }
            Text("写真は最大\(maxPhotos)枚まで追加できます。⭐️で「今日の一枚」をえらびましょう。現在 \(viewModel.entry.photoPaths.count)/\(maxPhotos) 枚。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if remainingSlots == 0 && monetization.isPremiumUnlocked == false {
                Button("写真上限を解放（プレミアム）") {
                    showPaywall = true
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    private func refreshLinkedPhotoPaths() {
        linkedPhotoPathsCache = viewModel.linkedDiaryPhotoPaths()
    }

    private func showPhotoImportToast(_ summary: DiaryViewModel.PhotoImportSummary) {
        guard summary.hasIssues || summary.addedCount == 0 else { return }
        var lines: [String] = []
        if summary.addedCount > 0 {
            lines.append("写真を追加しました（\(summary.addedCount)枚）")
        }
        if summary.skippedCount > 0 {
            lines.append("最大\(viewModel.diaryPhotoLimit)枚までのため、\(summary.skippedCount)枚は追加できませんでした")
        }
        if summary.failedLoadCount > 0 {
            lines.append("読み込めない写真が\(summary.failedLoadCount)枚ありました")
        }
        if summary.failedSaveCount > 0 {
            lines.append("保存に失敗した写真が\(summary.failedSaveCount)枚ありました")
        }
        guard lines.isEmpty == false else { return }
        let emoji = summary.addedCount > 0 ? "🖼️" : "⚠️"
        ToastManager.shared.show(emoji: emoji, message: lines.joined(separator: "\n"))
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

private struct DiaryLocationsMapView: View, Equatable {
    let locations: [DiaryLocation]

    static func ==(lhs: DiaryLocationsMapView, rhs: DiaryLocationsMapView) -> Bool {
        let lhsKeys = lhs.locations.map { "\($0.id.uuidString)|\($0.name)|\($0.address ?? "")|\($0.latitude)|\($0.longitude)" }
        let rhsKeys = rhs.locations.map { "\($0.id.uuidString)|\($0.name)|\($0.address ?? "")|\($0.latitude)|\($0.longitude)" }
        return lhsKeys == rhsKeys
    }

    var body: some View {
        Map(initialPosition: .region(region(for: locations)), interactionModes: []) {
            ForEach(locations) { location in
                Marker(location.name, coordinate: location.coordinate)
            }
        }
        .mapStyle(.standard(elevation: .flat))
    }

    private func region(for locations: [DiaryLocation]) -> MKCoordinateRegion {
        guard let first = locations.first else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125),
                                      span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
        }
        if locations.count == 1 {
            return MKCoordinateRegion(center: first.coordinate,
                                      span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        }
        let latitudes = locations.map { $0.latitude }
        let longitudes = locations.map { $0.longitude }
        let minLat = latitudes.min() ?? first.latitude
        let maxLat = latitudes.max() ?? first.latitude
        let minLon = longitudes.min() ?? first.longitude
        let maxLon = longitudes.max() ?? first.longitude
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.01, (maxLat - minLat) * 1.8),
                                    longitudeDelta: max(0.01, (maxLon - minLon) * 1.8))
        return MKCoordinateRegion(center: center, span: span)
    }
}

private struct DiaryLocationRow: View, Equatable {
    let location: DiaryLocation
    let onLink: () -> Void
    let onEditTags: () -> Void
    let onRemove: () -> Void

    static func ==(lhs: DiaryLocationRow, rhs: DiaryLocationRow) -> Bool {
        lhs.location == rhs.location
    }

    var body: some View {
        let photoCount = location.photoPaths.count
        let tagCount = location.visitTags.count
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name)
                        .font(.body)
                    if let address = location.address, address.isEmpty == false {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    onLink()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text(photoCount == 0 ? "写真" : "写真 \(photoCount)")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(photoCount == 0 ? .secondary : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                }
                .buttonStyle(.plain)
                Button {
                    onEditTags()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "tag")
                        Text(tagCount == 0 ? "タグ" : "タグ \(tagCount)")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tagCount == 0 ? .secondary : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                }
                .buttonStyle(.plain)
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            if location.visitTags.isEmpty == false {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(location.visitTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.tertiarySystemBackground), in: Capsule())
                        }
                    }
                }
            }
            if location.photoPaths.isEmpty == false {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(location.photoPaths, id: \.self) { path in
                            AsyncThumbnailImage(path: path, size: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct LocationTagEditorContext: Identifiable {
    let locationID: UUID
    let isPromptForNewLocation: Bool
    var id: String { locationID.uuidString }
}

private struct LocationVisitTagPickerSheet: View {
    let locationName: String
    @ObservedObject var store: AppDataStore
    let isPromptForNewLocation: Bool
    let onSave: ([String]) -> Void
    let onGlobalRename: (String, String) -> Void
    let onGlobalDelete: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var workingTags: [String]
    @State private var draftTagName: String = ""
    @State private var messageText: String?
    @State private var showTagManager = false
    
    init(locationName: String,
         selectedTags: [String],
         store: AppDataStore,
         isPromptForNewLocation: Bool,
         onSave: @escaping ([String]) -> Void,
         onGlobalRename: @escaping (String, String) -> Void,
         onGlobalDelete: @escaping (String) -> Void) {
        self.locationName = locationName
        _store = ObservedObject(wrappedValue: store)
        self.isPromptForNewLocation = isPromptForNewLocation
        self.onSave = onSave
        self.onGlobalRename = onGlobalRename
        self.onGlobalDelete = onGlobalDelete
        _workingTags = State(initialValue: Self.normalizedTags(selectedTags))
    }
    
    private var maxTags: Int { AppDataStore.maxLocationVisitTagsPerVisit }
    private var maxTagLength: Int { AppDataStore.maxLocationVisitTagNameLength }
    private var orderedDefinitions: [LocationVisitTagDefinition] {
        store.locationVisitTagDefinitions.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    var body: some View {
        NavigationStack {
            listContent
            .navigationTitle("訪問タグ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        onSave(Self.normalizedTags(workingTags))
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showTagManager) {
                LocationVisitTagManagerView(store: store,
                                            onTagRenamed: { oldName, newName in
                                                applyRename(oldName: oldName, newName: newName)
                                                onGlobalRename(oldName, newName)
                                            },
                                            onTagDeleted: { deletedName in
                                                applyDeletion(name: deletedName)
                                                onGlobalDelete(deletedName)
                                            })
            }
            .alert("タグ", isPresented: isMessageAlertPresented) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(messageText ?? "")
            }
        }
    }

    private var isMessageAlertPresented: Binding<Bool> {
        Binding(
            get: { messageText != nil },
            set: { newValue in
                if newValue == false {
                    messageText = nil
                }
            }
        )
    }

    private var listContent: some View {
        List {
            promptSection
            selectedTagsSection
            selectableTagsSection
            addTagSection
            manageSection
        }
    }

    @ViewBuilder
    private var promptSection: some View {
        if isPromptForNewLocation {
            Section {
                Text("「\(locationName)」にタグを付けます。あとから変更もできます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedTagsSection: some View {
        Section("選択中 (\(workingTags.count)/\(maxTags))") {
            if workingTags.isEmpty {
                Text("未タグ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(workingTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.secondarySystemBackground), in: Capsule())
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var selectableTagsSection: some View {
        Section("タグを選択") {
            ForEach(orderedDefinitions) { definition in
                Button {
                    toggleTag(definition.name)
                } label: {
                    HStack {
                        Text(definition.name)
                        Spacer()
                        if containsTag(named: definition.name) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
    }

    private var addTagSection: some View {
        Section("タグを追加") {
            HStack(spacing: 8) {
                TextField("新しいタグ名", text: $draftTagName)
                Button("追加") {
                    createTag()
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("タグ名は\(maxTagLength)文字以内。絵文字も使えます。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var manageSection: some View {
        Section {
            Button("タグ管理") {
                showTagManager = true
            }
        }
    }
    
    private func toggleTag(_ name: String) {
        if let index = indexOfTag(named: name) {
            workingTags.remove(at: index)
            return
        }
        guard workingTags.count < maxTags else {
            messageText = "1つの場所訪問には最大\(maxTags)件まで設定できます。"
            return
        }
        workingTags.append(name)
        workingTags = Self.normalizedTags(workingTags)
    }
    
    private func createTag() {
        do {
            let created = try store.createLocationVisitTag(named: draftTagName)
            draftTagName = ""
            if containsTag(named: created.name) == false {
                toggleTag(created.name)
            }
        } catch {
            messageText = (error as? AppDataStore.LocationVisitTagError)?.errorDescription ?? "タグの追加に失敗しました。"
        }
    }
    
    private func containsTag(named name: String) -> Bool {
        indexOfTag(named: name) != nil
    }
    
    private func indexOfTag(named name: String) -> Int? {
        let key = Self.normalizedTagKey(name)
        return workingTags.firstIndex { Self.normalizedTagKey($0) == key }
    }
    
    private func applyRename(oldName: String, newName: String) {
        for index in workingTags.indices where Self.isSameTagName(workingTags[index], oldName) {
            workingTags[index] = newName
        }
        workingTags = Self.normalizedTags(workingTags)
    }
    
    private func applyDeletion(name: String) {
        workingTags.removeAll { Self.isSameTagName($0, name) }
        workingTags = Self.normalizedTags(workingTags)
    }
    
    private static func normalizedTags(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        var normalized: [String] = []
        for raw in tags {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            let key = normalizedTagKey(trimmed)
            guard seen.contains(key) == false else { continue }
            seen.insert(key)
            normalized.append(trimmed)
            if normalized.count >= AppDataStore.maxLocationVisitTagsPerVisit {
                break
            }
        }
        return normalized
    }
    
    private static func normalizedTagKey(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
    
    private static func isSameTagName(_ lhs: String, _ rhs: String) -> Bool {
        normalizedTagKey(lhs) == normalizedTagKey(rhs)
    }
}

private struct LocationVisitTagManagerView: View {
    @ObservedObject var store: AppDataStore
    let onTagRenamed: (String, String) -> Void
    let onTagDeleted: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var draftTagName: String = ""
    @State private var messageText: String?
    @State private var renameTarget: LocationVisitTagDefinition?
    @State private var renameDraft: String = ""
    @State private var deleteTarget: LocationVisitTagDefinition?
    @State private var deleteAffectedCount: Int = 0
    
    private var orderedDefinitions: [LocationVisitTagDefinition] {
        store.locationVisitTagDefinitions.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section("タグ一覧") {
                    ForEach(orderedDefinitions) { definition in
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.tertiary)
                            Text(definition.name)
                            Spacer()
                            Button {
                                renameDraft = definition.name
                                renameTarget = definition
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            Button(role: .destructive) {
                                deleteTarget = definition
                                deleteAffectedCount = affectedVisitCount(for: definition.name)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onMove { source, destination in
                        store.moveLocationVisitTag(from: source, to: destination)
                    }
                }
                
                Section("タグを追加") {
                    HStack(spacing: 8) {
                        TextField("新しいタグ名", text: $draftTagName)
                        Button("追加") {
                            do {
                                _ = try store.createLocationVisitTag(named: draftTagName)
                                draftTagName = ""
                            } catch {
                                messageText = (error as? AppDataStore.LocationVisitTagError)?.errorDescription ?? "タグの追加に失敗しました。"
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(draftTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                
                Section {
                    Button("初期タグを追加") {
                        let added = store.reAddDefaultLocationVisitTags()
                        if added == 0 {
                            messageText = "追加できる初期タグはありません。"
                        } else {
                            messageText = "初期タグを\(added)件追加しました。"
                        }
                    }
                }
            }
            .navigationTitle("訪問タグ管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .alert("タグ名を変更", isPresented: Binding(get: {
                renameTarget != nil
            }, set: { newValue in
                if newValue == false {
                    renameTarget = nil
                }
            }), actions: {
                TextField("タグ名", text: $renameDraft)
                Button("キャンセル", role: .cancel) {
                    renameTarget = nil
                }
                Button("保存") {
                    guard let target = renameTarget else { return }
                    let oldName = target.name
                    do {
                        try store.renameLocationVisitTag(id: target.id, to: renameDraft)
                        onTagRenamed(oldName, renameDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                        renameTarget = nil
                    } catch {
                        messageText = (error as? AppDataStore.LocationVisitTagError)?.errorDescription ?? "タグ名の変更に失敗しました。"
                    }
                }
            }, message: {
                Text("タグ名は\(AppDataStore.maxLocationVisitTagNameLength)文字以内です。")
            })
            .alert("タグを削除", isPresented: Binding(get: {
                deleteTarget != nil
            }, set: { newValue in
                if newValue == false {
                    deleteTarget = nil
                }
            }), actions: {
                Button("キャンセル", role: .cancel) {
                    deleteTarget = nil
                }
                Button("削除", role: .destructive) {
                    guard let target = deleteTarget else { return }
                    _ = store.deleteLocationVisitTag(id: target.id)
                    onTagDeleted(target.name)
                    deleteTarget = nil
                }
            }, message: {
                let name = deleteTarget?.name ?? ""
                Text("「\(name)」を全訪問(\(deleteAffectedCount)件)から削除します。")
            })
            .alert("タグ", isPresented: Binding(get: {
                messageText != nil
            }, set: { newValue in
                if newValue == false {
                    messageText = nil
                }
            }), actions: {
                Button("OK", role: .cancel) { }
            }, message: {
                Text(messageText ?? "")
            })
        }
    }
    
    private func affectedVisitCount(for tagName: String) -> Int {
        let key = normalizedTagKey(tagName)
        var count = 0
        for entry in store.diaryEntries {
            for location in entry.locations {
                if location.visitTags.contains(where: { normalizedTagKey($0) == key }) {
                    count += 1
                }
            }
        }
        return count
    }
    
    private func normalizedTagKey(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

private struct PhotoSelection: Identifiable {
    let id = UUID()
    var index: Int
}

private enum PhotoLinkContext: Identifiable {
    case location(UUID)
    case photo(String)

    var id: String {
        switch self {
        case .location(let id):
            return "location-\(id.uuidString)"
        case .photo(let path):
            return "photo-\(path)"
        }
    }
}

private struct PhotoLocationLinkSheet: View {
    let context: PhotoLinkContext
    @ObservedObject var viewModel: DiaryViewModel
    let onImportSummary: (DiaryViewModel.PhotoImportSummary) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhotoPaths: Set<String> = []
    @State private var selectedLocationIDs: Set<UUID> = []
    @State private var locationSelection: [PhotosPickerItem] = []
    @State private var isImportingLocationPhotos = false

    private var isLocationMode: Bool {
        if case .location = context { return true }
        return false
    }

    private var currentLocation: DiaryLocation? {
        guard case .location(let id) = context else { return nil }
        return viewModel.entry.locations.first { $0.id == id }
    }

    private var currentPhotoPath: String? {
        guard case .photo(let path) = context else { return nil }
        return path
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLocationMode {
                    locationModeView
                } else {
                    photoModeView
                }
            }
            .navigationTitle(isLocationMode ? "写真を紐付け" : "場所を紐付け")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        applySelection()
                    }
                }
            }
            .onAppear {
                setupSelection()
            }
            .onChange(of: locationSelection) { _, newSelection in
                guard newSelection.isEmpty == false else { return }
                let items = newSelection
                locationSelection = []
                isImportingLocationPhotos = true
                _Concurrency.Task {
                    let summary = await viewModel.importLocationPhotos(from: items)
                    await MainActor.run {
                        isImportingLocationPhotos = false
                        if summary.addedCount > 0 {
                            selectedPhotoPaths.formUnion(summary.addedPaths)
                            // 追加分のみを既存リンクへ追記（上書きしない）
                            if case .location(let locationID) = context {
                                viewModel.addPhotoLinks(forLocation: locationID, paths: summary.addedPaths)
                            }
                        }
                        onImportSummary(summary)
                    }
                }
            }
        }
    }

    private var locationModeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let location = currentLocation {
                Text(location.name)
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            let diaryPaths = viewModel.entry.photoPaths
            let linkedLocationPaths = Set(currentLocation?.photoPaths ?? [])
            // 編集中（未確定）の選択も表示に反映して、追加直後の確認を可能にする
            let previewLinkedLocationPaths = linkedLocationPaths.union(selectedPhotoPaths)
            let locationPaths = viewModel.entry.locationPhotoPaths.filter { previewLinkedLocationPaths.contains($0) }
            if diaryPaths.isEmpty && locationPaths.isEmpty {
                VStack(spacing: 12) {
                    Text("写真がありません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    locationPhotoAddPicker
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if diaryPaths.isEmpty == false {
                            Text("日記の写真")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                            LazyVGrid(columns: photoGridColumns, spacing: 12) {
                                ForEach(diaryPaths, id: \.self) { path in
                                    PhotoLinkTile(path: path,
                                                  isSelected: selectedPhotoPaths.contains(path)) {
                                        togglePhoto(path)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        Text("追加した写真")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                        LazyVGrid(columns: photoGridColumns, spacing: 12) {
                            ForEach(locationPaths, id: \.self) { path in
                                PhotoLinkTile(path: path,
                                              isSelected: selectedPhotoPaths.contains(path)) {
                                    togglePhoto(path)
                                }
                            }
                            locationPhotoAddPicker
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private var locationPhotoAddPicker: some View {
        PhotosPicker(selection: $locationSelection,
                     maxSelectionCount: nil,
                     matching: .images) {
            VStack {
                if isImportingLocationPhotos {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Image(systemName: "plus")
                        .font(.title3)
                    Text("追加")
                }
            }
            .frame(width: 72, height: 72)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isImportingLocationPhotos)
    }

    private var photoModeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let path = currentPhotoPath {
                HStack(spacing: 12) {
                    AsyncThumbnailImage(path: path, size: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("この写真に場所を紐付けます")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            if viewModel.entry.locations.isEmpty {
                Text("場所がありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.entry.locations) { location in
                        Button {
                            toggleLocation(location.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(location.name)
                                        .foregroundStyle(.primary)
                                    if let address = location.address, address.isEmpty == false {
                                        Text(address)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedLocationIDs.contains(location.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var photoGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 72), spacing: 12), count: 4)
    }

    private func setupSelection() {
        switch context {
        case .location(let id):
            if let location = viewModel.entry.locations.first(where: { $0.id == id }) {
                let availablePaths = Set(viewModel.entry.photoPaths + viewModel.entry.locationPhotoPaths)
                selectedPhotoPaths = Set(location.photoPaths.filter { availablePaths.contains($0) })
            }
        case .photo(let path):
            selectedLocationIDs = viewModel.linkedLocationIDs(forPhoto: path)
        }
    }

    private func togglePhoto(_ path: String) {
        if selectedPhotoPaths.contains(path) {
            selectedPhotoPaths.remove(path)
        } else {
            selectedPhotoPaths.insert(path)
        }
        if isLocationMode, let location = currentLocation {
            viewModel.updatePhotoLinks(forLocation: location.id, selectedPaths: Array(selectedPhotoPaths))
            if viewModel.entry.locationPhotoPaths.contains(path) {
                pruneUnlinkedLocationPhoto(path)
            }
        }
    }

    private func pruneUnlinkedLocationPhoto(_ path: String) {
        let stillLinked = viewModel.entry.locations.contains { $0.photoPaths.contains(path) }
        if stillLinked == false {
            viewModel.deleteLocationPhoto(path: path)
        }
    }

    private func toggleLocation(_ id: UUID) {
        if selectedLocationIDs.contains(id) {
            selectedLocationIDs.remove(id)
        } else {
            selectedLocationIDs.insert(id)
        }
    }

    private func applySelection() {
        switch context {
        case .location(let id):
            viewModel.updatePhotoLinks(forLocation: id, selectedPaths: Array(selectedPhotoPaths))
        case .photo(let path):
            let ordered = viewModel.entry.locations
                .map(\.id)
                .filter { selectedLocationIDs.contains($0) }
            viewModel.updateLocationLinks(forPhoto: path, selectedLocationIDs: ordered)
        }
        dismiss()
    }
}

private struct PhotoLinkTile: View {
    let path: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            ZStack(alignment: .topTrailing) {
                AsyncThumbnailImage(path: path, size: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .white.opacity(0.9))
                    .padding(6)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct DiaryPhotoThumbnailList: View, Equatable {
    let photoPaths: [String]
    let favoritePhotoPath: String?
    let linkedPhotoPaths: Set<String>
    let showFavorite: Bool
    let showDelete: Bool
    let onSetFavorite: (Int) -> Void
    let onOpen: (Int) -> Void
    let onLink: (String) -> Void
    let onDelete: ((String) -> Void)?

    static func ==(lhs: DiaryPhotoThumbnailList, rhs: DiaryPhotoThumbnailList) -> Bool {
        lhs.photoPaths == rhs.photoPaths
        && lhs.favoritePhotoPath == rhs.favoritePhotoPath
        && lhs.linkedPhotoPaths == rhs.linkedPhotoPaths
        && lhs.showFavorite == rhs.showFavorite
        && lhs.showDelete == rhs.showDelete
    }

    var body: some View {
        ForEach(Array(photoPaths.enumerated()), id: \.offset) { index, path in
            let isFavorite = favoritePhotoPath == path
            let isLinked = linkedPhotoPaths.contains(path)
            DiaryPhotoThumbnailItem(
                path: path,
                index: index,
                isFavorite: isFavorite,
                isLinked: isLinked,
                showFavorite: showFavorite,
                showDelete: showDelete,
                onSetFavorite: onSetFavorite,
                onOpen: onOpen,
                onLink: onLink,
                onDelete: onDelete
            )
        }
    }
}

// 個別のサムネイルアイテム（非同期読み込み）
private struct DiaryPhotoThumbnailItem: View {
    let path: String
    let index: Int
    let isFavorite: Bool
    let isLinked: Bool
    let showFavorite: Bool
    let showDelete: Bool
    let onSetFavorite: (Int) -> Void
    let onOpen: (Int) -> Void
    let onLink: (String) -> Void
    let onDelete: ((String) -> Void)?
    
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
            if showFavorite {
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
            } else if showDelete, let onDelete {
                Button {
                    onDelete(path)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.5), in: Circle())
                }
                .offset(x: -8, y: -8)
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                onLink(path)
            } label: {
                Image(systemName: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(isLinked ? Color.white : Color.white.opacity(0.9))
                    .padding(6)
                    .background(isLinked ? Color.accentColor.opacity(0.9) : Color.black.opacity(0.45),
                                in: Circle())
            }
            .offset(x: 6, y: 6)
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
