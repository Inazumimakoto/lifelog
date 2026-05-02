//
//  WallpaperCalendarSettingsStore.swift
//  lifelog
//
//  Created by Codex on 2026/04/27.
//

import Foundation

final class WallpaperCalendarSettingsStore {
    static let shared = WallpaperCalendarSettingsStore()

    private let settingsKey = "WallpaperCalendar_Settings_V1"
    private let directoryName = "WallpaperCalendar"
    private let backgroundDirectoryName = "Backgrounds"
    private let generatedDirectoryName = "Generated"
    private let generatedFilename = "wallpaper-calendar-latest.jpg"
    private let defaults: UserDefaults
    private let fileManager: FileManager

    init(defaults: UserDefaults = UserDefaults(suiteName: PersistenceController.appGroupIdentifier) ?? .standard,
         fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
    }

    func load() -> WallpaperCalendarSettings {
        guard let data = defaults.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode(WallpaperCalendarSettings.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    func save(_ settings: WallpaperCalendarSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: settingsKey)
    }

    func update(_ transform: (inout WallpaperCalendarSettings) -> Void) -> WallpaperCalendarSettings {
        var settings = load()
        transform(&settings)
        settings.updatedAt = Date()
        save(settings)
        return settings
    }

    func saveBackgroundImageData(_ data: Data) throws -> WallpaperCalendarSettings {
        let directory = try ensureBackgroundDirectory()
        let filename = "background-\(UUID().uuidString).jpg"
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic])

        return update { settings in
            removeFileIfPresent(filename: settings.backgroundImageFilename, in: directory)
            settings.backgroundImageFilename = filename
            settings.backgroundAdjustment = .defaultValue
            settings.lastGeneratedFingerprint = nil
        }
    }

    func removeBackgroundImage() -> WallpaperCalendarSettings {
        update { settings in
            if let filename = settings.backgroundImageFilename,
               let directory = try? ensureBackgroundDirectory() {
                removeFileIfPresent(filename: filename, in: directory)
            }
            settings.backgroundImageFilename = nil
            settings.backgroundAdjustment = .defaultValue
            settings.lastGeneratedFingerprint = nil
        }
    }

    func backgroundImageURL(for settings: WallpaperCalendarSettings? = nil) -> URL? {
        let current = settings ?? load()
        guard let filename = current.backgroundImageFilename,
              let directory = try? ensureBackgroundDirectory()
        else {
            return nil
        }
        let url = directory.appendingPathComponent(filename)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func generatedImageURL(for settings: WallpaperCalendarSettings? = nil) -> URL? {
        let current = settings ?? load()
        guard let filename = current.lastGeneratedFilename,
              let directory = try? ensureGeneratedDirectory()
        else {
            return nil
        }
        let url = directory.appendingPathComponent(filename)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func latestGeneratedImageURL() throws -> URL {
        try ensureGeneratedDirectory().appendingPathComponent(generatedFilename)
    }

    func saveGeneratedMetadata(fingerprint: String) -> WallpaperCalendarSettings {
        update { settings in
            settings.lastGeneratedFingerprint = fingerprint
            settings.lastGeneratedFilename = generatedFilename
        }
    }

    func invalidateGeneratedImage() -> WallpaperCalendarSettings {
        update { settings in
            settings.lastGeneratedFingerprint = nil
            settings.lastGeneratedFilename = nil
        }
    }

    private func ensureBackgroundDirectory() throws -> URL {
        let url = try ensureRootDirectory().appendingPathComponent(backgroundDirectoryName, isDirectory: true)
        try ensureDirectory(at: url)
        return url
    }

    private func ensureGeneratedDirectory() throws -> URL {
        let url = try ensureRootDirectory().appendingPathComponent(generatedDirectoryName, isDirectory: true)
        try ensureDirectory(at: url)
        return url
    }

    private func ensureRootDirectory() throws -> URL {
        let baseURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: PersistenceController.appGroupIdentifier)
            ?? URL.applicationSupportDirectory
        let url = baseURL.appendingPathComponent(directoryName, isDirectory: true)
        try ensureDirectory(at: url)
        return url
    }

    private func ensureDirectory(at url: URL) throws {
        if fileManager.fileExists(atPath: url.path) == false {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func removeFileIfPresent(filename: String?, in directory: URL) {
        guard let filename else { return }
        let url = directory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
    }
}
