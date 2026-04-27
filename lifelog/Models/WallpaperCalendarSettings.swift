//
//  WallpaperCalendarSettings.swift
//  lifelog
//
//  Created by Codex on 2026/04/27.
//

import Foundation

struct WallpaperCalendarSettings: Codable, Equatable {
    var weekCount: WallpaperCalendarWeekCount
    var layoutPreset: WallpaperCalendarLayoutPreset
    var privacyMode: WallpaperCalendarPrivacyMode
    var appearance: WallpaperCalendarAppearance
    var backgroundImageFilename: String?
    var lastGeneratedFingerprint: String?
    var lastGeneratedFilename: String?
    var updatedAt: Date

    init(weekCount: WallpaperCalendarWeekCount = .three,
         layoutPreset: WallpaperCalendarLayoutPreset = .standard,
         privacyMode: WallpaperCalendarPrivacyMode = .details,
         appearance: WallpaperCalendarAppearance = .system,
         backgroundImageFilename: String? = nil,
         lastGeneratedFingerprint: String? = nil,
         lastGeneratedFilename: String? = nil,
         updatedAt: Date = Date()) {
        self.weekCount = weekCount
        self.layoutPreset = layoutPreset
        self.privacyMode = privacyMode
        self.appearance = appearance
        self.backgroundImageFilename = backgroundImageFilename
        self.lastGeneratedFingerprint = lastGeneratedFingerprint
        self.lastGeneratedFilename = lastGeneratedFilename
        self.updatedAt = updatedAt
    }

    static let `default` = WallpaperCalendarSettings()

    private enum CodingKeys: String, CodingKey {
        case weekCount
        case layoutPreset
        case privacyMode
        case appearance
        case backgroundImageFilename
        case lastGeneratedFingerprint
        case lastGeneratedFilename
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weekCount = try container.decodeIfPresent(WallpaperCalendarWeekCount.self, forKey: .weekCount) ?? .three
        layoutPreset = try container.decodeIfPresent(WallpaperCalendarLayoutPreset.self, forKey: .layoutPreset) ?? .standard
        privacyMode = try container.decodeIfPresent(WallpaperCalendarPrivacyMode.self, forKey: .privacyMode) ?? .details
        appearance = try container.decodeIfPresent(WallpaperCalendarAppearance.self, forKey: .appearance) ?? .system
        backgroundImageFilename = try container.decodeIfPresent(String.self, forKey: .backgroundImageFilename)
        lastGeneratedFingerprint = try container.decodeIfPresent(String.self, forKey: .lastGeneratedFingerprint)
        lastGeneratedFilename = try container.decodeIfPresent(String.self, forKey: .lastGeneratedFilename)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

enum WallpaperCalendarWeekCount: Int, Codable, CaseIterable, Identifiable {
    case two = 2
    case three = 3
    case four = 4

    var id: Int { rawValue }

    var title: String {
        "\(rawValue)週"
    }
}

enum WallpaperCalendarLayoutPreset: String, Codable, CaseIterable, Identifiable {
    case standard
    case avoidWidgets
    case avoidMedia
    case avoidWidgetsAndMedia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard:
            return "標準"
        case .avoidWidgets:
            return "ウィジェットあり"
        case .avoidMedia:
            return "再生バーあり"
        case .avoidWidgetsAndMedia:
            return "両方あり"
        }
    }

    var detail: String {
        switch self {
        case .standard:
            return "時計の下に大きめに表示"
        case .avoidWidgets:
            return "上のウィジェット領域を避ける"
        case .avoidMedia:
            return "下の再生バー領域を避ける"
        case .avoidWidgetsAndMedia:
            return "上下どちらも避ける"
        }
    }
}

enum WallpaperCalendarPrivacyMode: String, Codable, CaseIterable, Identifiable {
    case details
    case categoryOnly
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .details:
            return "予定名"
        case .categoryOnly:
            return "カテゴリのみ"
        case .hidden:
            return "非表示"
        }
    }
}

enum WallpaperCalendarAppearance: String, Codable, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "端末に合わせる"
        case .dark:
            return "黒"
        case .light:
            return "白"
        }
    }
}
