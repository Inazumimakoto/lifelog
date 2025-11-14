//
//  TodayTimelineView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct TodayTimelineView: View {
    var items: [JournalViewModel.TimelineItem]
    private let startHour: Double = 0
    private let endHour: Double = 24

    private var tasks: [JournalViewModel.TimelineItem] {
        items.filter { $0.kind == .task && $0.title.isEmpty == false }
    }

    var body: some View {
        let timelineHeight: CGFloat = 360
        HStack(alignment: .top, spacing: 16) {
            timelineColumn(height: timelineHeight)
            tasksColumn
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .frame(height: timelineHeight + 48)
    }

    private var tasksColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日のタスク")
                .font(.caption)
                .foregroundStyle(.secondary)
            let activeTasks = items.filter { $0.kind == .task && $0.detail != "__completed__" }
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
            TodayAxisView(height: height)
            TimelineGrid(height: height, startHour: startHour, endHour: endHour)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            ForEach(items) { item in
                let (offset, blockHeight) = position(for: item, contentHeight: height)
                let detailText = item.detail == "__completed__" ? nil : item.detail
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
                .background(item.kind == .event ? Color.accentColor.gradient : Color.green.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(height: blockHeight, alignment: .topLeading)
                .offset(x: 48, y: offset)
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
        Double(Calendar.current.component(.hour, from: date)) + Double(Calendar.current.component(.minute, from: date)) / 60
    }

    private func position(for item: JournalViewModel.TimelineItem, contentHeight: CGFloat) -> (CGFloat, CGFloat) {
        let start = hourValue(item.start)
        var end = hourValue(item.end)
        var normalizedStart = max(start - startHour, 0)
        var normalizedEnd = max(end - startHour, 0)
        if normalizedEnd < normalizedStart {
            normalizedEnd += 24
        }
        let totalHours = endHour - startHour
        normalizedStart = min(normalizedStart, totalHours)
        normalizedEnd = min(normalizedEnd, totalHours + 6)
        let offset = CGFloat(normalizedStart / totalHours) * contentHeight
        let height = CGFloat(max((normalizedEnd - normalizedStart) / totalHours, 0.05)) * contentHeight
        return (offset, height)
    }
}

private struct TodayAxisView: View {
    var height: CGFloat
    private let startHour: Double = 0
    private let endHour: Double = 24

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(stride(from: startHour, through: endHour, by: 4)), id: \.self) { hour in
                Text(String(format: "%02.0f:00", hour))
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
