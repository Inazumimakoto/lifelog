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
    private let cellTopPadding = WallpaperCalendarGridStyle.topPadding
    private let cellHorizontalPadding: CGFloat = 0
    private let cellHeight = WallpaperCalendarGridStyle.cellHeight
    private let dateRowHeight = WallpaperCalendarGridStyle.dateHeight
    private var previewRowHeight: CGFloat { snapshot.gridStyle.rowHeight }
    private let cellRowSpacing = WallpaperCalendarGridStyle.rowSpacing
    private let cellCornerRadius: CGFloat = 10
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
            WallpaperCalendarPhotoBackgroundView(
                image: backgroundImage,
                adjustment: settings.backgroundAdjustment
            )
                .frame(width: size.width, height: size.height)

            Color.black.opacity(isDarkAppearance ? 0.18 : 0.08)
        } else {
            AppColorPalette.color(for: settings.backgroundColorToken)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(snapshot.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                    .shadow(color: textShadowColor, radius: textShadowRadius, x: 0, y: 1)
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
        let isToday = WallpaperCalendarDataProvider.calendar.isDateInToday(day.date)
        return VStack(alignment: .leading, spacing: cellRowSpacing) {
            dateLabel(for: day.date)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: dateRowHeight)

            ForEach(0..<day.rowContents.count, id: \.self) { index in
                calendarCellRowView(day.rowContents[index], isToday: isToday)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, cellTopPadding)
        .padding(.horizontal, cellHorizontalPadding)
        .frame(width: width, height: height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: cellCornerRadius)
                .fill(
                    isToday
                    ? WallpaperCalendarGridStyle.todayColor.opacity(WallpaperCalendarGridStyle.todayOpacity)
                    : Color.clear
                )
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func dateLabel(for date: Date) -> some View {
        let calendar = WallpaperCalendarDataProvider.calendar
        let dayText = String(calendar.component(.day, from: date))

        Text(dayText)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(dateTextColor(for: date))
            .shadow(color: textShadowColor, radius: textShadowRadius, x: 0, y: 1)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func calendarCellRowView(_ content: WallpaperCalendarCellRowContent, isToday: Bool) -> some View {
        switch content {
        case .multiDayPlaceholder, .empty:
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: previewRowHeight)
        case .overflow(let count):
            Text("+\(count)")
                .font(.system(size: snapshot.gridStyle.preferences.fontSize))
                .lineLimit(1)
                .foregroundStyle(secondaryTextColor)
                .shadow(color: textShadowColor, radius: textShadowRadius, x: 0, y: 1)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: previewRowHeight)
        case .item(let item):
            previewBar(
                title: item.displayTitle(privacyMode: settings.privacyMode),
                color: item.color,
                isToday: isToday,
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
                    let y = CGFloat(weekIndex) * (cellHeight + gridSpacing) + snapshot.gridStyle.rowOffset(segment.lane)
                    let width = CGFloat(spanLength) * cellWidth + CGFloat(max(0, spanLength - 1)) * gridSpacing - cellHorizontalPadding * 2

                    multiDayBar(segment: segment, startDate: week.days[segment.startColumn].date)
                        .frame(width: max(0, width), height: previewRowHeight, alignment: .leading)
                        .offset(x: x, y: y)
                }
            }
        }
        .frame(width: width, height: gridHeight(cellHeight: cellHeight), alignment: .topLeading)
    }

    private func multiDayBar(segment: WallpaperCalendarWeekMultiDaySegment, startDate: Date) -> some View {
        let leadingRadius: CGFloat = segment.continuesBeforeWeek ? 0 : previewRowCornerRadius
        let trailingRadius: CGFloat = segment.continuesAfterWeek ? 0 : previewRowCornerRadius
        let title = snapshot.gridStyle.title(for: segment, privacyMode: settings.privacyMode)

        return previewBar(
            title: title,
            color: segment.color,
            isToday: WallpaperCalendarDataProvider.calendar.isDateInToday(startDate),
            leadingRadius: leadingRadius,
            trailingRadius: trailingRadius
        )
    }

    private func previewBar(title: String,
                            color: Color,
                            isToday: Bool,
                            leadingRadius: CGFloat,
                            trailingRadius: CGFloat) -> some View {
        let attributedTitle = snapshot.gridStyle.attributedTitle(title, category: color, settings: settings,
                                                                 hasPhoto: backgroundImage != nil, isToday: isToday)
        return WallpaperCalendarEventLabel(title: attributedTitle)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: previewRowHeight)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: leadingRadius,
                    bottomLeadingRadius: leadingRadius,
                    bottomTrailingRadius: trailingRadius,
                    topTrailingRadius: trailingRadius
                )
                .fill(color.opacity(snapshot.gridStyle.preferences.opacity))
            )
            .clipped()
    }

    private func layoutMetrics(in size: CGSize) -> WallpaperCalendarLayoutMetrics {
        let horizontalPadding = max(26, size.width * 0.07)
        let width = max(0, size.width - horizontalPadding * 2)
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

    private func layoutTop(in size: CGSize) -> CGFloat {
        size.height * 0.36
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

    private func dateTextColor(for date: Date) -> Color {
        let weekday = WallpaperCalendarDataProvider.calendar.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 {
            return secondaryTextColor
        }
        return primaryTextColor
    }

    private var primaryTextColor: Color {
        isDarkAppearance ? Color.white : Color.black.opacity(0.92)
    }

    private var secondaryTextColor: Color {
        isDarkAppearance ? Color.white.opacity(0.78) : Color.black.opacity(0.62)
    }

    private var textShadowColor: Color {
        isDarkAppearance ? Color.black.opacity(0.45) : Color.clear
    }

    private var textShadowRadius: CGFloat {
        isDarkAppearance ? 1.2 : 0
    }
}

private struct WallpaperCalendarEventLabel: UIViewRepresentable {
    let title: NSAttributedString

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 1
        label.lineBreakMode = .byClipping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.attributedText = title
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
