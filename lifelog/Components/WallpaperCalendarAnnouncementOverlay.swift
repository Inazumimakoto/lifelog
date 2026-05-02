//
//  WallpaperCalendarAnnouncementOverlay.swift
//  lifelog
//
//  Created by Codex on 2026/05/01.
//

import SwiftUI
import UIKit

struct WallpaperCalendarAnnouncementOverlayModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onDismiss: () -> Void
    let onOpenSettings: () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                WallpaperCalendarAnnouncementOverlay(
                    onDismiss: onDismiss,
                    onOpenSettings: onOpenSettings
                )
                .transition(.opacity)
                .zIndex(1000)
            }
        }
        .animation(.easeOut(duration: 0.18), value: isPresented)
    }
}

private struct WallpaperCalendarAnnouncementOverlay: View {
    let onDismiss: () -> Void
    let onOpenSettings: () -> Void

    private let settings: WallpaperCalendarSettings
    private let snapshot: WallpaperCalendarSnapshot
    private let backgroundImage = WallpaperCalendarDefaultPreviewBackground.image

    init(onDismiss: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void) {
        self.onDismiss = onDismiss
        self.onOpenSettings = onOpenSettings

        var settings = WallpaperCalendarSettings.default
        settings.layoutPreset = .avoidMedia
        settings.weekCount = settings.effectiveWeekCount
        settings.privacyMode = .details
        self.settings = settings
        self.snapshot = WallpaperCalendarAnnouncementDemo.makeSnapshot(settings: settings)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                preview

                Text("ロック画面からも予定を確認できるようになりました！")
                    .font(.headline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)

                Divider()

                HStack(spacing: 0) {
                    Button {
                        onDismiss()
                    } label: {
                        Text("今はしない")
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }

                    Divider()
                        .frame(height: 44)

                    Button {
                        onOpenSettings()
                    } label: {
                        Text("設定を開く")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                }
            }
            .padding(.top, 18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.22), radius: 28, x: 0, y: 18)
            .frame(maxWidth: 330)
            .padding(.horizontal, 28)
        }
        .accessibilityAddTraits(.isModal)
    }

    private var preview: some View {
        let width: CGFloat = 154
        let baseWidth: CGFloat = 393
        let baseHeight: CGFloat = 852
        let scale = width / baseWidth

        return WallpaperCalendarLockScreenPreview(
            snapshot: snapshot,
            settings: settings,
            backgroundImage: backgroundImage,
            isDarkAppearance: true
        )
        .frame(width: baseWidth, height: baseHeight)
        .scaleEffect(scale)
        .frame(width: width, height: baseHeight * scale)
        .shadow(color: Color.black.opacity(0.22), radius: 12, x: 0, y: 8)
    }
}

private enum WallpaperCalendarDefaultPreviewBackground {
    static let image: UIImage = {
        let size = CGSize(width: 393, height: 852)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cgContext = context.cgContext
            let rect = CGRect(origin: .zero, size: size)

            let colors = [
                UIColor(red: 0.05, green: 0.09, blue: 0.18, alpha: 1).cgColor,
                UIColor(red: 0.09, green: 0.18, blue: 0.31, alpha: 1).cgColor,
                UIColor(red: 0.12, green: 0.30, blue: 0.36, alpha: 1).cgColor,
                UIColor(red: 0.02, green: 0.08, blue: 0.13, alpha: 1).cgColor
            ]
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: [0, 0.34, 0.66, 1]
            )
            if let gradient {
                cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: rect.midX, y: rect.minY),
                    end: CGPoint(x: rect.midX, y: rect.maxY),
                    options: []
                )
            }

            drawSoftCircle(
                in: cgContext,
                center: CGPoint(x: 314, y: 146),
                radius: 118,
                color: UIColor(red: 0.27, green: 0.66, blue: 0.76, alpha: 0.36)
            )
            drawSoftCircle(
                in: cgContext,
                center: CGPoint(x: 86, y: 260),
                radius: 150,
                color: UIColor(red: 0.73, green: 0.39, blue: 0.86, alpha: 0.22)
            )
            drawSoftCircle(
                in: cgContext,
                center: CGPoint(x: 240, y: 650),
                radius: 180,
                color: UIColor(red: 0.97, green: 0.48, blue: 0.20, alpha: 0.20)
            )

            UIColor.black.withAlphaComponent(0.14).setFill()
            UIBezierPath(rect: rect).fill()

            let ridge = UIBezierPath()
            ridge.move(to: CGPoint(x: 0, y: 640))
            ridge.addCurve(to: CGPoint(x: 130, y: 574), controlPoint1: CGPoint(x: 42, y: 618), controlPoint2: CGPoint(x: 78, y: 568))
            ridge.addCurve(to: CGPoint(x: 250, y: 628), controlPoint1: CGPoint(x: 174, y: 580), controlPoint2: CGPoint(x: 208, y: 620))
            ridge.addCurve(to: CGPoint(x: 393, y: 548), controlPoint1: CGPoint(x: 306, y: 640), controlPoint2: CGPoint(x: 348, y: 562))
            ridge.addLine(to: CGPoint(x: 393, y: 852))
            ridge.addLine(to: CGPoint(x: 0, y: 852))
            ridge.close()
            UIColor(red: 0.01, green: 0.04, blue: 0.08, alpha: 0.62).setFill()
            ridge.fill()
        }
    }()

    private static func drawSoftCircle(in context: CGContext,
                                       center: CGPoint,
                                       radius: CGFloat,
                                       color: UIColor) {
        let colors = [
            color.cgColor,
            color.withAlphaComponent(0).cgColor
        ]
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: [0, 1]
        )
        guard let gradient else { return }
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: [.drawsAfterEndLocation]
        )
    }
}

private enum WallpaperCalendarAnnouncementDemo {
    static func makeSnapshot(settings: WallpaperCalendarSettings,
                             now: Date = Date()) -> WallpaperCalendarSnapshot {
        let calendar = WallpaperCalendarDataProvider.calendar
        let today = calendar.startOfDay(for: now)
        let rangeStart = startOfWeek(containing: today, calendar: calendar)
        let weekCount = settings.effectiveWeekCount.rawValue
        let dayCount = weekCount * 7
        let rangeEndExclusive = calendar.date(byAdding: .day, value: dayCount, to: rangeStart) ?? rangeStart
        let todayOffset = calendar.dateComponents([.day], from: rangeStart, to: today).day ?? 0
        let dates = (0..<dayCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: rangeStart).map { calendar.startOfDay(for: $0) }
        }
        let sampleItems = makeSampleItems(
            todayOffset: todayOffset,
            rangeStart: rangeStart,
            dayCount: dayCount,
            calendar: calendar
        )

        let weeks = stride(from: 0, to: dates.count, by: 7).compactMap { startIndex -> WallpaperCalendarWeek? in
            let endIndex = min(startIndex + 7, dates.count)
            guard endIndex - startIndex == 7 else { return nil }
            let weekDates = Array(dates[startIndex..<endIndex])
            let days = weekDates.enumerated().map { index, date in
                let offset = startIndex + index
                let items = sampleItems[offset] ?? []
                return WallpaperCalendarDay(
                    date: date,
                    previews: items,
                    rowContents: rowContents(for: items)
                )
            }

            return WallpaperCalendarWeek(
                id: weekDates[0],
                days: days,
                multiDayLayout: .empty
            )
        }

        return WallpaperCalendarSnapshot(
            generatedAt: now,
            rangeStart: rangeStart,
            rangeEndExclusive: rangeEndExclusive,
            weekdaySymbols: ["日", "月", "火", "水", "木", "金", "土"],
            weeks: weeks,
            fingerprintPayload: WallpaperCalendarFingerprintPayload(
                rangeStart: rangeStart.timeIntervalSince1970,
                rangeEndExclusive: rangeEndExclusive.timeIntervalSince1970,
                events: [],
                tasks: []
            )
        )
    }

    private static func makeSampleItems(todayOffset: Int,
                                        rangeStart: Date,
                                        dayCount: Int,
                                        calendar: Calendar) -> [Int: [WallpaperCalendarItem]] {
        let samples: [(offset: Int, title: String, category: String, color: String, hour: Int)] = [
            (todayOffset, "予定", "予定", "#0EA5E9", 10),
            (todayOffset, "予定", "仕事", "#F97316", 18),
            (todayOffset + 1, "予定", "趣味", "#22C55E", 20),
            (todayOffset + 3, "予定", "旅行", "#3B82F6", 12),
            (todayOffset + 7, "予定", "予定", "#EC4899", 11)
        ]

        return samples.reduce(into: [Int: [WallpaperCalendarItem]]()) { result, sample in
            guard (0..<dayCount).contains(sample.offset),
                  let day = calendar.date(byAdding: .day, value: sample.offset, to: rangeStart),
                  let startDate = calendar.date(bySettingHour: sample.hour, minute: 0, second: 0, of: day),
                  let endDate = calendar.date(byAdding: .hour, value: 1, to: startDate)
            else {
                return
            }

            result[sample.offset, default: []].append(
                WallpaperCalendarItem(
                    id: "\(sample.offset)-\(sample.category)-\(sample.hour)",
                    sourceID: UUID(),
                    title: sample.title,
                    categoryName: sample.category,
                    color: AppColorPalette.color(for: sample.color),
                    kind: .event,
                    startDate: startDate,
                    endDate: endDate,
                    isAllDay: false,
                    priority: nil
                )
            )
        }
    }

    private static func rowContents(for items: [WallpaperCalendarItem]) -> [WallpaperCalendarCellRowContent] {
        var rows = Array(repeating: WallpaperCalendarCellRowContent.empty, count: WallpaperCalendarDataProvider.itemLimit)
        let visibleCount = min(items.count, rows.count)
        for index in 0..<visibleCount {
            rows[index] = .item(items[index])
        }
        return rows
    }

    private static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day) ?? day
    }
}
