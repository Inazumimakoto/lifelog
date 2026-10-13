//
//  TodayTimelineView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct TodayTimelineView: View {
    @ObservedObject private var categoryPalette = CategoryPaletteObserver.shared
    var items: [JournalViewModel.TimelineItem]
    var anchorDate: Date
    
    var body: some View {
        let timelineHeight: CGFloat = 360
        HStack(alignment: .top, spacing: 16) {
            timelineColumn(height: timelineHeight)
            // tasksColumn // Removed reference from body
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .frame(height: timelineHeight + 48)
    }

    private var tasksColumn: some View { // Re-added tasksColumn as private var
        VStack(alignment: .leading, spacing: 12) {
            Text("今日のタスク")
                .font(.caption)
                .foregroundStyle(.secondary)
            let activeTasks = items.filter { $0.kind == .task && $0.title.isEmpty == false }
            if activeTasks.isEmpty {
                Text("予定されたタスクはありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activeTasks) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(task.detail ?? "詳細なし")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(intervalText(start: task.start, end: task.end))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func timelineColumn(height: CGFloat) -> some View {
        let bounds = TimelineHourBounds(items: items.map { item in
            let range = effectiveRange(for: item)
            return .init(start: hourValue(range.start), end: hourValue(range.end), isSleep: item.kind == .sleep)
        })
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [Color(.systemBackground), Color(.systemGray6)], startPoint: .top, endPoint: .bottom))
                .frame(height: height)
            TodayAxisView(height: height, startHour: bounds.start, endHour: bounds.end)
            TimelineGrid(height: height, startHour: bounds.start, endHour: bounds.end)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            ForEach(items) { item in
                let (offset, blockHeight) = position(for: item, contentHeight: height, bounds: bounds)
                if blockHeight > 0 {
                    let detailText = timelineDetailText(for: item)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        if let detail = detailText, detail.isEmpty == false {
                            Text(detail)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: 240, alignment: .leading)
                    .background(color(for: item))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(height: blockHeight, alignment: .topLeading)
                    .offset(x: 48, y: offset)
                }
            }
        }
        .frame(width: 220, height: height)
    }

    private func timelineDetailText(for item: JournalViewModel.TimelineItem) -> String? {
        if item.kind == .event,
           let eventDetail = item.eventDetail,
           eventDetail.isEmpty == false {
            return eventDetail
        }
        guard item.detail != "__completed__" else { return nil }
        if item.kind == .event, let detail = item.detail {
            return CategoryPalette.displayName(for: detail)
        }
        return item.detail
    }

    private func intervalText(start: Date, end: Date) -> String {
        let startText = start.jaMonthDayString
        let endText = end.jaMonthDayString
        if startText == endText {
            return startText
        }
        return "\(startText) 〜 \(endText)"
    }

    private func hourValue(_ date: Date) -> Double {
        let calendar = Calendar.current
        let dayDifference = calendar.dateComponents([.day], from: calendar.startOfDay(for: anchorDate), to: calendar.startOfDay(for: date)).day ?? 0
        
        let hour = Double(calendar.component(.hour, from: date))
        let minute = Double(calendar.component(.minute, from: date)) // Changed calendar.current.component to calendar.component
        
        return hour + (minute / 60.0) + (Double(dayDifference) * 24.0)
    }

    private func position(for item: JournalViewModel.TimelineItem,
                          contentHeight: CGFloat,
                          bounds: TimelineHourBounds) -> (CGFloat, CGFloat) {
        let range = effectiveRange(for: item)
        let start = hourValue(range.start)
        let end = hourValue(range.end)

        let totalHours = bounds.end - bounds.start
        
        let clippedStart = max(start, bounds.start)
        let clippedEnd = min(end, bounds.end)

        if clippedStart >= clippedEnd {
            return (0, 0)
        }

        let normalizedStart = clippedStart - bounds.start
        let normalizedEnd = clippedEnd - bounds.start
        
        let offset = CGFloat(normalizedStart / totalHours) * contentHeight
        let height = CGFloat((normalizedEnd - normalizedStart) / totalHours) * contentHeight
        
        return (offset, height)
    }

    private func effectiveRange(for item: JournalViewModel.TimelineItem) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: anchorDate)
        if item.isAllDay {
            let end = calendar.date(byAdding: .minute, value: 90, to: dayStart) ?? dayStart
            return (start: dayStart, end: end)
        }
        return (start: item.start, end: item.end)
    }

    private func color(for item: JournalViewModel.TimelineItem) -> Color {
        switch item.kind {
        case .event:
            return CategoryPalette.color(for: item.detail ?? "")
        case .task:
            return .green
        case .sleep:
            return .purple
        }
    }
}

private struct TodayAxisView: View {
    var height: CGFloat
    var startHour: Double
    var endHour: Double

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(stride(from: startHour, through: endHour, by: 4)), id: \.self) { hour in
                let displayHour = (Int(hour) % 24 + 24) % 24
                Text(String(format: "%02d:00", displayHour))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .offset(y: yOffset(for: hour))
            }
        }
        .frame(width: 40, height: height)
    }

    private func yOffset(for hour: Double) -> CGFloat {
        let ratio = CGFloat((hour - startHour) / (endHour - startHour))
        return ratio * height - 6
    }
}

private struct TimelineGrid: View {
    var height: CGFloat
    var startHour: Double
    var endHour: Double

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(stride(from: startHour, through: endHour, by: 3)), id: \.self) { hour in
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 1)
                    .offset(y: yOffset(for: hour) - 0.5)
            }
        }
        .frame(height: height)
    }

    private func yOffset(for hour: Double) -> CGFloat {
        let ratio = CGFloat((hour - startHour) / (endHour - startHour))
        return ratio * height
    }
}
