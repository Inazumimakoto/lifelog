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
    case failedToEncodeImage

    var errorDescription: String? {
        switch self {
        case .failedToRenderImage:
            return String(localized: "壁紙カレンダー画像を作成できませんでした。")
        case .failedToEncodeImage:
            return String(localized: "壁紙カレンダー画像を書き出せませんでした。")
        }
    }
}

@MainActor
final class WallpaperCalendarRenderer {
    private static let renderVersion = 11

    private let settingsStore: WallpaperCalendarSettingsStore
    private let dataProvider: WallpaperCalendarDataProvider
    private let fileManager: FileManager
    private let gridSpacing: CGFloat = 4
    private let cellTopPadding = WallpaperCalendarGridStyle.topPadding
    private let cellHeight = WallpaperCalendarGridStyle.cellHeight
    private let dateRowHeight = WallpaperCalendarGridStyle.dateHeight
    private let cellCornerRadius: CGFloat = 10
    private let previewRowCornerRadius: CGFloat = 4

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

    nonisolated deinit {}

    func render(force: Bool = false,
                now: Date = Date(),
                screenSize: CGSize? = nil,
                scale: CGFloat? = nil) throws -> URL {
        let resolvedScreenSize = screenSize ?? WallpaperCalendarCanvas.size
        let resolvedScale = scale ?? WallpaperCalendarCanvas.scale
        let settings = settingsStore.load()
        let snapshot = try dataProvider.makeSnapshot(settings: settings, now: now)
        let backgroundURL = settingsStore.backgroundImageURL(for: settings)
        let backgroundImage = backgroundURL.flatMap { UIImage(contentsOfFile: $0.path) }
        let isDarkAppearance = resolveDarkAppearance(settings: settings, hasBackgroundImage: backgroundImage != nil)
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

        let image = renderImage(
            snapshot: snapshot,
            settings: settings,
            backgroundImage: backgroundImage,
            isDarkAppearance: isDarkAppearance,
            size: resolvedScreenSize,
            scale: resolvedScale
        )
        guard let data = image.jpegData(compressionQuality: 0.94) else {
            throw WallpaperCalendarRendererError.failedToEncodeImage
        }

        let outputURL = try settingsStore.latestGeneratedImageURL()
        try data.write(to: outputURL, options: [.atomic])
        _ = settingsStore.saveGeneratedMetadata(fingerprint: fingerprint)
        return outputURL
    }

    func makePreviewSnapshot(settings: WallpaperCalendarSettings,
                             now: Date = Date()) throws -> WallpaperCalendarSnapshot {
        try dataProvider.makeSnapshot(settings: settings, now: now)
    }

    func resolveDarkAppearance(settings: WallpaperCalendarSettings,
                               hasBackgroundImage: Bool) -> Bool {
        hasBackgroundImage || WallpaperCalendarBackgroundPalette.isDark(settings.backgroundColorToken)
    }

    func renderImage(snapshot: WallpaperCalendarSnapshot,
                     settings: WallpaperCalendarSettings,
                     backgroundImage: UIImage?,
                     isDarkAppearance: Bool,
                     size: CGSize,
                     scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let cgContext = context.cgContext
            drawBackground(in: CGRect(origin: .zero, size: size),
                           backgroundImage: backgroundImage,
                           settings: settings,
                           isDarkAppearance: isDarkAppearance)
            drawCalendar(snapshot: snapshot,
                         settings: settings,
                         isDarkAppearance: isDarkAppearance,
                         hasBackgroundImage: backgroundImage != nil,
                         size: size,
                         context: cgContext)
        }
    }

    private func drawBackground(in rect: CGRect,
                                backgroundImage: UIImage?,
                                settings: WallpaperCalendarSettings,
                                isDarkAppearance: Bool) {
        if let backgroundImage {
            let background = WallpaperCalendarPhotoBackground(image: backgroundImage)
            background.update(size: rect.size,
                              adjustment: settings.backgroundAdjustment,
                              contentsScale: UIGraphicsGetCurrentContext()?.ctm.a.magnitude ?? 1)
            if let context = UIGraphicsGetCurrentContext() {
                background.layer.render(in: context)
            }
            UIColor.black.withAlphaComponent(isDarkAppearance ? 0.18 : 0.08).setFill()
            UIBezierPath(rect: rect).fill()
        } else {
            UIColor(AppColorPalette.color(for: settings.backgroundColorToken)).setFill()
            UIBezierPath(rect: rect).fill()
        }
    }

    private func drawCalendar(snapshot: WallpaperCalendarSnapshot,
                              settings: WallpaperCalendarSettings,
                              isDarkAppearance: Bool,
                              hasBackgroundImage: Bool,
                              size: CGSize,
                              context: CGContext) {
        let layout = layoutMetrics(in: size, settings: settings)
        let primaryColor = isDarkAppearance
            ? UIColor.white
            : UIColor.black.withAlphaComponent(0.92)
        let secondaryColor = isDarkAppearance
            ? UIColor.white.withAlphaComponent(0.78)
            : UIColor.black.withAlphaComponent(0.62)
        let textShadow = isDarkAppearance ? WallpaperCalendarGridStyle.textShadow(color: .black.withAlphaComponent(0.50)) : nil
        let cellWidth = calendarGridCellWidth(for: layout.width)
        let gridTop = layout.y + layout.weekdayHeaderHeight + gridSpacing
        let gridStyle = snapshot.gridStyle

        drawWeekdayHeader(snapshot.weekdaySymbols,
                          layout: layout,
                          primaryColor: secondaryColor,
                          cellWidth: cellWidth,
                          textShadow: textShadow)

        for (weekIndex, week) in snapshot.weeks.enumerated() {
            let weekY = gridTop + CGFloat(weekIndex) * (cellHeight + gridSpacing)
            for (dayIndex, day) in week.days.enumerated() {
                let x = layout.x + CGFloat(dayIndex) * (cellWidth + gridSpacing)
                let cellRect = CGRect(x: x, y: weekY, width: cellWidth, height: cellHeight)
                drawDayCell(day,
                            in: cellRect,
                            snapshot: snapshot,
                            settings: settings,
                            primaryColor: primaryColor,
                            secondaryColor: secondaryColor,
                            gridStyle: gridStyle,
                            hasPhoto: hasBackgroundImage,
                            textShadow: textShadow)
            }
        }

        for (weekIndex, week) in snapshot.weeks.enumerated() {
            for segment in week.multiDayLayout.segments {
                let spanLength = segment.endColumn - segment.startColumn + 1
                let x = layout.x + CGFloat(segment.startColumn) * (cellWidth + gridSpacing)
                let y = gridTop + CGFloat(weekIndex) * (cellHeight + gridSpacing) + gridStyle.rowOffset(segment.lane)
                let width = CGFloat(spanLength) * cellWidth + CGFloat(max(0, spanLength - 1)) * gridSpacing
                let rect = CGRect(x: x, y: y, width: max(0, width), height: gridStyle.rowHeight)
                let title = gridStyle.title(for: segment, privacyMode: settings.privacyMode)
                let isToday = snapshot.isToday(week.days[segment.startColumn].date)
                let label = gridStyle.attributedTitle(title, category: segment.color, settings: settings,
                                                      hasPhoto: hasBackgroundImage, isToday: isToday)
                drawPreviewBar(title: label,
                               color: UIColor(segment.color),
                               rect: rect,
                               leadingRadius: segment.continuesBeforeWeek ? 0 : previewRowCornerRadius,
                               trailingRadius: segment.continuesAfterWeek ? 0 : previewRowCornerRadius,
                               gridStyle: gridStyle)
            }
        }

        context.setBlendMode(.normal)
    }

    private func drawWeekdayHeader(_ symbols: [String],
                                   layout: WallpaperCalendarDrawingLayout,
                                   primaryColor: UIColor,
                                   cellWidth: CGFloat,
                                   textShadow: NSShadow?) {
        let font = UIFont.systemFont(ofSize: 12)
        for (index, symbol) in symbols.enumerated() {
            let rect = CGRect(
                x: layout.x + CGFloat(index) * (cellWidth + gridSpacing),
                y: layout.y,
                width: cellWidth,
                height: layout.weekdayHeaderHeight
            )
            drawText(symbol, in: rect, font: font, color: primaryColor, alignment: .center, shadow: textShadow)
        }
    }

    private func drawDayCell(_ day: WallpaperCalendarDay,
                             in rect: CGRect,
                             snapshot: WallpaperCalendarSnapshot,
                             settings: WallpaperCalendarSettings,
                             primaryColor: UIColor,
                             secondaryColor: UIColor,
                             gridStyle: WallpaperCalendarGridStyle,
                             hasPhoto: Bool,
                             textShadow: NSShadow?) {
        let calendar = snapshot.calendar
        let isToday = snapshot.isToday(day.date)
        if isToday {
            UIColor(WallpaperCalendarGridStyle.todayColor).withAlphaComponent(WallpaperCalendarGridStyle.todayOpacity).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: cellCornerRadius).fill()
        }

        let weekday = calendar.component(.weekday, from: day.date)
        let dateColor = (weekday == 1 || weekday == 7) ? secondaryColor : primaryColor
        let dateRect = CGRect(
            x: rect.minX + 4,
            y: rect.minY + cellTopPadding,
            width: rect.width - 8,
            height: dateRowHeight
        )
        drawText(String(calendar.component(.day, from: day.date)),
                 in: dateRect,
                 font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                 color: dateColor,
                 alignment: .left,
                 shadow: textShadow)

        for (rowIndex, rowContent) in day.rowContents.enumerated() {
            let rowY = rect.minY + gridStyle.rowOffset(rowIndex)
            let rowRect = CGRect(x: rect.minX, y: rowY, width: rect.width, height: gridStyle.rowHeight)
            switch rowContent {
            case .multiDayPlaceholder, .empty:
                break
            case .overflow(let count):
                drawText("+\(count)",
                         in: rowRect.insetBy(dx: 4, dy: 0),
                         font: UIFont.systemFont(ofSize: gridStyle.preferences.fontSize),
                         color: secondaryColor,
                         alignment: .left,
                         shadow: textShadow)
            case .item(let item):
                let label = gridStyle.attributedTitle(item.displayTitle(privacyMode: settings.privacyMode),
                                                      category: item.color, settings: settings, hasPhoto: hasPhoto, isToday: isToday)
                drawPreviewBar(title: label,
                               color: UIColor(item.color),
                               rect: rowRect,
                               leadingRadius: previewRowCornerRadius,
                               trailingRadius: previewRowCornerRadius,
                               gridStyle: gridStyle)
            }
        }
    }

    private func drawPreviewBar(title: NSAttributedString,
                                color: UIColor,
                                rect: CGRect,
                                leadingRadius: CGFloat,
                                trailingRadius: CGFloat,
                                gridStyle: WallpaperCalendarGridStyle) {
        guard rect.width > 0, rect.height > 0 else { return }
        color.withAlphaComponent(color.cgColor.alpha * CGFloat(gridStyle.preferences.opacity)).setFill()
        previewBarPath(rect: rect, leadingRadius: leadingRadius, trailingRadius: trailingRadius).fill()
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.clip(to: rect)
        title.draw(at: CGPoint(x: rect.minX + 3, y: rect.midY - title.size().height / 2))
        context?.restoreGState()
    }

    private func drawText(_ text: String,
                          in rect: CGRect,
                          font: UIFont,
                          color: UIColor,
                          alignment: NSTextAlignment,
                          shadow: NSShadow? = nil) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byClipping
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        if let shadow {
            attributes[.shadow] = shadow
        }
        let currentContext = UIGraphicsGetCurrentContext()
        currentContext?.saveGState()
        currentContext?.clip(to: rect)
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin],
            attributes: attributes,
            context: nil
        )
        currentContext?.restoreGState()
    }

    private func layoutMetrics(in size: CGSize, settings: WallpaperCalendarSettings) -> WallpaperCalendarDrawingLayout {
        let horizontalPadding = max(26, size.width * 0.07)
        let width = max(0, size.width - horizontalPadding * 2)
        let weekdayHeaderHeight: CGFloat = 24
        return WallpaperCalendarDrawingLayout(
            x: horizontalPadding,
            y: layoutTop(in: size, settings: settings),
            width: width,
            weekdayHeaderHeight: weekdayHeaderHeight
        )
    }

    private func layoutTop(in size: CGSize, settings: WallpaperCalendarSettings) -> CGFloat {
        size.height * 0.36
    }

    private func calendarGridCellWidth(for totalWidth: CGFloat) -> CGFloat {
        let totalSpacing = gridSpacing * 6
        guard totalWidth > totalSpacing else { return 0 }
        return (totalWidth - totalSpacing) / 7
    }

    private func previewBarPath(rect: CGRect,
                                leadingRadius: CGFloat,
                                trailingRadius: CGFloat) -> UIBezierPath {
        var corners: UIRectCorner = []
        if leadingRadius > 0 {
            corners.formUnion([.topLeft, .bottomLeft])
        }
        if trailingRadius > 0 {
            corners.formUnion([.topRight, .bottomRight])
        }
        guard corners.isEmpty == false else {
            return UIBezierPath(rect: rect)
        }
        return UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: max(leadingRadius, trailingRadius), height: max(leadingRadius, trailingRadius))
        )
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
            renderVersion: Self.renderVersion,
            highlightedDay: snapshot.calendar.startOfDay(for: snapshot.generatedAt),
            weekCount: settings.effectiveWeekCount.rawValue,
            layoutPreset: settings.layoutPreset.rawValue,
            privacyMode: settings.privacyMode.rawValue,
            backgroundColorToken: settings.backgroundColorToken,
            backgroundAdjustment: settings.backgroundAdjustment,
            isDarkAppearance: isDarkAppearance,
            eventFontSize: snapshot.gridStyle.preferences.fontSize,
            categoryFillOpacity: snapshot.gridStyle.preferences.opacity,
            screenWidth: Double(screenSize.width),
            screenHeight: Double(screenSize.height),
            scale: Double(scale),
            background: backgroundMetadata,
            calendar: snapshot.fingerprintPayload
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(payload)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct WallpaperCalendarDrawingLayout {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let weekdayHeaderHeight: CGFloat
}

private struct RenderFingerprintPayload: Codable {
    let renderVersion: Int
    let highlightedDay: Date
    let weekCount: Int
    let layoutPreset: String
    let privacyMode: String
    let backgroundColorToken: String
    let backgroundAdjustment: WallpaperCalendarBackgroundAdjustment
    let isDarkAppearance: Bool
    let eventFontSize: CGFloat
    let categoryFillOpacity: Double
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
