//
//  WallpaperCalendarSettings.swift
//  lifelog
//
//  Created by Codex on 2026/04/27.
//

import Foundation
import CoreGraphics

struct WallpaperCalendarSettings: Codable, Equatable {
    var weekCount: WallpaperCalendarWeekCount
    var layoutPreset: WallpaperCalendarLayoutPreset
    var privacyMode: WallpaperCalendarPrivacyMode
    var appearance: WallpaperCalendarAppearance
    var backgroundColorToken: String
    var backgroundImageFilename: String?
    var backgroundAdjustment: WallpaperCalendarBackgroundAdjustment
    var lastGeneratedFingerprint: String?
    var lastGeneratedFilename: String?
    var updatedAt: Date

    init(weekCount: WallpaperCalendarWeekCount = .three,
         layoutPreset: WallpaperCalendarLayoutPreset = .standard,
         privacyMode: WallpaperCalendarPrivacyMode = .details,
         appearance: WallpaperCalendarAppearance = .system,
         backgroundColorToken: String = WallpaperCalendarBackgroundPalette.defaultToken,
         backgroundImageFilename: String? = nil,
         backgroundAdjustment: WallpaperCalendarBackgroundAdjustment = .defaultValue,
         lastGeneratedFingerprint: String? = nil,
         lastGeneratedFilename: String? = nil,
         updatedAt: Date = Date()) {
        self.weekCount = weekCount
        self.layoutPreset = layoutPreset
        self.privacyMode = privacyMode
        self.appearance = appearance
        self.backgroundColorToken = backgroundColorToken
        self.backgroundImageFilename = backgroundImageFilename
        self.backgroundAdjustment = backgroundAdjustment
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
        case backgroundColorToken
        case backgroundImageFilename
        case backgroundAdjustment
        case lastGeneratedFingerprint
        case lastGeneratedFilename
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weekCount = try container.decodeIfPresent(WallpaperCalendarWeekCount.self, forKey: .weekCount) ?? .three
        let decodedLayoutPreset = try container.decodeIfPresent(WallpaperCalendarLayoutPreset.self, forKey: .layoutPreset) ?? .standard
        layoutPreset = decodedLayoutPreset.normalized
        privacyMode = try container.decodeIfPresent(WallpaperCalendarPrivacyMode.self, forKey: .privacyMode) ?? .details
        appearance = try container.decodeIfPresent(WallpaperCalendarAppearance.self, forKey: .appearance) ?? .system
        backgroundColorToken = try container.decodeIfPresent(String.self, forKey: .backgroundColorToken)
            ?? Self.backgroundColorToken(for: appearance)
        backgroundImageFilename = try container.decodeIfPresent(String.self, forKey: .backgroundImageFilename)
        backgroundAdjustment = try container.decodeIfPresent(WallpaperCalendarBackgroundAdjustment.self, forKey: .backgroundAdjustment)
            ?? .defaultValue
        lastGeneratedFingerprint = try container.decodeIfPresent(String.self, forKey: .lastGeneratedFingerprint)
        lastGeneratedFilename = try container.decodeIfPresent(String.self, forKey: .lastGeneratedFilename)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    var effectiveWeekCount: WallpaperCalendarWeekCount {
        layoutPreset.weekCount
    }

    private static func backgroundColorToken(for appearance: WallpaperCalendarAppearance) -> String {
        switch appearance {
        case .light:
            return WallpaperCalendarBackgroundPalette.whiteToken
        case .system, .dark:
            return WallpaperCalendarBackgroundPalette.defaultToken
        }
    }
}

struct WallpaperCalendarBackgroundAdjustment: Codable, Equatable {
    static let defaultValue = WallpaperCalendarBackgroundAdjustment()
    static let maxScale = 3.0

    var scale: Double
    var offsetX: Double
    var offsetY: Double

    init(scale: Double = 1.0,
         offsetX: Double = 0,
         offsetY: Double = 0) {
        self.scale = scale
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    // docs/requirements.md §4.11: allow the entire photo to fit above its blurred background.
    static func minimumScale(for imageSize: CGSize, canvasSize: CGSize) -> Double {
        guard let fillScale = aspectFillScale(for: imageSize, canvasSize: canvasSize) else { return 1 }
        let fitScale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let result = Double(fitScale / fillScale)
        return result.isFinite && result > 0 ? min(1, result) : 1
    }

    func clamped(for imageSize: CGSize, canvasSize: CGSize) -> WallpaperCalendarBackgroundAdjustment {
        let minimumScale = Self.minimumScale(for: imageSize, canvasSize: canvasSize)
        let finiteScale = scale.isFinite ? scale : Self.defaultValue.scale
        let resolvedScale = min(max(finiteScale, minimumScale), Self.maxScale)
        guard let scaledSize = Self.scaledImageSize(for: imageSize, canvasSize: canvasSize, scale: resolvedScale) else {
            return WallpaperCalendarBackgroundAdjustment(scale: resolvedScale)
        }

        let maxOffsetX = Self.maximumOffset(imageLength: scaledSize.width, canvasLength: canvasSize.width)
        let maxOffsetY = Self.maximumOffset(imageLength: scaledSize.height, canvasLength: canvasSize.height)
        let finiteOffsetX = offsetX.isFinite ? offsetX : 0
        let finiteOffsetY = offsetY.isFinite ? offsetY : 0

        return WallpaperCalendarBackgroundAdjustment(
            scale: resolvedScale,
            offsetX: min(max(finiteOffsetX, -maxOffsetX), maxOffsetX),
            offsetY: min(max(finiteOffsetY, -maxOffsetY), maxOffsetY)
        )
    }

    func imageRect(for imageSize: CGSize, in canvasRect: CGRect) -> CGRect {
        guard Self.isValidSize(canvasRect.size),
              canvasRect.minX.isFinite, canvasRect.minY.isFinite,
              canvasRect.maxX.isFinite, canvasRect.maxY.isFinite else { return .zero }
        let adjustment = clamped(for: imageSize, canvasSize: canvasRect.size)
        guard let scaledSize = Self.scaledImageSize(for: imageSize, canvasSize: canvasRect.size, scale: adjustment.scale) else {
            return canvasRect
        }
        let rect = CGRect(
            x: canvasRect.midX - scaledSize.width / 2 + CGFloat(adjustment.offsetX) * canvasRect.width,
            y: canvasRect.midY - scaledSize.height / 2 + CGFloat(adjustment.offsetY) * canvasRect.height,
            width: scaledSize.width,
            height: scaledSize.height
        )
        guard rect.minX.isFinite, rect.minY.isFinite,
              rect.maxX.isFinite, rect.maxY.isFinite else { return canvasRect }
        return rect
    }

    private static func isValidSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    private static func aspectFillScale(for imageSize: CGSize, canvasSize: CGSize) -> CGFloat? {
        guard isValidSize(imageSize), isValidSize(canvasSize) else { return nil }
        let scale = max(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        return scale.isFinite && scale > 0 ? scale : nil
    }

    private static func scaledImageSize(for imageSize: CGSize, canvasSize: CGSize, scale: Double) -> CGSize? {
        guard let fillScale = aspectFillScale(for: imageSize, canvasSize: canvasSize) else { return nil }
        let size = CGSize(width: imageSize.width * fillScale * scale,
                          height: imageSize.height * fillScale * scale)
        return isValidSize(size) ? size : nil
    }

    private static func maximumOffset(imageLength: CGFloat, canvasLength: CGFloat) -> Double {
        let overflow = max(0, (imageLength - canvasLength) / 2)
        let margin = min(canvasLength, imageLength) * 0.25
        let offset = Double((overflow + margin) / canvasLength)
        return offset.isFinite ? offset : 0
    }
}

enum WallpaperCalendarBackgroundPalette {
    static let defaultToken = "#000000"
    static let whiteToken = "#FFFFFF"
    static let choices: [String] = [
        defaultToken,
        whiteToken,
        "#111827",
        "#1F2937"
    ] + AppColorPalette.presets

    static func isDark(_ token: String) -> Bool {
        guard let rgb = rgbComponents(from: token) else {
            return true
        }
        let luminance = (0.2126 * rgb.red) + (0.7152 * rgb.green) + (0.0722 * rgb.blue)
        return luminance < 0.58
    }

    private static func rgbComponents(from token: String) -> (red: Double, green: Double, blue: Double)? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }
        let hex = String(trimmed.dropFirst())
        guard hex.count == 6,
              let value = Int(hex, radix: 16)
        else {
            return nil
        }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        return (red, green, blue)
    }
}

enum WallpaperCalendarWeekCount: Int, Codable, CaseIterable, Identifiable {
    case two = 2
    case three = 3
    case four = 4

    var id: Int { rawValue }

    var title: String {
        String(localized: "\(rawValue)週")
    }
}

enum WallpaperCalendarLayoutPreset: String, Codable, CaseIterable, Identifiable {
    case standard
    case avoidWidgets
    case avoidMedia
    case avoidWidgetsAndMedia

    static let selectableCases: [WallpaperCalendarLayoutPreset] = [
        .standard,
        .avoidMedia,
        .avoidWidgetsAndMedia
    ]

    var id: String { rawValue }

    var normalized: WallpaperCalendarLayoutPreset {
        self == .avoidWidgets ? .standard : self
    }

    var title: String {
        switch self {
        case .standard, .avoidWidgets:
            return String(localized: "標準")
        case .avoidMedia:
            return String(localized: "再生バーあり")
        case .avoidWidgetsAndMedia:
            return String(localized: "両方あり")
        }
    }

    var detail: String {
        switch self {
        case .standard, .avoidWidgets:
            return String(localized: "時計とウィジェットの下に4週分を表示")
        case .avoidMedia:
            return String(localized: "下の再生バー領域を避けて3週分を表示")
        case .avoidWidgetsAndMedia:
            return String(localized: "上下どちらも避けて2週分を表示")
        }
    }

    var weekCount: WallpaperCalendarWeekCount {
        switch self {
        case .standard, .avoidWidgets:
            return .four
        case .avoidMedia:
            return .three
        case .avoidWidgetsAndMedia:
            return .two
        }
    }

    var showsWidgetPlaceholder: Bool {
        self == .avoidWidgetsAndMedia
    }

    var showsMediaPlaceholder: Bool {
        self == .avoidMedia || self == .avoidWidgetsAndMedia
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
            return String(localized: "予定名")
        case .categoryOnly:
            return String(localized: "カテゴリのみ")
        case .hidden:
            return String(localized: "非表示")
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
            return String(localized: "端末に合わせる")
        case .dark:
            return String(localized: "黒")
        case .light:
            return String(localized: "白")
        }
    }
}
