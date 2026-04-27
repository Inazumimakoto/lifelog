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
                    WallpaperCalendarRenderView(
                        snapshot: previewSnapshot,
                        settings: settings,
                        backgroundImage: previewBackgroundImage,
                        isDarkAppearance: resolvedDarkAppearance
                    )
                    .frame(width: 260, height: 563)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
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
            Picker("表示範囲", selection: binding(\.weekCount)) {
                ForEach(WallpaperCalendarWeekCount.allCases) { weekCount in
                    Text(weekCount.title).tag(weekCount)
                }
            }

            Picker("配置", selection: binding(\.layoutPreset)) {
                ForEach(WallpaperCalendarLayoutPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }

            Text(settings.layoutPreset.detail)
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

    private func persistSettingsChange() {
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
