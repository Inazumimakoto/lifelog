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

    var body: some View {
        Form {
            previewSection
            displaySection
            backgroundSection
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

            Picker("背景なしの色", selection: binding(\.appearance)) {
                ForEach(WallpaperCalendarAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
        }
    }

    private var backgroundSection: some View {
        Section {
            PhotosPicker(selection: $selectedBackgroundItem, matching: .images) {
                HStack {
                    Label(settings.backgroundImageFilename == nil ? "背景画像を追加" : "背景画像を変更",
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
        } header: {
            Text("背景画像")
        } footer: {
            Text("画像を追加すると、その画像を中央で切り抜いて予定を重ねます。画像なしの場合は黒または白の単色背景になります。")
        }
    }

    private var shortcutSection: some View {
        Section("ショートカット") {
            Label("壁紙カレンダーを更新", systemImage: "sparkles.rectangle.stack")
                .foregroundStyle(.primary)

            Text("ショートカットでこのアクションを実行し、続けて「壁紙を設定」に渡すとロック画面を更新できます。")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private func loadGeneratedImage() {
        let url = settingsStore.generatedImageURL(for: settings)
        generatedImageURL = url
        generatedImage = url.flatMap { UIImage(contentsOfFile: $0.path) }
    }

    private var resolvedDarkAppearance: Bool {
        switch settings.appearance {
        case .system:
            return UITraitCollection.current.userInterfaceStyle != .light
        case .dark:
            return true
        case .light:
            return false
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
