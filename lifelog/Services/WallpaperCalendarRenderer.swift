//
//  WallpaperCalendarRenderer.swift
//  lifelog
//
//  Created by Codex on 2026/04/27.
//

import CryptoKit
import Foundation
import SwiftUI
import UIKit

enum WallpaperCalendarRendererError: LocalizedError {
    case failedToRenderImage
    case failedToEncodePNG

    var errorDescription: String? {
        switch self {
        case .failedToRenderImage:
            return "壁紙カレンダー画像を作成できませんでした。"
        case .failedToEncodePNG:
            return "壁紙カレンダー画像を書き出せませんでした。"
        }
    }
}

@MainActor
final class WallpaperCalendarRenderer {
    private let settingsStore: WallpaperCalendarSettingsStore
    private let dataProvider: WallpaperCalendarDataProvider
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.settingsStore = .shared
        self.dataProvider = WallpaperCalendarDataProvider()
        self.fileManager = fileManager
    }

    init(settingsStore: WallpaperCalendarSettingsStore,
         dataProvider: WallpaperCalendarDataProvider,
         fileManager: FileManager = .default) {
        self.settingsStore = settingsStore
        self.dataProvider = dataProvider
        self.fileManager = fileManager
    }

    func render(force: Bool = false,
                now: Date = Date(),
                screenSize: CGSize? = nil,
                scale: CGFloat? = nil) throws -> URL {
        let resolvedScreenSize = screenSize ?? UIScreen.main.bounds.size
        let resolvedScale = scale ?? UIScreen.main.scale
        let settings = settingsStore.load()
        let snapshot = dataProvider.makeSnapshot(settings: settings, now: now)
        let backgroundURL = settingsStore.backgroundImageURL(for: settings)
        let backgroundImage = backgroundURL.flatMap { UIImage(contentsOfFile: $0.path) }
        let isDarkAppearance = resolveDarkAppearance(settings.appearance)
        let fingerprint = try makeFingerprint(
            settings: settings,
            snapshot: snapshot,
            backgroundURL: backgroundURL,
            screenSize: resolvedScreenSize,
            scale: resolvedScale,
            isDarkAppearance: isDarkAppearance
        )

        if force == false,
           settings.lastGeneratedFingerprint == fingerprint,
           let existingURL = settingsStore.generatedImageURL(for: settings) {
            return existingURL
        }

        let renderView = WallpaperCalendarRenderView(
            snapshot: snapshot,
            settings: settings,
            backgroundImage: backgroundImage,
            isDarkAppearance: isDarkAppearance
        )
        .frame(width: resolvedScreenSize.width, height: resolvedScreenSize.height)
        .environment(\.colorScheme, isDarkAppearance ? .dark : .light)

        let renderer = ImageRenderer(content: renderView)
        renderer.scale = resolvedScale
        renderer.isOpaque = true

        guard let image = renderer.uiImage else {
            throw WallpaperCalendarRendererError.failedToRenderImage
        }
        guard let data = image.pngData() else {
            throw WallpaperCalendarRendererError.failedToEncodePNG
        }

        let outputURL = try settingsStore.latestGeneratedImageURL()
        try data.write(to: outputURL, options: [.atomic])
        _ = settingsStore.saveGeneratedMetadata(fingerprint: fingerprint)
        return outputURL
    }

    func makePreviewSnapshot(settings: WallpaperCalendarSettings,
                             now: Date = Date()) -> WallpaperCalendarSnapshot {
        dataProvider.makeSnapshot(settings: settings, now: now)
    }

    func resolveDarkAppearance(_ appearance: WallpaperCalendarAppearance) -> Bool {
        switch appearance {
        case .system:
            return UITraitCollection.current.userInterfaceStyle != .light
        case .dark:
            return true
        case .light:
            return false
        }
    }

    private func makeFingerprint(settings: WallpaperCalendarSettings,
                                 snapshot: WallpaperCalendarSnapshot,
                                 backgroundURL: URL?,
                                 screenSize: CGSize,
                                 scale: CGFloat,
                                 isDarkAppearance: Bool) throws -> String {
        let backgroundMetadata = backgroundURL.flatMap { url -> BackgroundMetadata? in
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
            let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970
            let fileSize = (attributes[.size] as? NSNumber)?.int64Value
            return BackgroundMetadata(path: url.lastPathComponent, modifiedAt: modifiedAt, fileSize: fileSize)
        }
        let payload = RenderFingerprintPayload(
            weekCount: settings.weekCount.rawValue,
            layoutPreset: settings.layoutPreset.rawValue,
            privacyMode: settings.privacyMode.rawValue,
            appearance: settings.appearance.rawValue,
            isDarkAppearance: isDarkAppearance,
            screenWidth: Double(screenSize.width),
            screenHeight: Double(screenSize.height),
            scale: Double(scale),
            background: backgroundMetadata,
            calendar: snapshot.fingerprintPayload
        )
        let data = try JSONEncoder().encode(payload)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct RenderFingerprintPayload: Codable {
    let weekCount: Int
    let layoutPreset: String
    let privacyMode: String
    let appearance: String
    let isDarkAppearance: Bool
    let screenWidth: Double
    let screenHeight: Double
    let scale: Double
    let background: BackgroundMetadata?
    let calendar: WallpaperCalendarFingerprintPayload
}

private struct BackgroundMetadata: Codable {
    let path: String
    let modifiedAt: TimeInterval?
    let fileSize: Int64?
}
