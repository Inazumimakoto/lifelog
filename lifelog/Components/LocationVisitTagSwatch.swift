//
//  LocationVisitTagSwatch.swift
//  lifelog
//

import SwiftUI

/// docs/ui-guidelines.md: 訪問タグの色を地図とタグ選択で共通に使う。
struct LocationVisitTagSwatch: View {
    let colorHex: String
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(Color(hex: colorHex) ?? .gray)
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
