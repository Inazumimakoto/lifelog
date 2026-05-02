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
    @State private var settings = WallpaperCalendarSettingsStore.shared.load()
    @State private var selectedBackgroundItem: PhotosPickerItem?
    @State private var previewSnapshot: WallpaperCalendarSnapshot?
    @State private var previewPages: [WallpaperCalendarPreviewPage] = []
    @State private var previewBackgroundImage: UIImage?
    @State private var generatedImageURL: URL?
    @State private var generatedImage: UIImage?
    @State private var shortcutGuidePage = 0
    @State private var shortcutAutomationGuidePage = 0
    @State private var isShowingBackgroundAdjustment = false
    @State private var isLoadingBackground = false
    @State private var isRendering = false
    @State private var alertMessage: String?

    private static let shortcutGuideSteps: [ShortcutGuideStep] = [
        ShortcutGuideStep(
            actionTitle: "ショートカット作成画面を開く",
            actionSystemImage: "square.grid.2x2",
            centersAction: true
        ),
        ShortcutGuideStep(
            assetName: "WallpaperShortcutGuide00",
            title: "lifelifyで検索",
            detail: "検索欄に「lifelify」と入力して「壁紙カレンダーを更新」を選びます。"
        ),
        ShortcutGuideStep(
            assetName: "WallpaperShortcutGuide01",
            title: "実行時に表示をオフ",
            detail: "「壁紙カレンダーを更新」を追加したら、「実行時に表示」をオフにします。"
        ),
        ShortcutGuideStep(
            assetName: "WallpaperShortcutGuide02",
            title: "壁紙を設定を追加",
            detail: "検索欄に「壁紙を設定」と入力し、iOS標準の「壁紙に写真を設定」を選びます。"
        ),
        ShortcutGuideStep(
            assetName: "WallpaperShortcutGuide03",
            title: "設定先を開く",
            detail: "「ロック画面、ホーム画面」と表示されている部分をタップします。"
        ),
        ShortcutGuideStep(
            assetName: "WallpaperShortcutGuide04",
            title: "ロック画面だけにする",
            detail: "ホーム画面のチェックを外して、ロック画面だけに設定します。"
        ),
        ShortcutGuideStep(
            assetName: "WallpaperShortcutGuide05",
            title: "詳細を開く",
            detail: "右側の「>」を押して、壁紙設定アクションの詳細を開きます。"
        ),
        ShortcutGuideStep(
            assetName: "WallpaperShortcutGuide06",
            title: "追加オプションをオフ",
            detail: "「プレビューを表示」と「被写体を切り取る」をどちらもオフにします。"
        ),
        ShortcutGuideStep(
            assetName: "WallpaperShortcutGuide07",
            title: "再生して確認",
            detail: "右下の再生ボタンを押して、ロック画面が変わることを確認します。確認できたら下の「自動更新を設定」へ進んでください。"
        )
    ]

    private static let shortcutAutomationSteps: [ShortcutGuideStep] = [
        ShortcutGuideStep(
            assetName: "WallpaperAutomationGuide01",
            title: "オートメーションを開く",
            detail: "下の「オートメーション」を選び、「新規オートメーション」をタップします。既にある場合は右上の「＋」を押します。"
        ),
        ShortcutGuideStep(
            assetName: "WallpaperAutomationGuide02",
            title: "アプリを選ぶ",
            detail: "予定を追加してlifelifyを閉じた時に更新するため、トリガーは「アプリ」を選びます。"
        ),
        ShortcutGuideStep(
            assetName: "WallpaperAutomationGuide03",
            title: "閉じた時にすぐ実行",
            detail: "①lifelifyを選択。②「開いている」を外して「閉じている」をオン。③「すぐに実行」を選び、通知をオフにして「次へ」を押します。"
        ),
        ShortcutGuideStep(
            assetName: "WallpaperAutomationGuide04",
            title: "ショートカットを選択",
            detail: "上で作った「壁紙カレンダーを更新」のショートカットを選びます。"
        ),
        ShortcutGuideStep(
            assetName: "WallpaperAutomationGuide05",
            title: "完成を確認",
            detail: "一覧に「lifelifyが閉じられたとき」と作成したショートカットが表示されていれば完了です。"
        )
    ]

    private let settingsStore = WallpaperCalendarSettingsStore.shared
    private let shortcutCreateURL = URL(string: "shortcuts://create-shortcut")

    var body: some View {
        Form {
            previewSection
            displaySection
            shortcutSection
            generationSection
        }
        .navigationTitle("ロック画面カレンダー")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshPreview()
            loadGeneratedImage()
        }
        .onChange(of: selectedBackgroundItem) { _, newItem in
            guard let newItem else { return }
            loadBackground(from: newItem)
        }
        .alert("ロック画面カレンダー", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if $0 == false { alertMessage = nil } }
        )) {
            Button("OK") { }
        } message: {
            Text(alertMessage ?? "")
        }
        .sheet(isPresented: $isShowingBackgroundAdjustment) {
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
    }

    private var previewSection: some View {
        Section {
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
                    onAdjustBackground: {
                        isShowingBackgroundAdjustment = true
                    },
                    onRemoveBackground: removeBackgroundImage
                )
                .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0))
                .listRowBackground(Color.clear)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
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
        Section {
            Text("次はショートカットとオートメーションを設定します。")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

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

                ShortcutAutomationSummary(
                    steps: Self.shortcutAutomationSteps,
                    selection: $shortcutAutomationGuidePage
                )
            }
            .padding(.vertical, 4)
        } header: {
            Text("ショートカット")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("「今日」がハイライトされるため、必要なら「時刻」トリガーで0:00に更新するオートメーションも追加してください。")
                Text("ロック画面のレイアウトが初期化されますが、時刻のフォントやウィジェットはiOSの壁紙設定で変更し直してください。次からは適用されます。")
            }
        }
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
        } footer: {
            Text("予定・タスク・日付・設定が同じ場合、ショートカット実行時は前回作成した画像を再利用します。")
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
            alertMessage = "ショートカット作成画面を開けませんでした。"
            return
        }
        UIApplication.shared.open(shortcutCreateURL)
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
            Text("ロック画面からも予定を確認しましょう。まずはここから背景画像や週数を選択。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
        "\(weekCount.rawValue)週"
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
            Label("自動更新を設定", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.semibold))

            Text("手動で動作確認できたら、必ず自動更新を設定します。")
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
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日(E)"
        return formatter.string(from: snapshot.generatedAt)
    }

    private var previewTimeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "H:mm"
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
