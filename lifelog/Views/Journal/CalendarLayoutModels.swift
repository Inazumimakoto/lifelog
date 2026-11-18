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

struct CalendarPreviewText: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let textColor: UIColor

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 1
        label.lineBreakMode = .byClipping
        label.adjustsFontSizeToFitWidth = false
        label.allowsDefaultTighteningForTruncation = true
        label.backgroundColor = .clear
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ uiView: UILabel, context: Context) {
        uiView.text = text
        uiView.font = Self.baseFont.withSize(fontSize)
        uiView.textColor = textColor
    }

    @available(iOS 16.0, *)
    static func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize {
        let targetWidth = proposal.width ?? .greatestFiniteMagnitude
        let targetHeight = proposal.height ?? .greatestFiniteMagnitude
        let size = uiView.sizeThatFits(CGSize(width: targetWidth, height: targetHeight))
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }

    static func rowHeight(for fontSize: CGFloat) -> CGFloat {
        ceil(baseFont.withSize(fontSize).lineHeight) + 3
    }

    private static let baseFont: UIFont = {
        let baseFont = UIFont.systemFont(ofSize: 9, weight: .medium)
        let descriptor = baseFont.fontDescriptor
        let traits = (descriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]) ?? [:]
        var condensedTraits = traits
        condensedTraits[.width] = -0.2
        let condensedDescriptor = descriptor.addingAttributes([.traits: condensedTraits])
        return UIFont(descriptor: condensedDescriptor, size: 9)
    }()
}

/// Month, week and settings preview use the same fixed-size day cells (requirements §4.2).
struct CalendarGridMetrics {
    static let cellHeight: CGFloat = 88
    static let dateHeight: CGFloat = 22
    static let topPadding: CGFloat = 4
    static let rowSpacing: CGFloat = 2
    static let gridSpacing: CGFloat = 4

    let rowHeight: CGFloat

    init(fontSize: CGFloat) {
        rowHeight = CalendarPreviewText.rowHeight(for: fontSize)
    }

    var laneCount: Int {
        let available = Self.cellHeight - Self.topPadding - Self.dateHeight
        return min(4, Int(available / (rowHeight + Self.rowSpacing)))
    }

    func rowOffset(for lane: Int) -> CGFloat {
        Self.topPadding + Self.dateHeight + Self.rowSpacing + CGFloat(lane) * (rowHeight + Self.rowSpacing)
    }
}
