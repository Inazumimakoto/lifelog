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
    @State private var previewBackgroundImage: UIImage?
    @State private var generatedImageURL: URL?
    @State private var generatedImage: UIImage?
    @State private var isLoadingBackground = false
    @State private var isRendering = false
    @State private var alertMessage: String?

    private let settingsStore = WallpaperCalendarSettingsStore.shared
    private let shortcutCreateURL = URL(string: "shortcuts://create-shortcut")

    var body: some View {
        Form {
            previewSection
            backgroundSection
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
    }

    private var previewSection: some View {
        Section {
            if let previewSnapshot {
                HStack {
                    Spacer()
                    WallpaperCalendarLockScreenPreview(
                        snapshot: previewSnapshot,
                        settings: settings,
                        backgroundImage: previewBackgroundImage,
                        isDarkAppearance: resolvedDarkAppearance
                    )
                    .scaledPhonePreview(width: 260)
                    Spacer()
                }
                .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var displaySection: some View {
        Section("表示") {
            Picker("配置", selection: layoutPresetBinding) {
                ForEach(WallpaperCalendarLayoutPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }

            Label(settings.layoutPreset.detail, systemImage: "calendar")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("表示内容", selection: binding(\.privacyMode)) {
                ForEach(WallpaperCalendarPrivacyMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        }
    }

    private var backgroundSection: some View {
        Section {
            PhotosPicker(selection: $selectedBackgroundItem, matching: .images) {
                HStack {
                    Label(settings.backgroundImageFilename == nil ? "壁紙画像を選ぶ" : "壁紙画像を変更",
                          systemImage: "photo")
                    Spacer()
                    if isLoadingBackground {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if settings.backgroundImageFilename != nil {
                Button(role: .destructive) {
                    settings = settingsStore.removeBackgroundImage()
                    previewBackgroundImage = nil
                    generatedImage = nil
                    generatedImageURL = nil
                    _Concurrency.Task {
                        await refreshPreview()
                    }
                } label: {
                    Label("背景画像を削除", systemImage: "trash")
                }
            }

            if settings.backgroundImageFilename == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("画像を選ばない場合の背景色")
                        .font(.subheadline)
                    backgroundColorSwatchGrid(selection: backgroundColorBinding)
                    ColorPicker("自由に色を選ぶ",
                                selection: colorPickerSelection(for: backgroundColorBinding),
                                supportsOpacity: false)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("壁紙")
        } footer: {
            Text("画像を選ぶと中央で切り抜いて予定を重ねます。画像を選ばない場合は単色背景になります。")
        }
    }

    private var shortcutSection: some View {
        Section {
            Button {
                openShortcutCreator()
            } label: {
                HStack {
                    Label("ショートカット作成画面を開く", systemImage: "square.grid.2x2")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                ShortcutSetupNote()

                ShortcutSetupStepRow(
                    number: 1,
                    title: "lifelifyのアクションを追加",
                    details: [
                        "作成画面で「アクションを追加」を押します。",
                        "検索欄に「lifelify」または「壁紙カレンダーを更新」と入力します。",
                        "検索結果から「壁紙カレンダーを更新」を選びます。"
                    ],
                    searchTerms: ["lifelify", "壁紙カレンダーを更新"]
                )

                ShortcutSetupStepRow(
                    number: 2,
                    title: "壁紙を設定アクションを追加",
                    details: [
                        "もう一度検索欄を開いて「壁紙を設定」と入力します。",
                        "iOS標準の「壁紙を設定」を選びます。",
                        "1つ目のアクションで作られた画像を、そのまま壁紙設定アクションに渡します。"
                    ],
                    searchTerms: ["壁紙を設定"]
                )

                ShortcutSetupStepRow(
                    number: 3,
                    title: "ロック画面だけに設定",
                    details: [
                        "「壁紙を設定」アクションの設定先をロック画面にします。",
                        "ホーム画面を変えたくない場合は、ホーム画面側を外します。",
                        "確認画面が毎回出る場合は、プレビュー表示や確認の設定をオフにします。"
                    ]
                )

                ShortcutSetupStepRow(
                    number: 4,
                    title: "自動更新にする",
                    details: [
                        "ショートカット単体で動くことを確認したら、ショートカットアプリの「オートメーション」を開きます。",
                        "毎朝の時刻、または「lifelifyを閉じたとき」をトリガーにします。",
                        "作ったショートカットを実行するように設定し、「実行の前に尋ねる」があればオフにします。"
                    ]
                )
            }
            .padding(.vertical, 4)
        } header: {
            Text("ショートカット")
        } footer: {
            Text("完成形は「壁紙カレンダーを更新」→「壁紙を設定」の2アクションです。予定・タスク・日付・設定が同じ場合は、作成済みの画像を再利用します。")
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

    private var layoutPresetBinding: Binding<WallpaperCalendarLayoutPreset> {
        Binding(
            get: {
                settings.layoutPreset
            },
            set: { newValue in
                guard settings.layoutPreset != newValue else { return }
                settings.layoutPreset = newValue
                settings.weekCount = newValue.weekCount
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

    private func persistSettingsChange() {
        settings.weekCount = settings.effectiveWeekCount
        settings.lastGeneratedFingerprint = nil
        settings.updatedAt = Date()
        settingsStore.save(settings)
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
        previewSnapshot = renderer.makePreviewSnapshot(settings: settings)
        previewBackgroundImage = settingsStore
            .backgroundImageURL(for: settings)
            .flatMap { UIImage(contentsOfFile: $0.path) }
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

    private func backgroundColorSwatchGrid(selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                ForEach(WallpaperCalendarBackgroundPalette.choices, id: \.self) { token in
                    Circle()
                        .fill(AppColorPalette.color(for: token))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .stroke(Color.secondary.opacity(token == WallpaperCalendarBackgroundPalette.whiteToken ? 0.35 : 0),
                                        lineWidth: 1)
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    isSameColorToken(selection.wrappedValue, token) ? Color.primary : Color.clear,
                                    lineWidth: 2
                                )
                        )
                        .onTapGesture {
                            selection.wrappedValue = token
                        }
                }
            }
            .padding(.vertical, 4)

            Text(selection.wrappedValue)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
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
}

private struct ShortcutSetupNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("ショートカットが必要な理由", systemImage: "questionmark.circle")
                .font(.subheadline.weight(.semibold))

            Text("lifelifyはロック画面用の画像を作ります。実際にロック画面へ反映する操作は、iOS標準の「壁紙を設定」アクションにつなぐ必要があります。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ShortcutSetupStepRow: View {
    let number: Int
    let title: String
    let details: [String]
    var searchTerms: [String] = []

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                ForEach(details, id: \.self) { detail in
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if searchTerms.isEmpty == false {
                    HStack(spacing: 6) {
                        ForEach(searchTerms, id: \.self) { term in
                            Text(term)
                                .font(.caption.monospaced())
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.14), in: Capsule())
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }
}

private struct WallpaperCalendarLockScreenPreview: View {
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
