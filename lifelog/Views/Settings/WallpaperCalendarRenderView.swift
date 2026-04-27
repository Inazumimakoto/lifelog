//
//  WallpaperCalendarRenderView.swift
//  lifelog
//
//  Created by Codex on 2026/04/27.
//

import SwiftUI
import UIKit

struct WallpaperCalendarRenderView: View {
    let snapshot: WallpaperCalendarSnapshot
    let settings: WallpaperCalendarSettings
    let backgroundImage: UIImage?
    let isDarkAppearance: Bool

    private let gridSpacing: CGFloat = 4
    private let cellTopPadding: CGFloat = 4
    private let cellHorizontalPadding: CGFloat = 2
    private let dateRowHeight: CGFloat = 20
    private let previewRowHeight: CGFloat = 16
    private let cellRowSpacing: CGFloat = 2
    private let previewRowCornerRadius: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let layout = layoutMetrics(in: size)

            ZStack(alignment: .topLeading) {
                background(size: size)

                VStack(spacing: gridSpacing) {
                    weekdayHeader
                        .frame(width: layout.width, height: layout.weekdayHeaderHeight)

                    calendarGrid(width: layout.width, cellHeight: layout.cellHeight)
                }
                .frame(width: layout.width, height: layout.height, alignment: .top)
                .offset(x: layout.x, y: layout.y)
            }
        }
    }

    @ViewBuilder
    private func background(size: CGSize) -> some View {
        if let backgroundImage {
            Image(uiImage: backgroundImage)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()

            Color.black.opacity(isDarkAppearance ? 0.18 : 0.08)
        } else {
            (isDarkAppearance ? Color.black : Color.white)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: gridSpacing) {
            ForEach(Array(snapshot.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func calendarGrid(width: CGFloat, cellHeight: CGFloat) -> some View {
        let cellWidth = calendarGridCellWidth(for: width)

        return ZStack(alignment: .topLeading) {
            VStack(spacing: gridSpacing) {
                ForEach(snapshot.weeks) { week in
                    HStack(spacing: gridSpacing) {
                        ForEach(week.days) { day in
                            dayCell(day, width: cellWidth, height: cellHeight)
                        }
                    }
                    .frame(width: width, height: cellHeight)
                }
            }

            multiDayOverlay(width: width, cellWidth: cellWidth, cellHeight: cellHeight)
        }
        .frame(width: width, height: gridHeight(cellHeight: cellHeight), alignment: .topLeading)
    }

    private func dayCell(_ day: WallpaperCalendarDay, width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: cellRowSpacing) {
            dateLabel(for: day.date)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: dateRowHeight)

            ForEach(0..<day.rowContents.count, id: \.self) { index in
                calendarCellRowView(day.rowContents[index])
            }

            Spacer(minLength: 0)
        }
        .padding(.top, cellTopPadding)
        .padding(.horizontal, cellHorizontalPadding)
        .frame(width: width, height: height, alignment: .top)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func dateLabel(for date: Date) -> some View {
        let calendar = WallpaperCalendarDataProvider.calendar
        let dayText = String(calendar.component(.day, from: date))

        if calendar.isDateInToday(date) {
            Text(dayText)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 28, height: 28)
                .background(Color.blue, in: Circle())
                .offset(y: -4)
        } else {
            Text(dayText)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(dateTextColor(for: date))
                .frame(width: 28, height: 28, alignment: .center)
                .offset(y: -4)
        }
    }

    @ViewBuilder
    private func calendarCellRowView(_ content: WallpaperCalendarCellRowContent) -> some View {
        switch content {
        case .multiDayPlaceholder, .empty:
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: previewRowHeight)
        case .overflow(let count):
            Text("+\(count)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(secondaryTextColor)
                .padding(.horizontal, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: previewRowHeight)
        case .item(let item):
            previewBar(
                title: item.displayTitle(privacyMode: settings.privacyMode),
                color: item.color,
                leadingRadius: previewRowCornerRadius,
                trailingRadius: previewRowCornerRadius
            )
        }
    }

    private func multiDayOverlay(width: CGFloat, cellWidth: CGFloat, cellHeight: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(snapshot.weeks.enumerated()), id: \.offset) { weekIndex, week in
                ForEach(week.multiDayLayout.segments) { segment in
                    let spanLength = segment.endColumn - segment.startColumn + 1
                    let x = CGFloat(segment.startColumn) * (cellWidth + gridSpacing) + cellHorizontalPadding
                    let y = CGFloat(weekIndex) * (cellHeight + gridSpacing) + multiDayOverlayRowY(lane: segment.lane)
                    let width = CGFloat(spanLength) * cellWidth + CGFloat(max(0, spanLength - 1)) * gridSpacing - cellHorizontalPadding * 2

                    multiDayBar(segment: segment)
                        .frame(width: max(0, width), height: previewRowHeight, alignment: .leading)
                        .offset(x: x, y: y)
                }
            }
        }
        .frame(width: width, height: gridHeight(cellHeight: cellHeight), alignment: .topLeading)
    }

    private func multiDayBar(segment: WallpaperCalendarWeekMultiDaySegment) -> some View {
        let leadingRadius: CGFloat = segment.continuesBeforeWeek ? 0 : previewRowCornerRadius
        let trailingRadius: CGFloat = segment.continuesAfterWeek ? 0 : previewRowCornerRadius
        let title = segment.continuesBeforeWeek ? " " : segment.displayTitle(privacyMode: settings.privacyMode)

        return previewBar(
            title: title,
            color: segment.color,
            leadingRadius: leadingRadius,
            trailingRadius: trailingRadius
        )
        .opacity(segment.continuesBeforeWeek ? 0.92 : 1)
    }

    private func previewBar(title: String,
                            color: Color,
                            leadingRadius: CGFloat,
                            trailingRadius: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(primaryTextColor)
            .padding(.horizontal, 3)
            .padding(.vertical, 1.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: previewRowHeight)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: leadingRadius,
                    bottomLeadingRadius: leadingRadius,
                    bottomTrailingRadius: trailingRadius,
                    topTrailingRadius: trailingRadius
                )
                .fill(color.opacity(backgroundImage == nil ? 0.30 : 0.56))
            )
            .clipped()
    }

    private func layoutMetrics(in size: CGSize) -> WallpaperCalendarLayoutMetrics {
        let horizontalPadding = max(26, size.width * 0.07)
        let width = max(0, size.width - horizontalPadding * 2)
        let cellHeight = cellHeight(for: settings.weekCount)
        let weekdayHeaderHeight: CGFloat = 24
        let gridHeight = gridHeight(cellHeight: cellHeight)
        let height = weekdayHeaderHeight + gridSpacing + gridHeight
        let y = layoutTop(in: size)
        return WallpaperCalendarLayoutMetrics(
            x: horizontalPadding,
            y: y,
            width: width,
            height: height,
            cellHeight: cellHeight,
            weekdayHeaderHeight: weekdayHeaderHeight
        )
    }

    private func cellHeight(for weekCount: WallpaperCalendarWeekCount) -> CGFloat {
        switch weekCount {
        case .two:
            return 98
        case .three:
            return 92
        case .four:
            return 86
        }
    }

    private func layoutTop(in size: CGSize) -> CGFloat {
        switch settings.layoutPreset {
        case .standard:
            return size.height * 0.34
        case .avoidWidgets:
            return size.height * 0.43
        case .avoidMedia:
            return size.height * 0.26
        case .avoidWidgetsAndMedia:
            return size.height * 0.40
        }
    }

    private func gridHeight(cellHeight: CGFloat) -> CGFloat {
        let weekCount = CGFloat(max(1, snapshot.weeks.count))
        return weekCount * cellHeight + CGFloat(max(0, snapshot.weeks.count - 1)) * gridSpacing
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

    private func dateTextColor(for date: Date) -> Color {
        let weekday = WallpaperCalendarDataProvider.calendar.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 {
            return secondaryTextColor
        }
        return primaryTextColor
    }

    private var primaryTextColor: Color {
        isDarkAppearance ? Color.white.opacity(0.92) : Color.black.opacity(0.86)
    }

    private var secondaryTextColor: Color {
        isDarkAppearance ? Color.white.opacity(0.62) : Color.black.opacity(0.46)
    }
}

private struct WallpaperCalendarLayoutMetrics {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let cellHeight: CGFloat
    let weekdayHeaderHeight: CGFloat
}
