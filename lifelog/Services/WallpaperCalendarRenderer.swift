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
            return "壁紙カレンダー画像を作成できませんでした。"
        case .failedToEncodeImage:
            return "壁紙カレンダー画像を書き出せませんでした。"
        }
    }
}

@MainActor
final class WallpaperCalendarRenderer {
    private static let renderVersion = 6

    private let settingsStore: WallpaperCalendarSettingsStore
    private let dataProvider: WallpaperCalendarDataProvider
    private let fileManager: FileManager
    private let gridSpacing: CGFloat = 4
    private let cellTopPadding: CGFloat = 4
    private let cellHeight: CGFloat = 88
    private let dateRowHeight: CGFloat = 18
    private let previewRowHeight: CGFloat = 14
    private let cellRowSpacing: CGFloat = 2
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
                             now: Date = Date()) -> WallpaperCalendarSnapshot {
        dataProvider.makeSnapshot(settings: settings, now: now)
    }

    func resolveDarkAppearance(settings: WallpaperCalendarSettings,
                               hasBackgroundImage: Bool) -> Bool {
        hasBackgroundImage || WallpaperCalendarBackgroundPalette.isDark(settings.backgroundColorToken)
    }

    private func renderImage(snapshot: WallpaperCalendarSnapshot,
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
            backgroundImage.draw(in: aspectFillRect(
                imageSize: backgroundImage.size,
                targetRect: rect,
                adjustment: settings.backgroundAdjustment
            ))
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
        let textShadow = makeTextShadow(isEnabled: isDarkAppearance)
        let cellWidth = calendarGridCellWidth(for: layout.width)
        let gridTop = layout.y + layout.weekdayHeaderHeight + gridSpacing
        let chipAlpha: CGFloat = hasBackgroundImage ? 0.62 : 0.30

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
                            settings: settings,
                            primaryColor: primaryColor,
                            secondaryColor: secondaryColor,
                            chipAlpha: chipAlpha,
                            textShadow: textShadow)
            }
        }

        for (weekIndex, week) in snapshot.weeks.enumerated() {
            for segment in week.multiDayLayout.segments {
                let spanLength = segment.endColumn - segment.startColumn + 1
                let x = layout.x + CGFloat(segment.startColumn) * (cellWidth + gridSpacing)
                let y = gridTop + CGFloat(weekIndex) * (cellHeight + gridSpacing) + multiDayOverlayRowY(lane: segment.lane)
                let width = CGFloat(spanLength) * cellWidth + CGFloat(max(0, spanLength - 1)) * gridSpacing
                let rect = CGRect(x: x, y: y, width: max(0, width), height: previewRowHeight)
                let title = segment.continuesBeforeWeek ? " " : segment.displayTitle(privacyMode: settings.privacyMode)
                drawPreviewBar(title: title,
                               color: UIColor(segment.color),
                               rect: rect,
                               leadingRadius: segment.continuesBeforeWeek ? 0 : previewRowCornerRadius,
                               trailingRadius: segment.continuesAfterWeek ? 0 : previewRowCornerRadius,
                               textColor: primaryColor,
                               alpha: chipAlpha,
                               textShadow: textShadow)
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
                             settings: WallpaperCalendarSettings,
                             primaryColor: UIColor,
                             secondaryColor: UIColor,
                             chipAlpha: CGFloat,
                             textShadow: NSShadow?) {
        let calendar = WallpaperCalendarDataProvider.calendar
        if calendar.isDateInToday(day.date) {
            UIColor.systemBlue.withAlphaComponent(0.28).setFill()
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
            let rowY = rect.minY + cellTopPadding + dateRowHeight + cellRowSpacing +
                CGFloat(rowIndex) * (previewRowHeight + cellRowSpacing)
            let rowRect = CGRect(x: rect.minX, y: rowY, width: rect.width, height: previewRowHeight)
            switch rowContent {
            case .multiDayPlaceholder, .empty:
                break
            case .overflow(let count):
                drawText("+\(count)",
                         in: rowRect.insetBy(dx: 4, dy: 0),
                         font: UIFont.systemFont(ofSize: 9),
                         color: secondaryColor,
                         alignment: .left,
                         shadow: textShadow)
            case .item(let item):
                drawPreviewBar(title: item.displayTitle(privacyMode: settings.privacyMode),
                               color: UIColor(item.color),
                               rect: rowRect,
                               leadingRadius: previewRowCornerRadius,
                               trailingRadius: previewRowCornerRadius,
                               textColor: primaryColor,
                               alpha: chipAlpha,
                               textShadow: textShadow)
            }
        }
    }

    private func drawPreviewBar(title: String,
                                color: UIColor,
                                rect: CGRect,
                                leadingRadius: CGFloat,
                                trailingRadius: CGFloat,
                                textColor: UIColor,
                                alpha: CGFloat,
                                textShadow: NSShadow?) {
        guard rect.width > 0, rect.height > 0 else { return }
        color.withAlphaComponent(alpha).setFill()
        previewBarPath(rect: rect, leadingRadius: leadingRadius, trailingRadius: trailingRadius).fill()
        drawText(title,
                 in: rect.insetBy(dx: 3, dy: 1.5),
                 font: previewFont,
                 color: textColor,
                 alignment: .left,
                 shadow: textShadow)
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

    private func makeTextShadow(isEnabled: Bool) -> NSShadow? {
        guard isEnabled else { return nil }
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.50)
        shadow.shadowBlurRadius = 1.2
        shadow.shadowOffset = CGSize(width: 0, height: 1)
        return shadow
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

    private func multiDayOverlayRowY(lane: Int) -> CGFloat {
        cellTopPadding +
        dateRowHeight +
        cellRowSpacing +
        CGFloat(lane) * (previewRowHeight + cellRowSpacing)
    }

    private func aspectFillRect(imageSize: CGSize,
                                targetRect: CGRect,
                                adjustment: WallpaperCalendarBackgroundAdjustment) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return targetRect }
        let resolvedAdjustment = adjustment.clamped(for: imageSize, canvasSize: targetRect.size)
        let scale = max(targetRect.width / imageSize.width, targetRect.height / imageSize.height) *
            CGFloat(resolvedAdjustment.scale)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let x = targetRect.midX - width / 2 + CGFloat(resolvedAdjustment.offsetX) * targetRect.width
        let y = targetRect.midY - height / 2 + CGFloat(resolvedAdjustment.offsetY) * targetRect.height
        return clampedBackgroundRect(
            CGRect(x: x, y: y, width: width, height: height),
            targetRect: targetRect
        )
    }

    private func clampedBackgroundRect(_ rect: CGRect, targetRect: CGRect) -> CGRect {
        let x = rect.width > targetRect.width
            ? min(max(rect.minX, targetRect.maxX - rect.width), targetRect.minX)
            : targetRect.midX - rect.width / 2
        let y = rect.height > targetRect.height
            ? min(max(rect.minY, targetRect.maxY - rect.height), targetRect.minY)
            : targetRect.midY - rect.height / 2
        return CGRect(
            x: x,
            y: y,
            width: rect.width,
            height: rect.height
        )
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

    private var previewFont: UIFont {
        let baseFont = UIFont.systemFont(ofSize: 9, weight: .medium)
        let descriptor = baseFont.fontDescriptor
        let traits = (descriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]) ?? [:]
        var condensedTraits = traits
        condensedTraits[.width] = -0.2
        let condensedDescriptor = descriptor.addingAttributes([.traits: condensedTraits])
        return UIFont(descriptor: condensedDescriptor, size: 9)
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
            weekCount: settings.effectiveWeekCount.rawValue,
            layoutPreset: settings.layoutPreset.rawValue,
            privacyMode: settings.privacyMode.rawValue,
            backgroundColorToken: settings.backgroundColorToken,
            backgroundAdjustment: settings.backgroundAdjustment,
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

private struct WallpaperCalendarDrawingLayout {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let weekdayHeaderHeight: CGFloat
}

private struct RenderFingerprintPayload: Codable {
    let renderVersion: Int
    let weekCount: Int
    let layoutPreset: String
    let privacyMode: String
    let backgroundColorToken: String
    let backgroundAdjustment: WallpaperCalendarBackgroundAdjustment
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
