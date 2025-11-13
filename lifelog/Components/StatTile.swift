//
//  StatTile.swift
//  lifelog
//
//  Created by Codex on 2025/11/14.
//

import SwiftUI

struct StatTile: View {
    var title: String
    var value: String
    var subtitle: String?
    var action: (() -> Void)?

    init(title: String,
         value: String,
         subtitle: String? = nil,
         action: (() -> Void)? = nil) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.action = action
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    tileContent
                }
                .buttonStyle(.plain)
            } else {
                tileContent
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var tileContent: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
