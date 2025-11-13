//
//  TodayTimelineView.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct TodayTimelineView: View {
    var items: [JournalViewModel.TimelineItem]
    private let startHour: Double = 6
    private let endHour: Double = 24

    var body: some View {
        let timelineHeight: CGFloat = 220
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                TodayAxisView(height: timelineHeight)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: timelineHeight)
                    ForEach(items) { item in
                        let (offset, blockHeight) = position(for: item, contentHeight: timelineHeight)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                            if let detail = item.detail, detail.isEmpty == false {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                        .padding(6)
                        .frame(maxWidth: 200, alignment: .leading)
                        .background(item.kind == .event ? Color.accentColor : Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .frame(height: blockHeight, alignment: .topLeading)
                        .offset(y: offset)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.trailing, 12)
        }
        .frame(height: timelineHeight + 20)
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
    private let startHour: Double = 6
    private let endHour: Double = 24

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(stride(from: startHour, through: endHour, by: 3)), id: \.self) { hour in
                Text(String(format: "%02.0f:00", hour))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .offset(y: yOffset(for: hour))
            }
        }
        .frame(width: 45, height: height)
    }

    private func yOffset(for hour: Double) -> CGFloat {
        let ratio = CGFloat((hour - startHour) / (endHour - startHour))
        return ratio * height - 6
    }
}
