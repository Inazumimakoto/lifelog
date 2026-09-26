//
//  WallpaperCalendarSettingsView.swift
//  lifelog
//
//  Created by Codex on 2026/04/27.
//

import PhotosUI
import SwiftUI
import UIKit

struct WallpaperCalendarSettingsView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage("WallpaperCalendar_OnboardingPresented_V1") private var hasSeenSetupGuide = false
    @State private var settings = WallpaperCalendarSettingsStore.shared.load()
    @State private var selectedBackgroundItem: PhotosPickerItem?
    @State private var previewSnapshot: WallpaperCalendarSnapshot?
    @State private var previewPages: [WallpaperCalendarPreviewPage] = []
    @State private var previewBackgroundImage: UIImage?
    @State private var generatedImageURL: URL?
    @State private var generatedImage: UIImage?
    @State private var shortcutSheet: ShortcutSheet?
    @State private var shortcutGuidePage = 0
    @State private var shortcutAutomationGuidePage = 0
    @State private var isShowingBackgroundAdjustment = false
    @State private var isLoadingBackground = false
    @State private var isRendering = false
    @State private var alertMessage: String?

    private static let shortcutGuideSteps: [ShortcutGuideStep] = [
        ShortcutGuideStep(
            actionTitle: String(localized: "ショートカット作成画面を開く"),
            actionSystemImage: "square.grid.2x2",
            centersAction: true
        ),
        ShortcutGuideStep(
            assetName: "WallpaperShortcutGuide00",
            title: String(localized: "lifelifyで検索"),
            detail: String(localized: "検索欄に「lifelify」と入力して「壁紙カレンダーを更新」を選びます。")
        ),
        ShortcutGuideStep(
            assetName: "WallpaperShortcutGuide01",
            title: String(localized: "実行時に表示をオフ"),
            detail: String(localized: "「壁紙カレンダーを更新」を追加したら、「実行時に表示」をオフにします。")
        ),
        ShortcutGuideStep(
            assetName: "WallpaperShortcutGuide02",
            title: String(localized: "壁紙を設定を追加"),
            detail: String(localized: "検索欄に「壁紙を設定」と入力し、iOS標準の「壁紙に写真を設定」を選びます。")
        ),
        ShortcutGuideStep(
            assetName: "WallpaperShortcutGuide03",
            title: String(localized: "設定先を開く"),
            detail: String(localized: "「ロック画面、ホーム画面」と表示されている部分をタップします。")
        ),
        ShortcutGuideStep(
            assetName: "WallpaperShortcutGuide04",
            title: String(localized: "ロック画面だけにする"),
            detail: String(localized: "ホーム画面のチェックを外して、ロック画面だけに設定します。")
        ),
        ShortcutGuideStep(
            assetName: "WallpaperShortcutGuide05",
            title: String(localized: "詳細を開く"),
            detail: String(localized: "右側の「>」を押して、壁紙設定アクションの詳細を開きます。")
        ),
        ShortcutGuideStep(
            assetName: "WallpaperShortcutGuide06",
            title: String(localized: "追加オプションをオフ"),
            detail: String(localized: "「プレビューを表示」と「被写体を切り取る」をどちらもオフにします。")
        ),
        ShortcutGuideStep(
            assetName: "WallpaperShortcutGuide07",
            title: String(localized: "再生して確認"),
            detail: String(localized: "右下の再生ボタンを押して、ロック画面が変わることを確認します。確認できたら下の「自動更新を設定」へ進んでください。")
        )
    ]

    private static let shortcutAutomationSteps: [ShortcutGuideStep] = [
        ShortcutGuideStep(
            assetName: "WallpaperAutomationGuide01",
            title: String(localized: "オートメーションを開く"),
            detail: String(localized: "下の「オートメーション」を選び、「新規オートメーション」をタップします。既にある場合は右上の「＋」を押します。")
        ),
        ShortcutGuideStep(
            assetName: "WallpaperAutomationGuide02",
            title: String(localized: "アプリを選ぶ"),
            detail: String(localized: "予定を追加してlifelifyを閉じた時に更新するため、トリガーは「アプリ」を選びます。")
        ),
        ShortcutGuideStep(
            assetName: "WallpaperAutomationGuide03",
            title: String(localized: "閉じた時にすぐ実行"),
            detail: String(localized: "①lifelifyを選択。②「開いている」を外して「閉じている」をオン。③「すぐに実行」を選び、通知をオフにして「次へ」を押します。")
        ),
        ShortcutGuideStep(
            assetName: "WallpaperAutomationGuide04",
            title: String(localized: "ショートカットを選択"),
            detail: String(localized: "上で追加または作成した壁紙カレンダーのショートカットを選びます。")
        ),
        ShortcutGuideStep(
            assetName: "WallpaperAutomationGuide05",
            title: String(localized: "完成を確認"),
            detail: String(localized: "一覧に「lifelifyが閉じられたとき」と作成したショートカットが表示されていれば完了です。")
        )
    ]

    private enum ShortcutSheet: Identifiable, Equatable {
        case setup(URL)
        case manual

        var id: String {
            switch self {
            case .setup: "setup"
            case .manual: "manual"
            }
        }
    }

    private let settingsStore = WallpaperCalendarSettingsStore.shared
    private let shortcutCreateURL = URL(string: "shortcuts://create-shortcut")
    private let shortcutInstallationURL = WallpaperCalendarShortcut.installationURL

    var body: some View {
        Form {
            previewSection
            displaySection
            shortcutSection
            manualSetupFootnote
        }
        .navigationTitle("ロック画面カレンダー")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshPreview()
            loadGeneratedImage()
            presentInitialSetupIfNeeded()
        }
        .onChange(of: selectedBackgroundItem) { _, newItem in
            guard let newItem else { return }
            loadBackground(from: newItem)
        }
        .alert("ロック画面カレンダー", isPresented: Binding(
            get: { alertMessage != nil && shortcutSheet == nil },
            set: { if $0 == false { alertMessage = nil } }
        )) {
            Button("OK") { }
        } message: {
            Text(alertMessage ?? "")
        }
        .sheet(item: $shortcutSheet, onDismiss: { alertMessage = nil }) { destination in
            shortcutSheetContent(destination)
                .sheet(isPresented: $isShowingBackgroundAdjustment) {
                    backgroundAdjustmentContent
                }
                .alert("ロック画面カレンダー", isPresented: Binding(
                    get: { alertMessage != nil },
                    set: { if !$0 { alertMessage = nil } }
                )) {
                    Button("OK") { }
                } message: {
                    Text(alertMessage ?? "")
                }
        }
        .sheet(isPresented: Binding(
            get: { isShowingBackgroundAdjustment && shortcutSheet == nil },
            set: { isShowingBackgroundAdjustment = $0 }
        )) {
            backgroundAdjustmentContent
        }
    }

    @ViewBuilder
    private var backgroundAdjustmentContent: some View {
        if let previewSnapshot = currentPreviewPage?.snapshot ?? previewSnapshot,
           let previewBackgroundImage {
            WallpaperBackgroundAdjustmentSheet(
                snapshot: previewSnapshot,
                settings: settings,
                backgroundImage: previewBackgroundImage,
                isDarkAppearance: resolvedDarkAppearance,
                onSave: saveBackgroundAdjustment
            )
        } else {
            NavigationStack {
                ContentUnavailableView(
                    "画像を読み込めませんでした",
                    systemImage: "photo",
                    description: Text("もう一度、壁紙画像を選び直してください。")
                )
            }
        }
    }

    private var previewSection: some View {
        Section {
            wallpaperPreview
                .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0))
                .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var wallpaperPreview: some View {
        if previewPages.isEmpty == false {
            WallpaperCalendarPreviewEditor(
                selectedBackgroundItem: $selectedBackgroundItem,
                pages: previewPages,
                selectedPreset: settings.layoutPreset.normalized,
                backgroundImage: previewBackgroundImage,
                backgroundColor: colorPickerSelection(for: backgroundColorBinding),
                isDarkAppearance: resolvedDarkAppearance,
                isLoadingBackground: isLoadingBackground,
                onSelectPreset: selectLayoutPreset,
                onAdjustBackground: { isShowingBackgroundAdjustment = true },
                onRemoveBackground: removeBackgroundImage
            )
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var onboardingBackgroundContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let previewBackgroundImage, let page = currentPreviewPage {
                WallpaperCalendarLockScreenPreview(
                    snapshot: page.snapshot,
                    settings: page.settings,
                    backgroundImage: previewBackgroundImage,
                    isDarkAppearance: resolvedDarkAppearance
                )
                .scaledPhonePreview(width: 170)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            } else {
                AppColorPalette.color(for: settings.backgroundColorToken)
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.secondary.opacity(0.2))
                    }
                    .accessibilityHidden(true)
            }

            PhotosPicker(selection: $selectedBackgroundItem, matching: .images) {
                HStack {
                    Label {
                        if previewBackgroundImage == nil {
                            Text("写真を選ぶ")
                        } else {
                            Text("写真を変更")
                        }
                    } icon: {
                        Image(systemName: "photo")
                    }
                    Spacer()
                    if isLoadingBackground {
                        ProgressView()
                    }
                }
                .frame(minHeight: 32)
            }
            .buttonStyle(.bordered)
            .disabled(isLoadingBackground)
            .accessibilityIdentifier("wallpaperSetup.photo")

            if previewBackgroundImage == nil {
                ColorPicker("背景色", selection: colorPickerSelection(for: backgroundColorBinding), supportsOpacity: false)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("wallpaperSetup.color")
            } else {
                Button {
                    isShowingBackgroundAdjustment = true
                } label: {
                    Label("写真の位置を調整", systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(minHeight: 44)
                }
                .disabled(isLoadingBackground)
                .accessibilityIdentifier("wallpaperSetup.adjust")

                Button("写真を使わない", role: .destructive, action: removeBackgroundImage)
                    .frame(minHeight: 44)
                    .disabled(isLoadingBackground)
                    .accessibilityIdentifier("wallpaperSetup.removePhoto")
            }
        }
    }

    private var onboardingLayoutContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { proxy in
                let spacing: CGFloat = 10
                let optionWidth = max(0, (proxy.size.width - spacing * 2) / 3)
                let phoneWidth = max(1, min(104, optionWidth - 16))

                HStack(alignment: .top, spacing: spacing) {
                    ForEach(WallpaperCalendarLayoutPreset.selectableCases) { preset in
                        Button {
                            selectLayoutPreset(preset)
                        } label: {
                            onboardingLayoutOption(preset, phoneWidth: phoneWidth)
                                .frame(width: optionWidth)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.weekCount.title)
                        .accessibilityIdentifier("wallpaperSetup.layout.\(preset.rawValue)")
                        .accessibilityAddTraits(settings.layoutPreset.normalized == preset ? .isSelected : [])
                    }
                }
            }
            .frame(height: 300)

            Text(settings.layoutPreset.normalized.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func onboardingLayoutOption(_ preset: WallpaperCalendarLayoutPreset, phoneWidth: CGFloat) -> some View {
        let isSelected = settings.layoutPreset.normalized == preset

        return VStack(spacing: 10) {
            if let page = previewPages.first(where: { $0.preset == preset.normalized }) {
                WallpaperCalendarLockScreenPreview(
                    snapshot: page.snapshot,
                    settings: page.settings,
                    backgroundImage: previewBackgroundImage,
                    isDarkAppearance: resolvedDarkAppearance
                )
                .scaledPhonePreview(width: phoneWidth)
                .accessibilityHidden(true)
            } else {
                ProgressView()
                    .frame(width: phoneWidth, height: phoneWidth * 852 / 393)
            }

            HStack(spacing: 4) {
                Text(preset.weekCount.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private var onboardingPrivacyContent: some View {
        VStack(spacing: 12) {
            ForEach(WallpaperCalendarPrivacyMode.allCases) { mode in
                Button {
                    binding(\.privacyMode).wrappedValue = mode
                } label: {
                    selectionCard(
                        title: mode.title,
                        detail: privacyDescription(for: mode),
                        isSelected: settings.privacyMode == mode
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wallpaperSetup.privacy.\(mode.rawValue)")
                .accessibilityAddTraits(settings.privacyMode == mode ? .isSelected : [])
            }
        }
    }

    private func selectionCard(title: String, detail: String, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private func privacyDescription(for mode: WallpaperCalendarPrivacyMode) -> String {
        switch mode {
        case .details:
            String(localized: "予定やタスクの名前を表示します。")
        case .categoryOnly:
            String(localized: "予定はカテゴリ名、タスクは「タスク」と表示します。")
        case .hidden:
            String(localized: "名前を隠して、「予定あり」「タスクあり」と表示します。")
        }
    }

    @ViewBuilder
    private var onboardingPreviewContent: some View {
        if let page = currentPreviewPage {
            WallpaperCalendarLockScreenPreview(
                snapshot: page.snapshot,
                settings: page.settings,
                backgroundImage: previewBackgroundImage,
                isDarkAppearance: resolvedDarkAppearance
            )
            .scaledPhonePreview(width: 210)
            .frame(maxWidth: .infinity)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
        }
    }

    private var displaySection: some View {
        Section("表示") {
            Picker("表示内容", selection: binding(\.privacyMode)) {
                ForEach(WallpaperCalendarPrivacyMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        }
    }

    private var shortcutSection: some View {
        Section("設定ガイド") {
            Text("壁紙の作成から自動更新まで、設定手順をもう一度確認できます。")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: presentSetupGuide) {
                HStack {
                    Text("設定手順をもう一度見る")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("wallpaperShortcut.start")
        }
    }

    private func presentInitialSetupIfNeeded() {
        // Requirements §4.11: automatically introduce the feature once on this device.
        // This records presentation, not successful shortcut or automation installation.
        guard !hasSeenSetupGuide else { return }
        hasSeenSetupGuide = true
        presentSetupGuide()
    }

    private func presentSetupGuide() {
        if let shortcutInstallationURL {
            shortcutSheet = .setup(shortcutInstallationURL)
        } else {
            shortcutSheet = .manual
        }
    }

    private var manualSetupFootnote: some View {
        Section {
            Button {
                shortcutSheet = .manual
            } label: {
                Text("※ 追加できない場合は、手動で作成できます。")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("wallpaperShortcut.manual")
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private func shortcutSheetContent(_ destination: ShortcutSheet) -> some View {
        // requirements.md §4.11: adding, checking, and automating are explicit user steps.
        switch destination {
        case .setup(let url):
            WallpaperCalendarShortcutInstallGuide(
                isWallpaperLoading: isLoadingBackground,
                onInstall: {
                    openURL(url) { accepted in
                        if !accepted {
                            alertMessage = String(localized: "追加ページを開けませんでした。通信環境を確認して、もう一度お試しください。")
                        }
                    }
                },
                onOpenShortcuts: openShortcuts,
                backgroundContent: { onboardingBackgroundContent },
                layoutContent: { onboardingLayoutContent },
                privacyContent: { onboardingPrivacyContent },
                previewContent: { onboardingPreviewContent },
                manualGuide: { manualSetupContent }
            )
        case .manual:
            NavigationStack {
                ScrollView {
                    manualSetupContent
                        .padding()
                }
                .navigationTitle("手動で設定")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("閉じる") { shortcutSheet = nil }
                    }
                }
            }
        }
    }

    private var manualSetupContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            manualShortcutGuide
            ShortcutAutomationSummary(
                steps: Self.shortcutAutomationSteps,
                selection: $shortcutAutomationGuidePage
            )
            generationSection
        }
    }

    private var manualShortcutGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShortcutSetupNote()

            ShortcutGuidePager(
                steps: Self.shortcutGuideSteps,
                selection: $shortcutGuidePage,
                onStepAction: { step in
                    if step.actionTitle != nil {
                        openShortcutCreator()
                    }
                }
            )
        }
        .padding(.vertical, 4)
    }

    private var generationSection: some View {
        Section {
            Button {
                renderNow()
            } label: {
                HStack {
                    Label("今すぐ画像を作成", systemImage: "wand.and.stars")
                    Spacer()
                    if isRendering {
                        ProgressView()
                    }
                }
            }
            .disabled(isRendering || isLoadingBackground)

            if let generatedImage {
                Image(uiImage: generatedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if let generatedImageURL {
                ShareLink(item: generatedImageURL) {
                    Label("画像を共有", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func binding<Value: Equatable>(_ keyPath: WritableKeyPath<WallpaperCalendarSettings, Value>) -> Binding<Value> {
        Binding(
            get: {
                settings[keyPath: keyPath]
            },
            set: { newValue in
                guard settings[keyPath: keyPath] != newValue else { return }
                settings[keyPath: keyPath] = newValue
                persistSettingsChange()
            }
        )
    }

    private var backgroundColorBinding: Binding<String> {
        Binding(
            get: {
                settings.backgroundColorToken
            },
            set: { newValue in
                guard isSameColorToken(settings.backgroundColorToken, newValue) == false else { return }
                settings.backgroundColorToken = newValue
                persistSettingsChange()
            }
        )
    }

    private func selectLayoutPreset(_ newValue: WallpaperCalendarLayoutPreset) {
        let normalizedValue = newValue.normalized
        guard settings.layoutPreset.normalized != normalizedValue else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            settings.layoutPreset = normalizedValue
            settings.weekCount = normalizedValue.weekCount
        }
        persistSettingsChange()
    }

    private func persistSettingsChange() {
        settings.layoutPreset = settings.layoutPreset.normalized
        settings.weekCount = settings.effectiveWeekCount
        settings.lastGeneratedFingerprint = nil
        settings.updatedAt = Date()
        settingsStore.save(settings)
        _Concurrency.Task {
            await refreshPreview()
        }
    }

    private func saveBackgroundAdjustment(_ adjustment: WallpaperCalendarBackgroundAdjustment) {
        settings.backgroundAdjustment = adjustment
        generatedImage = nil
        generatedImageURL = nil
        persistSettingsChange()
    }

    private func removeBackgroundImage() {
        settings = settingsStore.removeBackgroundImage()
        previewBackgroundImage = nil
        generatedImage = nil
        generatedImageURL = nil
        _Concurrency.Task {
            await refreshPreview()
        }
    }

    private func loadBackground(from item: PhotosPickerItem) {
        isLoadingBackground = true
        _Concurrency.Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    await MainActor.run {
                        isLoadingBackground = false
                        alertMessage = "背景画像を読み込めませんでした。"
                    }
                    return
                }
                let imageData = UIImage(data: data)?.jpegData(compressionQuality: 0.92) ?? data
                let newSettings = try settingsStore.saveBackgroundImageData(imageData)
                await MainActor.run {
                    settings = newSettings
                    selectedBackgroundItem = nil
                    isLoadingBackground = false
                    generatedImage = nil
                    generatedImageURL = nil
                }
                await refreshPreview()
            } catch {
                await MainActor.run {
                    isLoadingBackground = false
                    alertMessage = error.localizedDescription
                }
            }
        }
    }

    @MainActor
    private func refreshPreview() async {
        let renderer = WallpaperCalendarRenderer()
        let backgroundImage = settingsStore
            .backgroundImageURL(for: settings)
            .flatMap { UIImage(contentsOfFile: $0.path) }
        let pages = WallpaperCalendarLayoutPreset.selectableCases.map { preset in
            var pageSettings = settings
            pageSettings.layoutPreset = preset.normalized
            pageSettings.weekCount = preset.weekCount
            return WallpaperCalendarPreviewPage(
                preset: preset.normalized,
                snapshot: renderer.makePreviewSnapshot(settings: pageSettings),
                settings: pageSettings
            )
        }
        previewPages = pages
        previewSnapshot = pages.first { $0.preset == settings.layoutPreset.normalized }?.snapshot
            ?? pages.first?.snapshot
        previewBackgroundImage = backgroundImage
    }

    private func renderNow() {
        isRendering = true
        _Concurrency.Task { @MainActor in
            do {
                let url = try WallpaperCalendarRenderer().render(force: true)
                settings = settingsStore.load()
                generatedImageURL = url
                generatedImage = UIImage(contentsOfFile: url.path)
                isRendering = false
                await refreshPreview()
            } catch {
                isRendering = false
                alertMessage = error.localizedDescription
            }
        }
    }

    private func openShortcutCreator() {
        guard let shortcutCreateURL else {
            alertMessage = String(localized: "ショートカット作成画面を開けませんでした。")
            return
        }
        openURL(shortcutCreateURL) { accepted in
            if !accepted {
                alertMessage = String(localized: "ショートカット作成画面を開けませんでした。")
            }
        }
    }

    private func openShortcuts() {
        guard let url = URL(string: "shortcuts://") else { return }
        openURL(url) { accepted in
            if !accepted {
                alertMessage = String(localized: "ショートカットを開けませんでした。ショートカットアプリがインストールされているか確認してください。")
            }
        }
    }

    private func loadGeneratedImage() {
        let url = settingsStore.generatedImageURL(for: settings)
        generatedImageURL = url
        generatedImage = url.flatMap { UIImage(contentsOfFile: $0.path) }
    }

    private func colorPickerSelection(for selection: Binding<String>) -> Binding<Color> {
        Binding(
            get: {
                AppColorPalette.color(for: selection.wrappedValue)
            },
            set: { selected in
                if let hex = selected.cgColor?.hexString {
                    selection.wrappedValue = hex
                }
            }
        )
    }

    private func isSameColorToken(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    private var resolvedDarkAppearance: Bool {
        previewBackgroundImage != nil || WallpaperCalendarBackgroundPalette.isDark(settings.backgroundColorToken)
    }

    private var currentPreviewPage: WallpaperCalendarPreviewPage? {
        previewPages.first { $0.preset == settings.layoutPreset.normalized }
            ?? previewPages.first
    }
}

private struct WallpaperCalendarPreviewPage: Identifiable {
    var id: String { preset.rawValue }
    let preset: WallpaperCalendarLayoutPreset
    let snapshot: WallpaperCalendarSnapshot
    let settings: WallpaperCalendarSettings
}

private struct WallpaperCalendarPreviewEditor: View {
    @Binding var selectedBackgroundItem: PhotosPickerItem?

    let pages: [WallpaperCalendarPreviewPage]
    let selectedPreset: WallpaperCalendarLayoutPreset
    let backgroundImage: UIImage?
    @Binding var backgroundColor: Color
    let isDarkAppearance: Bool
    let isLoadingBackground: Bool
    let onSelectPreset: (WallpaperCalendarLayoutPreset) -> Void
    let onAdjustBackground: () -> Void
    let onRemoveBackground: () -> Void

    private let previewWidth: CGFloat = 272
    private let previewHeight: CGFloat = 852 * (272.0 / 393.0)

    var body: some View {
        VStack(spacing: 12) {
            Text("背景と表示する週数を選べます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            backgroundToolbar
                .frame(height: 48)

            previewPageIndicator

            TabView(selection: previewSelection) {
                ForEach(pages) { page in
                    WallpaperCalendarLockScreenPreview(
                        snapshot: page.snapshot,
                        settings: page.settings,
                        backgroundImage: backgroundImage,
                        isDarkAppearance: isDarkAppearance
                    )
                    .scaledPhonePreview(width: previewWidth)
                    .tag(page.preset.rawValue)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: previewHeight)
        }
        .frame(maxWidth: .infinity)
    }

    private var previewSelection: Binding<String> {
        Binding(
            get: {
                selectedPreset.normalized.rawValue
            },
            set: { rawValue in
                guard let preset = WallpaperCalendarLayoutPreset(rawValue: rawValue) else { return }
                onSelectPreset(preset)
            }
        )
    }

    private var previewPageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages) { page in
                Button {
                    onSelectPreset(page.preset)
                } label: {
                    Text(page.preset.weekLayoutTitle)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(page.preset == selectedPreset.normalized ? Color.white : Color.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(page.preset == selectedPreset.normalized ? Color.accentColor : Color.secondary.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var backgroundToolbar: some View {
        if backgroundImage == nil {
            HStack(spacing: 14) {
                PhotosPicker(selection: $selectedBackgroundItem, matching: .images) {
                    PreviewEditorIconButton(
                        systemImage: "photo.badge.plus",
                        isLoading: isLoadingBackground,
                        tint: .accentColor
                    )
                }
                .buttonStyle(.plain)
                .disabled(isLoadingBackground)
                .accessibilityLabel("壁紙画像を選ぶ")

                PreviewEditorColorPicker(color: $backgroundColor)
            }
        } else {
            HStack(spacing: 14) {
                PhotosPicker(selection: $selectedBackgroundItem, matching: .images) {
                    PreviewEditorIconButton(systemImage: "photo", tint: .accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("壁紙画像を変更")

                Button(action: onAdjustBackground) {
                    PreviewEditorIconButton(systemImage: "arrow.up.left.and.arrow.down.right", tint: .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(backgroundImage == nil)
                .accessibilityLabel("画像の位置を調整")

                Button(role: .destructive, action: onRemoveBackground) {
                    PreviewEditorIconButton(systemImage: "trash", tint: .red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("背景画像を削除")
            }
        }
    }
}

private struct PreviewEditorColorPicker: View {
    @Binding var color: Color

    var body: some View {
        ColorPicker("", selection: $color, supportsOpacity: false)
            .labelsHidden()
            .frame(width: 46, height: 46)
            .overlay {
                PreviewEditorIconButton(systemImage: "paintpalette", tint: .accentColor)
                    .allowsHitTesting(false)
            }
            .accessibilityLabel("背景色を自由に選ぶ")
    }
}

private struct PreviewEditorIconButton: View {
    let systemImage: String
    var isLoading = false
    var tint: Color = .accentColor

    var body: some View {
        Circle()
            .fill(tint.opacity(0.14))
            .frame(width: 46, height: 46)
            .overlay {
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
    }
}

private extension WallpaperCalendarLayoutPreset {
    var weekLayoutTitle: String {
        weekCount.title
    }

    var weekLayoutSubtitle: String {
        switch normalized {
        case .standard:
            return "ふだん使い"
        case .avoidMedia:
            return "再生バーあり"
        case .avoidWidgetsAndMedia:
            return "両方あり"
        case .avoidWidgets:
            return "ふだん使い"
        }
    }
}

private struct ShortcutSetupNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("まず手動で動作確認", systemImage: "play.circle")
                .font(.subheadline.weight(.semibold))

            Text("ショートカットを作って一度実行し、ロック画面が変わることを確認してから自動更新にします。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ShortcutGuideStep: Identifiable {
    let id = UUID()
    var assetName: String? = nil
    var title: String? = nil
    var detail: String? = nil
    var actionTitle: String? = nil
    var actionSystemImage: String? = nil
    var centersAction = false
}

private struct ShortcutGuidePager: View {
    let steps: [ShortcutGuideStep]
    @Binding var selection: Int
    var onStepAction: ((ShortcutGuideStep) -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            TabView(selection: $selection) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    ShortcutGuideCard(
                        step: step,
                        currentIndex: index + 1,
                        totalCount: steps.count,
                        onAction: step.actionTitle == nil ? nil : {
                            onStepAction?(step)
                        }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 500)

            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { index in
                    Circle()
                        .fill(index == selection ? Color.accentColor : Color.secondary.opacity(0.28))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ShortcutGuideCard: View {
    let step: ShortcutGuideStep
    let currentIndex: Int
    let totalCount: Int
    let onAction: (() -> Void)?

    var body: some View {
        if step.centersAction {
            actionOnlyCard
        } else {
            standardCard
        }
    }

    private var standardCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(currentIndex)/\(totalCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()
            }

            if let assetName = step.assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                    )
            }

            if let title = step.title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }

            if let detail = step.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle = step.actionTitle, let onAction {
                stepActionButton(title: actionTitle, action: onAction)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var actionOnlyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(currentIndex)/\(totalCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()
            }

            Spacer()

            if let actionTitle = step.actionTitle, let onAction {
                stepActionButton(title: actionTitle, action: onAction)
                    .frame(maxWidth: .infinity)
            }

            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func stepActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: step.actionSystemImage ?? "arrow.up.right")
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
    }
}

private struct ShortcutAutomationSummary: View {
    let steps: [ShortcutGuideStep]
    @Binding var selection: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("自動更新を設定", systemImage: "3.circle")
                .font(.subheadline.weight(.semibold))

            Text("ショートカットの確認ができたら、毎回の操作なしで更新できるように設定します。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ShortcutGuidePager(
                steps: steps,
                selection: $selection
            )

        }
    }
}

private struct WallpaperBackgroundAdjustmentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let snapshot: WallpaperCalendarSnapshot
    let settings: WallpaperCalendarSettings
    let backgroundImage: UIImage
    let isDarkAppearance: Bool
    let onSave: (WallpaperCalendarBackgroundAdjustment) -> Void

    @State private var adjustment: WallpaperCalendarBackgroundAdjustment
    @State private var dragStartAdjustment: WallpaperCalendarBackgroundAdjustment?
    @State private var scaleStartAdjustment: WallpaperCalendarBackgroundAdjustment?

    private let phoneSize = CGSize(width: 393, height: 852)

    init(snapshot: WallpaperCalendarSnapshot,
         settings: WallpaperCalendarSettings,
         backgroundImage: UIImage,
         isDarkAppearance: Bool,
         onSave: @escaping (WallpaperCalendarBackgroundAdjustment) -> Void) {
        self.snapshot = snapshot
        self.settings = settings
        self.backgroundImage = backgroundImage
        self.isDarkAppearance = isDarkAppearance
        self.onSave = onSave
        _adjustment = State(initialValue: settings.backgroundAdjustment)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let controlsHeight: CGFloat = 116
                let verticalPadding: CGFloat = 36
                let contentSpacing: CGFloat = 18
                let availablePreviewHeight = max(420, proxy.size.height - controlsHeight - verticalPadding - contentSpacing)
                let widthForHeight = availablePreviewHeight * phoneSize.width / phoneSize.height
                let previewWidth = min(max(240, proxy.size.width - 40), 330, widthForHeight)
                let previewHeight = phoneSize.height * (previewWidth / phoneSize.width)
                let previewSize = CGSize(width: previewWidth, height: previewHeight)

                VStack(spacing: contentSpacing) {
                    adjustedPreview(width: previewWidth, previewSize: previewSize)

                    VStack(alignment: .leading, spacing: 12) {
                        Label("ドラッグで移動、ピンチで拡大", systemImage: "hand.draw")
                            .font(.subheadline.weight(.semibold))

                        HStack {
                            Image(systemName: "minus.magnifyingglass")
                                .foregroundStyle(.secondary)
                            Slider(value: scaleBinding, in: WallpaperCalendarBackgroundAdjustment.minScale...WallpaperCalendarBackgroundAdjustment.maxScale)
                            Image(systemName: "plus.magnifyingglass")
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            adjustment = .defaultValue
                        } label: {
                            Label("中央に戻す", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.vertical, verticalPadding / 2)
            }
            .navigationTitle("画像の位置を調整")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        onSave(clampedAdjustment)
                        dismiss()
                    }
                }
            }
        }
    }

    private func adjustedPreview(width: CGFloat, previewSize: CGSize) -> some View {
        WallpaperCalendarLockScreenPreview(
            snapshot: snapshot,
            settings: previewSettings,
            backgroundImage: backgroundImage,
            isDarkAppearance: isDarkAppearance
        )
        .scaledPhonePreview(width: width)
        .contentShape(Rectangle())
        .gesture(dragGesture(previewSize: previewSize))
        .simultaneousGesture(magnificationGesture)
    }

    private var previewSettings: WallpaperCalendarSettings {
        var previewSettings = settings
        previewSettings.backgroundAdjustment = clampedAdjustment
        return previewSettings
    }

    private var clampedAdjustment: WallpaperCalendarBackgroundAdjustment {
        adjustment.clamped(for: backgroundImage.size, canvasSize: phoneSize)
    }

    private var scaleBinding: Binding<Double> {
        Binding(
            get: {
                adjustment.scale
            },
            set: { newValue in
                adjustment = WallpaperCalendarBackgroundAdjustment(
                    scale: newValue,
                    offsetX: adjustment.offsetX,
                    offsetY: adjustment.offsetY
                )
                .clamped(for: backgroundImage.size, canvasSize: phoneSize)
            }
        )
    }

    private func dragGesture(previewSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartAdjustment == nil {
                    dragStartAdjustment = adjustment
                }
                let start = dragStartAdjustment ?? adjustment
                adjustment = WallpaperCalendarBackgroundAdjustment(
                    scale: adjustment.scale,
                    offsetX: start.offsetX + Double(value.translation.width / previewSize.width),
                    offsetY: start.offsetY + Double(value.translation.height / previewSize.height)
                )
                .clamped(for: backgroundImage.size, canvasSize: phoneSize)
            }
            .onEnded { _ in
                adjustment = clampedAdjustment
                dragStartAdjustment = nil
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if scaleStartAdjustment == nil {
                    scaleStartAdjustment = adjustment
                }
                let start = scaleStartAdjustment ?? adjustment
                adjustment = WallpaperCalendarBackgroundAdjustment(
                    scale: start.scale * Double(value),
                    offsetX: adjustment.offsetX,
                    offsetY: adjustment.offsetY
                )
                .clamped(for: backgroundImage.size, canvasSize: phoneSize)
            }
            .onEnded { _ in
                adjustment = clampedAdjustment
                scaleStartAdjustment = nil
            }
    }
}

struct WallpaperCalendarLockScreenPreview: View {
    let snapshot: WallpaperCalendarSnapshot
    let settings: WallpaperCalendarSettings
    let backgroundImage: UIImage?
    let isDarkAppearance: Bool

    private let phoneSize = CGSize(width: 393, height: 852)

    var body: some View {
        ZStack {
            WallpaperCalendarRenderView(
                snapshot: snapshot,
                settings: settings,
                backgroundImage: backgroundImage,
                isDarkAppearance: isDarkAppearance
            )
            .frame(width: phoneSize.width, height: phoneSize.height)

            lockChrome
        }
        .frame(width: phoneSize.width, height: phoneSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
        )
        .environment(\.colorScheme, isDarkAppearance ? .dark : .light)
    }

    private var lockChrome: some View {
        ZStack {
            VStack(spacing: 12) {
                statusBar
                clockBlock

                if settings.layoutPreset.showsWidgetPlaceholder {
                    widgetPlaceholder
                }

                Spacer()
            }
            .padding(.top, 20)
            .padding(.horizontal, 22)

            if settings.layoutPreset.showsMediaPlaceholder {
                mediaPlaceholder
                    .padding(.horizontal, 12)
                    .padding(.bottom, 86)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }

            bottomControls
                .padding(.horizontal, 54)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private var statusBar: some View {
        HStack {
            Text("Carrier")
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100.bolt")
            }
            .font(.system(size: 17, weight: .semibold))
        }
        .foregroundStyle(primaryTextColor)
    }

    private var clockBlock: some View {
        VStack(spacing: 2) {
            Text(previewDateText)
                .font(.system(size: 21, weight: .bold))
            Text(previewTimeText)
                .font(.system(size: 96, weight: .thin))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .foregroundStyle(primaryTextColor)
    }

    private var widgetPlaceholder: some View {
        HStack(spacing: 28) {
            weatherWidgetPlaceholder
            circularWidgetPlaceholder(systemImage: "bolt.fill")
            circularWidgetPlaceholder(systemImage: "sun.max.fill")
        }
        .frame(height: 70)
    }

    private var weatherWidgetPlaceholder: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<6, id: \.self) { index in
                    VStack(spacing: 4) {
                        Text(["21", "0", "3", "6", "9", "12"][index])
                            .font(.system(size: 12, weight: .medium))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(placeholderFill)
                            .frame(width: 24, height: 22)
                            .overlay(Image(systemName: index == 5 ? "cloud.fill" : "sun.max.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(primaryTextColor))
                        Text(["14", "13", "12", "13", "20", "24"][index])
                            .font(.system(size: 12, weight: .medium))
                    }
                }
            }
        }
        .foregroundStyle(primaryTextColor)
    }

    private func circularWidgetPlaceholder(systemImage: String) -> some View {
        Circle()
            .stroke(primaryTextColor.opacity(0.9), lineWidth: 7)
            .frame(width: 60, height: 60)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(primaryTextColor)
            )
    }

    private var mediaPlaceholder: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(mediaFill)
            .frame(height: 184)
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(placeholderFill)
                    .frame(width: 62, height: 62)
                    .padding(18)
            }
            .overlay(alignment: .center) {
                VStack(spacing: 26) {
                    Capsule()
                        .fill(primaryTextColor.opacity(0.18))
                        .frame(width: 272, height: 8)
                    HStack(spacing: 54) {
                        Image(systemName: "backward.fill")
                        Image(systemName: "pause.fill")
                        Image(systemName: "forward.fill")
                    }
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(primaryTextColor)
                }
                .padding(.top, 44)
            }
    }

    private var bottomControls: some View {
        HStack {
            Circle()
                .fill(controlFill)
                .frame(width: 66, height: 66)
                .overlay(Image(systemName: "flashlight.on.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(primaryTextColor))
            Spacer()
            Circle()
                .fill(controlFill)
                .frame(width: 66, height: 66)
                .overlay(Image(systemName: "camera.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(primaryTextColor))
        }
    }

    private var previewDateText: String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MdE")
        return formatter.string(from: snapshot.generatedAt)
    }

    private var previewTimeText: String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Hm")
        return formatter.string(from: snapshot.generatedAt)
    }

    private var primaryTextColor: Color {
        isDarkAppearance ? .white : .black
    }

    private var placeholderFill: Color {
        isDarkAppearance ? Color.white.opacity(0.18) : Color.black.opacity(0.12)
    }

    private var mediaFill: Color {
        isDarkAppearance ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    private var controlFill: Color {
        isDarkAppearance ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
    }
}

private extension View {
    func scaledPhonePreview(width: CGFloat) -> some View {
        let baseWidth: CGFloat = 393
        let baseHeight: CGFloat = 852
        let scale = width / baseWidth
        return self
            .frame(width: baseWidth, height: baseHeight)
            .scaleEffect(scale)
            .frame(width: width, height: baseHeight * scale)
    }
}
