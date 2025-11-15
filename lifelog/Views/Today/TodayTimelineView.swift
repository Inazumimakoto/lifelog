//
//  TodayTimelineView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct TodayTimelineView: View {
    var items: [JournalViewModel.TimelineItem]
    var anchorDate: Date
    
    // Dynamic startHour and endHour
    private var dynamicStartHour: Double {
        let allHours = items.flatMap { [hourValue($0.start), hourValue($0.end)] }
        let minDataHour = allHours.min() ?? 0
        let maxDataHour = allHours.max() ?? 24

        var effectiveStartHour = minDataHour - 2 // 2 hours padding
        var effectiveEndHour = maxDataHour + 2 // 2 hours padding

        let minSpan: Double = 12.0 // Minimum 12-hour view
        let currentSpan = effectiveEndHour - effectiveStartHour // Changed to let

        if currentSpan < minSpan {
            let midPoint = (effectiveStartHour + effectiveEndHour) / 2
            effectiveStartHour = midPoint - minSpan / 2
            effectiveEndHour = midPoint + minSpan / 2
        }
        
        // Ensure the range is always at least 24 hours if it contains overnight sleep
        let hasOvernightSleep = items.contains(where: { $0.kind == .sleep && hourValue($0.end) < hourValue($0.start) })
        if hasOvernightSleep && effectiveEndHour - effectiveStartHour < 24 {
            let midPoint = (effectiveStartHour + effectiveEndHour) / 2
            effectiveStartHour = midPoint - 12
            effectiveEndHour = midPoint + 12
        }

        return effectiveStartHour
    }

    private var dynamicEndHour: Double {
        let allHours = items.flatMap { [hourValue($0.start), hourValue($0.end)] }
        let minDataHour = allHours.min() ?? 0
        let maxDataHour = allHours.max() ?? 24

        var effectiveStartHour = minDataHour - 2 // 2 hours padding
        var effectiveEndHour = maxDataHour + 2 // 2 hours padding

        let minSpan: Double = 12.0 // Minimum 12-hour view
        let currentSpan = effectiveEndHour - effectiveStartHour // Changed to let

        if currentSpan < minSpan {
            let midPoint = (effectiveStartHour + effectiveEndHour) / 2
            effectiveStartHour = midPoint - minSpan / 2
            effectiveEndHour = midPoint + minSpan / 2
        }

        let hasOvernightSleep = items.contains(where: { $0.kind == .sleep && hourValue($0.end) < hourValue($0.start) })
        if hasOvernightSleep && effectiveEndHour - effectiveStartHour < 24 {
            let midPoint = (effectiveStartHour + effectiveEndHour) / 2
            effectiveStartHour = midPoint - 12
            effectiveEndHour = midPoint + 12
        }
        
        return effectiveEndHour
    }

    private var tasks: [JournalViewModel.TimelineItem] {
        items.filter { $0.kind == .task && $0.title.isEmpty == false }
    }

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
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [Color(.systemBackground), Color(.systemGray6)], startPoint: .top, endPoint: .bottom))
                .frame(height: height)
            TodayAxisView(height: height, startHour: dynamicStartHour, endHour: dynamicEndHour)
            TimelineGrid(height: height, startHour: dynamicStartHour, endHour: dynamicEndHour)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            ForEach(items) { item in // Changed $0 to item
                let (offset, blockHeight) = position(for: item, contentHeight: height)
                if blockHeight > 0 {
                    let detailText = item.detail == "__completed__" ? nil : item.detail
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title) // Changed $0.title to item.title
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
                    .background(item.kind == .sleep ? Color.purple.gradient : (item.kind == .event ? Color.accentColor.gradient : Color.green.gradient))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(height: blockHeight, alignment: .topLeading)
                    .offset(x: 48, y: offset)
                }
            }
        }
        .frame(width: 220, height: height)
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

    private func position(for item: JournalViewModel.TimelineItem, contentHeight: CGFloat) -> (CGFloat, CGFloat) {
        let start = hourValue(item.start)
        let end = hourValue(item.end)

        let totalHours = dynamicEndHour - dynamicStartHour
        
        let clippedStart = max(start, dynamicStartHour)
        let clippedEnd = min(end, dynamicEndHour)

        if clippedStart >= clippedEnd {
            return (0, 0)
        }

        let normalizedStart = clippedStart - dynamicStartHour
        let normalizedEnd = clippedEnd - dynamicStartHour
        
        let offset = CGFloat(normalizedStart / totalHours) * contentHeight
        let height = CGFloat((normalizedEnd - normalizedStart) / totalHours) * contentHeight
        
        return (offset, height)
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
