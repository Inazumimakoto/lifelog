//
//  CalendarLayoutModels.swift
//  lifelog
//

import SwiftUI
import UIKit

enum CalendarMode: Equatable {
    case schedule
    case review
}

enum MultiDayPosition {
    case none      // Single-day or non-multi-day
    case start     // First day of multi-day event
    case middle    // Middle day of multi-day event
    case end       // Last day of multi-day event
}

struct CalendarPreviewText: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 1
        label.lineBreakMode = .byClipping
        label.adjustsFontSizeToFitWidth = false
        label.allowsDefaultTighteningForTruncation = true
        label.textColor = .label
        label.backgroundColor = .clear
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)
        label.font = Self.previewFont
        return label
    }

    func updateUIView(_ uiView: UILabel, context: Context) {
        uiView.text = text
        uiView.font = Self.previewFont
    }

    @available(iOS 16.0, *)
    static func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize {
        let targetWidth = proposal.width ?? .greatestFiniteMagnitude
        let targetHeight = proposal.height ?? .greatestFiniteMagnitude
        let size = uiView.sizeThatFits(CGSize(width: targetWidth, height: targetHeight))
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }

    private static let previewFont: UIFont = {
        let baseFont = UIFont.systemFont(ofSize: 9, weight: .medium)
        let descriptor = baseFont.fontDescriptor
        let traits = (descriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]) ?? [:]
        var condensedTraits = traits
        condensedTraits[.width] = -0.2
        let condensedDescriptor = descriptor.addingAttributes([.traits: condensedTraits])
        return UIFont(descriptor: condensedDescriptor, size: 9)
    }()
}

struct DayPreviewItem: Identifiable {
    enum Kind {
        case event
        case task
    }
    let id: String
    let title: String
    let color: Color
    let timeText: String?
    let kind: Kind

    // Multi-day event info (nil for tasks or when not needed)
    let eventStartDate: Date?
    let eventEndDate: Date?

    var isMultiDayEvent: Bool {
        guard kind == .event, let start = eventStartDate, let end = eventEndDate else { return false }
        let calendar = Calendar.current
        let adjustedEnd = calendar.date(byAdding: .second, value: -1, to: end) ?? end
        return !calendar.isDate(start, inSameDayAs: adjustedEnd)
    }

    func multiDayPosition(on date: Date) -> MultiDayPosition {
        guard isMultiDayEvent, let start = eventStartDate, let end = eventEndDate else {
            return .none
        }
        let calendar = Calendar.current
        let isStart = calendar.isDate(date, inSameDayAs: start)
        let adjustedEnd = calendar.date(byAdding: .second, value: -1, to: end) ?? end
        let isEnd = calendar.isDate(date, inSameDayAs: adjustedEnd)

        if isStart { return .start }
        if isEnd { return .end }
        return .middle
    }
}

struct CalendarWeekMultiDaySegment: Identifiable {
    let id: String
    let eventID: UUID
    let title: String
    let color: Color
    let lane: Int
    let startColumn: Int
    let endColumn: Int
    let continuesBeforeWeek: Bool
    let continuesAfterWeek: Bool
}

struct CalendarDayMultiDayState {
    let visibleLaneCount: Int
    let occupiedVisibleLanes: Set<Int>
    let hiddenMultiDayCount: Int

    static let empty = CalendarDayMultiDayState(visibleLaneCount: 0,
                                                occupiedVisibleLanes: [],
                                                hiddenMultiDayCount: 0)
}

struct CalendarWeekMultiDayLayout {
    let visibleLaneCount: Int
    let dayStates: [CalendarDayMultiDayState]
    let segments: [CalendarWeekMultiDaySegment]

    static let empty = CalendarWeekMultiDayLayout(visibleLaneCount: 0,
                                                  dayStates: Array(repeating: .empty, count: 7),
                                                  segments: [])
}

enum CalendarCellRowContent {
    case multiDayPlaceholder
    case item(DayPreviewItem)
    case overflow(Int)
    case empty
}
